import Foundation
import SwiftData

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

/// Turns a chapter's scanned pages into concepts + verified questions. Restartable: finished steps are skipped.
@MainActor
final class ChapterProcessor: ObservableObject {
    static let shared = ChapterProcessor()

    @Published private(set) var running: Set<UUID> = []
    var services: ClaudeServices = .live

    func isRunning(_ chapter: Chapter) -> Bool { running.contains(chapter.id) }

    func start(_ chapter: Chapter, context: ModelContext) {
        guard !running.contains(chapter.id) else { return }
        running.insert(chapter.id)
        Task {
            defer { running.remove(chapter.id) }
            do {
                try await process(chapter, context: context)
            } catch {
                chapter.status = .failed
                chapter.errorMessage = error.localizedDescription
                try? context.save()
            }
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
            try await extractAndOrganize(chapter, context: context)
        }
        try await solveAll(chapter, context: context)
        ensureSkills(chapter, context: context)

        chapter.status = .ready
        report(chapter, "Ready", 1, context)
    }

    // MARK: Extract + organize

    private struct RawQuestion {
        let ref: String
        let section: String
        let text: String
        let figure: Data?
        let pageIndex: Int
    }

    private func extractAndOrganize(_ chapter: Chapter, context: ModelContext) async throws {
        let pages = chapter.sortedPages
        guard !pages.isEmpty else { throw ClaudeClient.ClientError.decoding("This chapter has no pages.") }
        report(chapter, "Reading \(pages.count) pages…", 0.05, context)

        let apiImages = pages.map { ImageUtils.jpegForAPI($0.imageData) ?? $0.imageData }
        let flags = pages.map(\.isAnswerKey)
        let batchSize = 5
        let batches = stride(from: 0, to: pages.count, by: batchSize).map { start in
            (start, Array(apiImages[start..<min(start + batchSize, pages.count)]), Array(flags[start..<min(start + batchSize, pages.count)]))
        }
        let services = self.services
        let results = try await concurrentMap(batches, limit: 3) { batch in
            (batch.0, try await services.extract(pages: batch.1, answerKeyFlags: batch.2))
        }

        var raw: [RawQuestion] = []
        var sections: [ExtractionDTO.Section] = []
        var examples: [ExtractionDTO.Example] = []
        var answerKey: [String: String] = [:]
        for (offset, dto) in results {
            for s in dto.sections where !sections.contains(where: { $0.heading == s.heading }) { sections.append(s) }
            examples += dto.worked_examples
            for k in dto.answer_key { answerKey[Self.refKey(k.book_ref)] = k.answer }
            for q in dto.questions {
                let pageIndex = min(max(offset + q.page_number - 1, 0), pages.count - 1)
                guard !pages[pageIndex].isAnswerKey else { continue }
                var figure: Data?
                if q.has_figure, q.figure_box.width > 0, q.figure_box.height > 0 {
                    figure = ImageUtils.crop(pages[pageIndex].imageData, x: q.figure_box.x, y: q.figure_box.y,
                                             width: q.figure_box.width, height: q.figure_box.height)
                }
                raw.append(RawQuestion(ref: q.book_ref, section: q.section_heading, text: q.text, figure: figure, pageIndex: pageIndex))
            }
        }
        guard !raw.isEmpty else {
            throw ClaudeClient.ClientError.decoding("No exercises were found on these pages. Check that the scans are clear.")
        }

        report(chapter, "Organizing \(raw.count) questions into concepts…", 0.25, context)
        let plan = try await services.organize(questions: raw.map { ($0.ref, $0.section, $0.text) },
                                               sections: sections, examples: examples)

        chapter.title = plan.chapter_title.isEmpty ? chapter.title : plan.chapter_title
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

        let assignments = Dictionary(plan.assignments.map { ($0.question_number, $0) }, uniquingKeysWith: { a, _ in a })
        for (i, r) in raw.enumerated() {
            let a = assignments[i + 1]
            let difficulty = min(max(a?.difficulty ?? 1, 1), 3)
            let question = Question(text: r.text, difficulty: difficulty, source: .book, bookRef: r.ref)
            question.figureData = r.figure
            question.pageIndex = r.pageIndex
            question.estimatedSeconds = min(max(a?.estimated_seconds ?? 120, 20), 1200)
            question.answerKeyAnswer = answerKey[Self.refKey(r.ref)]
            let conceptIndex = min(max((a?.concept_number ?? 1) - 1, 0), concepts.count - 1)
            question.concept = concepts[conceptIndex]
            question.chapter = chapter
            context.insert(question)
        }
        try context.save()
    }

    /// "3.2 #14b" and "14b" style refs: match on the trailing exercise label.
    static func refKey(_ ref: String) -> String {
        let lowered = ref.lowercased()
        let label = lowered.split(whereSeparator: { $0 == "#" || $0 == " " }).last.map(String.init) ?? lowered
        return label.filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Solve

    private func solveAll(_ chapter: Chapter, context: ModelContext) async throws {
        let pending = chapter.questions.filter { $0.referenceAnswer.isEmpty && $0.status != .retired }
        guard !pending.isEmpty else { return }
        let total = chapter.questions.count
        var done = total - pending.count
        report(chapter, "Solving questions (\(done)/\(total))…", 0.3, context)

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
            for _ in 0..<4 { launch() }
            while let (id, result) = try await group.next() {
                if let q = byID[id] {
                    switch result {
                    case let .success(s):
                        q.referenceSolution = s.solution
                        q.referenceAnswer = s.finalAnswer
                        q.status = s.trusted ? .ok : .needsParentReview
                        q.reviewNote = s.note
                    case let .failure(error):
                        if case ClaudeClient.ClientError.missingAPIKey = error { throw error }
                        q.status = .needsParentReview
                        q.reviewNote = "Couldn't solve automatically: \(error.localizedDescription)"
                        q.referenceAnswer = "?"
                    }
                }
                done += 1
                report(chapter, "Solving questions (\(done)/\(total))…", 0.3 + 0.7 * Double(done) / Double(total), context)
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
