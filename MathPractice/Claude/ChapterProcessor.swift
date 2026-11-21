import Foundation
import SwiftData
import UIKit

/// Runs concurrent async work with a concurrency limit, preserving input order in results.
func concurrentMap<T: Sendable, R: Sendable>(_ items: [T], limit: Int, _ body: @escaping @Sendable (T) async throws -> R) async rethrows -> [R] {
    try await withThrowingTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        func launch() {
            guard next < items.count else { return }
            let i = next, item = items[i]
            next += 1
            group.addTask { (i, try await body(item)) }
        }
        for _ in 0..<min(limit, items.count) { launch() }
        while let (i, r) = try await group.next() {
            results[i] = r
            launch()
        }
        return results.map { $0! }
    }
}

/// Turns a chapter's scanned pages into concepts + verified questions.
///
/// Built for large chapters (60–100+ pages, hundreds of questions):
/// - pages are read in small batches, and each page's result is saved immediately, so an interruption
///   resumes from the next unread page instead of starting over;
/// - once questions are organized, the chapter can be practiced while the rest are still being solved
///   (solved in book order, so the first concepts are ready first);
/// - the screen is kept awake while work is running, since iOS pauses apps when the iPad sleeps.
@MainActor
final class ChapterProcessor: ObservableObject {
    static let shared = ChapterProcessor()
    static let pagesPerBatch = 3
    static let extractConcurrency = 3
    static let solveConcurrency = 6

    @Published private(set) var running: Set<UUID> = []
    var services: ClaudeServices = .live

    func isRunning(_ chapter: Chapter) -> Bool { running.contains(chapter.id) }

    func start(_ chapter: Chapter, context: ModelContext) {
        guard !running.contains(chapter.id) else { return }
        running.insert(chapter.id)
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            defer {
                running.remove(chapter.id)
                if running.isEmpty { UIApplication.shared.isIdleTimerDisabled = false }
            }
            do {
                try await process(chapter, context: context)
            } catch {
                chapter.status = .failed
                chapter.errorMessage = error.localizedDescription
                try? context.save()
            }
        }
    }

    /// Restarts any chapter whose processing was interrupted (app closed, iPad slept).
    func resumeInterrupted(_ chapters: [Chapter], context: ModelContext) {
        for chapter in chapters where chapter.status == .processing && !isRunning(chapter) {
            start(chapter, context: context)
        }
    }

    private func report(_ chapter: Chapter, _ message: String, _ fraction: Double, _ context: ModelContext) {
        chapter.progressMessage = message
        chapter.progressFraction = fraction
        try? context.save()
    }

    func process(_ chapter: Chapter, context: ModelContext) async throws {
        chapter.status = .processing
        chapter.errorMessage = nil

        if chapter.questions.isEmpty {
            try await extractPages(chapter, context: context)
            try await organize(chapter, context: context)
        }
        ensureSkills(chapter, context: context)
        try await solveAll(chapter, context: context)
        ensureSkills(chapter, context: context)

        chapter.status = .ready
        report(chapter, "Ready", 1, context)
    }

    // MARK: Step 1 — read pages (resumable)

    private func extractPages(_ chapter: Chapter, context: ModelContext) async throws {
        let pages = chapter.sortedPages
        guard !pages.isEmpty else { throw ClaudeClient.ClientError.decoding("This chapter has no pages.") }

        let pending = pages.indices.filter { pages[$0].extractionJSON == nil }
        guard !pending.isEmpty else { return }

        // Batches of consecutive unread pages; each also gets the page before it as section context.
        var batches: [[Int]] = []
        for i in pending {
            if let last = batches.last?.last, last == i - 1, batches[batches.count - 1].count < Self.pagesPerBatch {
                batches[batches.count - 1].append(i)
            } else {
                batches.append([i])
            }
        }
        struct Job: Sendable { let indices: [Int]; let images: [Data]; let flags: [Bool]; let context: Data? }
        let jobs = batches.map { idx in
            Job(indices: idx,
                images: idx.map { ImageUtils.jpegForAPI(pages[$0].imageData) ?? pages[$0].imageData },
                flags: idx.map { pages[$0].isAnswerKey },
                context: idx.first.flatMap { $0 > 0 ? ImageUtils.jpegForAPI(pages[$0 - 1].imageData, maxEdge: 1000) : nil })
        }

        let done = pages.count - pending.count
        var finished = done
        report(chapter, "Reading pages (\(finished)/\(pages.count))…", 0.02, context)
        let services = self.services

        try await withThrowingTaskGroup(of: (Job, ExtractionDTO).self) { group in
            var iterator = jobs.makeIterator()
            func launch() {
                guard let job = iterator.next() else { return }
                group.addTask { (job, try await services.extract(pages: job.images, answerKeyFlags: job.flags, contextPage: job.context)) }
            }
            for _ in 0..<Self.extractConcurrency { launch() }
            while let (job, dto) = try await group.next() {
                save(dto, to: job.indices.map { pages[$0] })
                finished += job.indices.count
                report(chapter, "Reading pages (\(finished)/\(pages.count))…", 0.25 * Double(finished) / Double(pages.count), context)
                launch()
            }
        }
    }

    /// Splits one batch's result across its pages and saves it right away.
    private func save(_ dto: ExtractionDTO, to batchPages: [PageImage]) {
        let encoder = JSONEncoder()
        for (i, page) in batchPages.enumerated() {
            let pageDTO = ExtractionDTO(
                sections: i == 0 ? dto.sections : [],
                worked_examples: i == 0 ? dto.worked_examples : [],
                questions: dto.questions.filter { min(max($0.page_number, 1), batchPages.count) == i + 1 },
                answer_key: i == 0 ? dto.answer_key : [])
            page.extractionJSON = (try? encoder.encode(pageDTO)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
    }

    // MARK: Step 2 — organize into concepts

    private struct RawQuestion {
        let ref: String
        let section: String
        let text: String
        let figure: Data?
        let pageIndex: Int
    }

    private func organize(_ chapter: Chapter, context: ModelContext) async throws {
        let pages = chapter.sortedPages
        let decoder = JSONDecoder()
        var raw: [RawQuestion] = []
        var sections: [ExtractionDTO.Section] = []
        var examples: [ExtractionDTO.Example] = []
        var keys: [ExtractionDTO.Key] = []

        for (index, page) in pages.enumerated() {
            guard let json = page.extractionJSON?.data(using: .utf8),
                  let dto = try? decoder.decode(ExtractionDTO.self, from: json) else { continue }
            for s in dto.sections where !sections.contains(where: { $0.heading == s.heading }) { sections.append(s) }
            examples += dto.worked_examples
            keys += dto.answer_key
            guard !page.isAnswerKey else { continue }
            for q in dto.questions {
                var figure: Data?
                if q.has_figure, q.figure_box.width > 0, q.figure_box.height > 0 {
                    figure = ImageUtils.crop(page.imageData, x: q.figure_box.x, y: q.figure_box.y,
                                             width: q.figure_box.width, height: q.figure_box.height)
                }
                raw.append(RawQuestion(ref: q.book_ref, section: q.section_heading, text: q.text, figure: figure, pageIndex: index))
            }
        }
        guard !raw.isEmpty else {
            throw ClaudeClient.ClientError.decoding("No exercises were found on these pages. Check that the scans are clear.")
        }

        report(chapter, "Organizing \(raw.count) questions into concepts…", 0.27, context)
        let plan = try await services.organize(questions: raw.map { ($0.ref, $0.section, $0.text) },
                                               sections: sections, examples: examples)

        chapter.title = plan.chapter_title.isEmpty || chapter.title != "New chapter" ? chapter.title : plan.chapter_title
        var concepts: [Concept] = []
        for (i, c) in plan.concepts.enumerated() {
            let concept = Concept(name: c.name, summary: c.summary, bookOrder: i, workedExample: c.worked_example)
            concept.chapter = chapter
            context.insert(concept)
            concepts.append(concept)
        }
        if concepts.isEmpty {
            let concept = Concept(name: chapter.title, summary: "", bookOrder: 0)
            concept.chapter = chapter
            context.insert(concept)
            concepts.append(concept)
        }

        let answers = AnswerKeyMatcher(keys: keys, questionRefs: raw.map(\.ref))
        let assignments = Dictionary(plan.assignments.map { ($0.question_number, $0) }, uniquingKeysWith: { a, _ in a })
        for (i, r) in raw.enumerated() {
            let a = assignments[i + 1]
            let question = Question(text: r.text, difficulty: min(max(a?.difficulty ?? 1, 1), 3), source: .book, bookRef: r.ref)
            question.figureData = r.figure
            question.pageIndex = r.pageIndex
            question.estimatedSeconds = min(max(a?.estimated_seconds ?? 120, 20), 1200)
            question.answerKeyAnswer = answers.answer(for: r.ref)
            question.concept = concepts[min(max((a?.concept_number ?? 1) - 1, 0), concepts.count - 1)]
            question.chapter = chapter
            context.insert(question)
        }
        try context.save()
    }

    // MARK: Step 3 — solve (chapter is practicable while this runs)

    private func solveAll(_ chapter: Chapter, context: ModelContext) async throws {
        // Book order: earliest concepts and easiest questions first, so practice can start right away.
        let pending = chapter.questions
            .filter { $0.referenceAnswer.isEmpty && $0.status != .retired }
            .sorted { a, b in
                let ca = a.concept?.bookOrder ?? 0, cb = b.concept?.bookOrder ?? 0
                if ca != cb { return ca < cb }
                if a.difficulty != b.difficulty { return a.difficulty < b.difficulty }
                return (a.pageIndex ?? 0) < (b.pageIndex ?? 0)
            }
        guard !pending.isEmpty else { return }
        let total = chapter.questions.count
        var done = total - pending.count
        let solvingMessage = { "Solving questions (\(done)/\(total)) — you can start practicing" }
        report(chapter, solvingMessage(), 0.3, context)

        let inputs = pending.map { q in
            (q.id, QuestionContext(text: q.text, figureJPEG: q.figureData, conceptName: q.concept?.name ?? ""), q.answerKeyAnswer)
        }
        let services = self.services
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })

        try await withThrowingTaskGroup(of: (UUID, Result<VerifiedSolution, Error>).self) { group in
            var iterator = inputs.makeIterator()
            func launch() {
                guard let (id, ctx, key) = iterator.next() else { return }
                group.addTask {
                    do { return (id, .success(try await services.solveVerified(ctx, answerKey: key))) }
                    catch { return (id, .failure(error)) }
                }
            }
            for _ in 0..<Self.solveConcurrency { launch() }
            while let (id, result) = try await group.next() {
                if let q = byID[id] {
                    switch result {
                    case let .success(s):
                        q.referenceSolution = s.solution
                        q.referenceAnswer = s.finalAnswer
                        q.status = s.trusted ? .ok : .needsCheck
                        q.reviewNote = s.note
                    case let .failure(error):
                        if case ClaudeClient.ClientError.missingAPIKey = error { throw error }
                        q.status = .needsCheck
                        q.reviewNote = "Couldn't solve automatically: \(error.localizedDescription)"
                        q.referenceAnswer = "?"
                    }
                }
                done += 1
                report(chapter, solvingMessage(), 0.3 + 0.7 * Double(done) / Double(total), context)
                launch()
            }
        }
    }

    func ensureSkills(_ chapter: Chapter, context: ModelContext) {
        for concept in chapter.concepts {
            let levels = Set(concept.questions.map(\.difficulty))
            for d in levels where chapter.skill(concept: concept, difficulty: d) == nil {
                let skill = SkillState(concept: concept, difficulty: d)
                skill.chapter = chapter
                context.insert(skill)
            }
        }
        try? context.save()
    }
}

/// Matches answer-key entries to questions. Refs look like "3.2 #14b"; exercise numbers repeat across
/// sections, so match on section + label, and fall back to the label alone only when it's unambiguous.
struct AnswerKeyMatcher {
    private var byFull: [String: String] = [:]
    private var byLabel: [String: [String]] = [:]
    private var questionLabelCounts: [String: Int] = [:]

    init(keys: [ExtractionDTO.Key], questionRefs: [String]) {
        for k in keys {
            byFull[Self.full(k.book_ref)] = k.answer
            byLabel[Self.label(k.book_ref), default: []].append(k.answer)
        }
        for ref in questionRefs { questionLabelCounts[Self.label(ref), default: 0] += 1 }
    }

    func answer(for ref: String) -> String? {
        if let a = byFull[Self.full(ref)] { return a }
        let label = Self.label(ref)
        if questionLabelCounts[label] == 1, let answers = byLabel[label], answers.count == 1 { return answers[0] }
        return nil
    }

    /// "3.2 #14b" → "3.2|14b"; "Section 3.2, #14(b)" → "3.2|14b".
    static func full(_ ref: String) -> String {
        let parts = ref.lowercased().split(separator: "#", maxSplits: 1)
        let section = parts.count > 1 ? String(parts[0]) : ""
        let sectionKey = section.filter { $0.isNumber || $0 == "." || $0.isLetter }
            .replacingOccurrences(of: "section", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return sectionKey + "|" + label(ref)
    }

    static func label(_ ref: String) -> String {
        let lowered = ref.lowercased()
        let tail = lowered.split(separator: "#").last.map(String.init) ?? lowered
        let lastToken = tail.split(whereSeparator: { $0 == " " }).last.map(String.init) ?? tail
        return lastToken.filter { $0.isLetter || $0.isNumber }
    }
}
