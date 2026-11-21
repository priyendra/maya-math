import Foundation
import SwiftData
import UIKit

/// Turns a chapter's scanned pages into a digital chapter: section tree, content blocks, and tagged questions.
///
/// 1. Read pages in small batches (each page's result saved immediately, so an interruption resumes).
/// 2. Check printed page numbers for gaps/repeats.
/// 3. Outline: canonical section tree + concepts (one call over the whole chapter).
/// 4. Assign: concept, difficulty, time, answer-key link (batched by section, in parallel).
/// No solving — the grader solves each question when grading.
@MainActor
final class ChapterProcessor: ObservableObject {
    static let shared = ChapterProcessor()
    static let pagesPerBatch = 3
    static let readConcurrency = 4
    static let assignBatchSize = 40
    static let assignConcurrency = 4

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
        // Chapters organized by an older version: re-organize from the stored transcriptions (quick, no re-reading).
        for chapter in chapters where chapter.status == .ready && chapter.formatVersion >= 2
            && chapter.formatVersion < Chapter.currentFormat && !isRunning(chapter) {
            reorganize(chapter, context: context)
        }
    }

    /// Re-reads a chapter from its stored page images with the current pipeline (no rescanning).
    /// Practice history for the chapter is discarded, since its questions are rebuilt.
    func reread(_ chapter: Chapter, context: ModelContext) {
        guard !isRunning(chapter) else { return }
        for q in chapter.questions { context.delete(q) }
        for c in chapter.concepts { context.delete(c) }
        for s in chapter.skills { context.delete(s) }
        for e in chapter.exams { context.delete(e) }
        for b in chapter.blocks { context.delete(b) }
        for p in chapter.pages { p.readJSON = nil; p.printedPageNumber = nil }
        chapter.outlineJSON = ""
        chapter.pageWarning = nil
        chapter.formatVersion = 1
        chapter.status = .processing
        chapter.progressFraction = 0
        try? context.save()
        start(chapter, context: context)
    }

    /// Rebuilds outline, questions and tags from the stored page transcriptions (no page reading).
    func reorganize(_ chapter: Chapter, context: ModelContext) {
        guard !isRunning(chapter), chapter.pages.allSatisfy({ $0.readJSON != nil }) else { return }
        for s in chapter.skills { context.delete(s) }
        for e in chapter.exams { context.delete(e) }
        chapter.formatVersion = 2
        chapter.status = .processing
        try? context.save()
        start(chapter, context: context)
    }

    private func report(_ chapter: Chapter, _ message: String, _ fraction: Double, _ context: ModelContext) {
        chapter.progressMessage = message
        chapter.progressFraction = fraction
        try? context.save()
    }

    func process(_ chapter: Chapter, context: ModelContext) async throws {
        chapter.status = .processing
        chapter.errorMessage = nil
        try await readPages(chapter, context: context)
        chapter.pageWarning = Self.checkPageNumbers(chapter.sortedPages)
        if chapter.formatVersion < Chapter.currentFormat || chapter.questions.isEmpty {
            try await organize(chapter, context: context)
        }
        ensureSkills(chapter, context: context)
        chapter.formatVersion = Chapter.currentFormat
        chapter.status = .ready
        report(chapter, "Ready", 1, context)
    }

    // MARK: 1. Read pages (resumable)

    private func readPages(_ chapter: Chapter, context: ModelContext) async throws {
        let pages = chapter.sortedPages
        guard !pages.isEmpty else { throw ClaudeClient.ClientError.decoding("This chapter has no pages.") }
        let pending = pages.indices.filter { pages[$0].readJSON == nil }
        guard !pending.isEmpty else { return }

        var batches: [[Int]] = []
        for i in pending {
            if let last = batches.last?.last, last == i - 1, batches[batches.count - 1].count < Self.pagesPerBatch {
                batches[batches.count - 1].append(i)
            } else {
                batches.append([i])
            }
        }
        struct Job: Sendable { let indices: [Int]; let images: [Data]; let hints: [Bool]; let context: Data? }
        let jobs = batches.map { idx in
            Job(indices: idx,
                images: idx.map { ImageUtils.jpegForAPI(pages[$0].imageData) ?? pages[$0].imageData },
                hints: idx.map { pages[$0].isAnswerKey },
                context: idx.first.flatMap { $0 > 0 ? ImageUtils.jpegForAPI(pages[$0 - 1].imageData, maxEdge: 1000) : nil })
        }

        var finished = pages.count - pending.count
        report(chapter, "Reading pages (\(finished)/\(pages.count))…", 0.02, context)
        let services = self.services
        let encoder = JSONEncoder()

        try await withThrowingTaskGroup(of: (Job, ReadDTO).self) { group in
            var iterator = jobs.makeIterator()
            func launch() {
                guard let job = iterator.next() else { return }
                group.addTask { (job, try await services.read(pages: job.images, answerKeyHints: job.hints, contextPage: job.context)) }
            }
            for _ in 0..<Self.readConcurrency { launch() }
            while let (job, dto) = try await group.next() {
                for (i, pageIndex) in job.indices.enumerated() {
                    let page = dto.pages.first { $0.image_number == i + 1 }
                        ?? ReadDTO.Page(image_number: i + 1, printed_page_number: 0, is_answer_key: job.hints[i], blocks: [])
                    pages[pageIndex].readJSON = (try? encoder.encode(page)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    if page.is_answer_key { pages[pageIndex].isAnswerKey = true }
                }
                finished += job.indices.count
                report(chapter, "Reading pages (\(finished)/\(pages.count))…", 0.7 * Double(finished) / Double(pages.count), context)
                launch()
            }
        }
    }

    static func decodePage(_ page: PageImage) -> ReadDTO.Page? {
        guard let json = page.readJSON else { return nil }
        return try? JSONDecoder().decode(ReadDTO.Page.self, from: Data(json.utf8))
    }

    // MARK: 2. Page numbers

    /// Fills in missing printed page numbers from neighbours and describes gaps/repeats (nil if none).
    static func checkPageNumbers(_ pages: [PageImage]) -> String? {
        let content = pages.filter { !$0.isAnswerKey }
        let read: [Int?] = content.map { p in decodePage(p).map(\.printed_page_number).flatMap { $0 > 0 ? $0 : nil } }
        let filled = inferPageNumbers(read)
        for (p, n) in zip(content, filled) { p.printedPageNumber = n }
        return pageProblems(filled)
    }

    static func inferPageNumbers(_ read: [Int?]) -> [Int?] {
        var out = read
        let known = read.indices.filter { read[$0] != nil }
        guard !known.isEmpty else { return out }
        for i in read.indices where read[i] == nil {
            let prev = known.last { $0 < i }, next = known.first { $0 > i }
            if let p = prev, let n = next, read[n]! - read[p]! == n - p { out[i] = read[p]! + (i - p) }
            else if let p = prev, next == nil { out[i] = read[p]! + (i - p) }
            else if let n = next, prev == nil { out[i] = read[n]! - (n - i) }
        }
        return out
    }

    static func pageProblems(_ numbers: [Int?]) -> String? {
        var problems: [String] = []
        var prev: Int?
        for n in numbers {
            guard let n else { continue }
            if let p = prev {
                if n == p { problems.append("page \(n) was scanned twice") }
                else if n == p + 2 { problems.append("page \(p + 1) seems to be missing") }
                else if n > p + 2 { problems.append("pages \(p + 1)–\(n - 1) seem to be missing") }
                else if n < p { problems.append("page \(n) comes after page \(p)") }
            }
            prev = n
        }
        guard !problems.isEmpty else { return nil }
        let s = problems.joined(separator: "; ")
        return s.prefix(1).uppercased() + s.dropFirst() + "."
    }

    // MARK: 3–4. Organize

    private struct Run {
        let path: [String]
        let pageLabel: String
        var samples: [String]
    }

    private struct RawBlock {
        let block: ReadDTO.Block
        let pageIndex: Int
        let pathIndex: Int
    }

    private func organize(_ chapter: Chapter, context: ModelContext) async throws {
        // Clear anything from a previous partial organize.
        for q in chapter.questions { context.delete(q) }
        for c in chapter.concepts { context.delete(c) }
        for b in chapter.blocks { context.delete(b) }

        let pages = chapter.sortedPages
        // Runs: consecutive blocks (in reading order) with the same section path. Mapping runs rather than distinct
        // paths lets the outline place a continuation page's partial path (lesson heading printed on an earlier
        // page) under the section actually in progress.
        var runs: [Run] = []
        var raw: [RawBlock] = []
        for (pi, page) in pages.enumerated() {
            guard let dto = Self.decodePage(page) else { continue }
            let pageLabel = page.printedPageNumber.map { "p\($0)" } ?? "scan \(pi + 1)"
            for b in dto.blocks {
                if runs.last?.path != b.section_path || runs.last?.pageLabel != pageLabel {
                    runs.append(Run(path: b.section_path, pageLabel: pageLabel, samples: []))
                }
                if b.kind != "answer", runs[runs.count - 1].samples.count < 2 {
                    let text = (b.printed_number.isEmpty ? "" : "#\(b.printed_number) ") + b.markdown
                    runs[runs.count - 1].samples.append(b.kind + ": " + text)
                }
                raw.append(RawBlock(block: b, pageIndex: pi, pathIndex: runs.count - 1))
            }
        }
        guard raw.contains(where: { $0.block.kind == "exercise" }) else {
            throw ClaudeClient.ClientError.decoding("No exercises were found on these pages. Check that the scans are clear.")
        }

        report(chapter, "Building the chapter outline…", 0.75, context)
        let outline = try await services.outline(runs: runs.map { ($0.path, $0.pageLabel, $0.samples) })

        // Section tree.
        var nodes: [SectionNode] = []
        var stack: [SectionNode] = []
        for (i, s) in outline.sections.enumerated() {
            let level = max(1, s.level)
            while let top = stack.last, top.level >= level { stack.removeLast() }
            let node = SectionNode(id: i, title: s.title, level: level, parent: stack.last?.id ?? -1)
            nodes.append(node)
            stack.append(node)
        }
        chapter.outline = nodes
        let sectionOfPath = Dictionary(outline.path_map.map { ($0.run_number - 1, $0.section_number - 1) }, uniquingKeysWith: { a, _ in a })
        func section(_ r: RawBlock) -> Int {
            let s = sectionOfPath[r.pathIndex] ?? -1
            return nodes.indices.contains(s) ? s : -1
        }
        if chapter.title == "New chapter", !outline.chapter_title.isEmpty { chapter.title = outline.chapter_title }

        var concepts: [Concept] = []
        for (i, c) in outline.concepts.enumerated() {
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

        // Content blocks + questions.
        var questions: [(Question, RawBlock)] = []
        var answers: [(text: String, section: Int)] = []
        for (order, r) in raw.enumerated() {
            let b = r.block, page = pages[r.pageIndex], sec = section(r)
            if b.kind == "answer" {
                let label = b.printed_number.isEmpty ? "" : "#\(b.printed_number): "
                answers.append(("[\(b.section_path.joined(separator: " › "))] \(label)\(b.markdown)", sec))
                continue
            }
            if page.isAnswerKey { continue }
            let block = ContentBlock(order: order, kind: b.kind, markdown: b.markdown, pageIndex: r.pageIndex, sectionID: sec)
            block.printedNumber = b.printed_number
            if b.has_figure, !b.figure_box.isEmpty {
                block.imageData = ImageUtils.crop(page.imageData, x: b.figure_box.x, y: b.figure_box.y,
                                                  width: b.figure_box.width, height: b.figure_box.height)
            }
            block.chapter = chapter
            context.insert(block)
            guard b.kind == "exercise" else { continue }
            let text = b.question_markdown.isEmpty ? b.markdown : b.question_markdown
            let q = Question(text: text, difficulty: 1, source: .book)
            q.printedNumber = b.printed_number
            q.printedPage = page.printedPageNumber
            q.pageIndex = page.order
            q.sectionID = sec
            q.pencilOK = b.pencil_ok
            q.pencilReason = b.pencil_reason
            q.isChallenge = b.is_challenge
            q.figureData = block.imageData
            q.concept = concepts[0]
            q.chapter = chapter
            context.insert(q)
            block.questionID = q.id
            questions.append((q, r))
        }

        // Assign concept / difficulty / time / answer key, batched by section.
        let conceptNames = concepts.map { "\($0.name) — \($0.summary)" }
        func related(_ a: Int, _ b: Int) -> Bool {
            guard a >= 0, b >= 0 else { return false }
            func ancestors(_ x: Int) -> Set<Int> {
                var out: Set<Int> = [x]; var cur = x
                while nodes.indices.contains(cur), nodes[cur].parent >= 0 { cur = nodes[cur].parent; out.insert(cur) }
                return out
            }
            return ancestors(a).contains(b) || ancestors(b).contains(a)
        }
        var batches: [[Int]] = []
        let bySection = Dictionary(grouping: questions.indices, by: { questions[$0].0.sectionID })
        for key in bySection.keys.sorted() {
            let idx = bySection[key]!
            stride(from: 0, to: idx.count, by: Self.assignBatchSize).forEach { batches.append(Array(idx[$0..<min($0 + Self.assignBatchSize, idx.count)])) }
        }
        struct AssignJob: Sendable { let indices: [Int]; let inputs: [AssignInput]; let answers: [String] }
        let jobs: [AssignJob] = batches.map { idx in
            let sec = questions[idx[0]].0.sectionID
            let title = nodes.indices.contains(sec) ? Self.sectionTitle(sec, nodes) : "Unknown section"
            let ans = answers.filter { related($0.section, sec) }.map(\.text)
            return AssignJob(indices: idx,
                             inputs: idx.map { AssignInput(text: questions[$0].0.text, printedNumber: questions[$0].0.printedNumber, section: title) },
                             answers: Array(ans.prefix(150)))
        }
        var done = 0
        report(chapter, "Organizing \(questions.count) questions…", 0.8, context)
        let services = self.services
        try await withThrowingTaskGroup(of: (AssignJob, AssignDTO).self) { group in
            var iterator = jobs.makeIterator()
            func launch() {
                guard let job = iterator.next() else { return }
                group.addTask { (job, try await services.assign(questions: job.inputs, concepts: conceptNames, answers: job.answers)) }
            }
            for _ in 0..<Self.assignConcurrency { launch() }
            while let (job, dto) = try await group.next() {
                for item in dto.items {
                    guard job.indices.indices.contains(item.question_number - 1) else { continue }
                    let q = questions[job.indices[item.question_number - 1]].0
                    q.concept = concepts[min(max(item.concept_number - 1, 0), concepts.count - 1)]
                    q.difficulty = min(max(item.difficulty, 1), 3)
                    q.estimatedSeconds = min(max(item.estimated_seconds, 15), 1200)
                    if job.answers.indices.contains(item.answer_number - 1) {
                        let entry = job.answers[item.answer_number - 1]
                        q.answerKeyAnswer = entry.components(separatedBy: "] ").dropFirst().joined(separator: "] ")
                    }
                }
                done += job.indices.count
                report(chapter, "Organizing questions (\(done)/\(questions.count))…", 0.8 + 0.2 * Double(done) / Double(max(questions.count, 1)), context)
                launch()
            }
        }
        try context.save()
    }

    static func sectionTitle(_ id: Int, _ nodes: [SectionNode]) -> String {
        var parts: [String] = []
        var cur = id
        while nodes.indices.contains(cur) { parts.insert(nodes[cur].title, at: 0); cur = nodes[cur].parent }
        return parts.joined(separator: " › ")
    }

    func ensureSkills(_ chapter: Chapter, context: ModelContext) {
        for concept in chapter.concepts {
            let levels = Set(concept.questions.filter { !$0.isChallenge }.map(\.difficulty))
            for d in levels where chapter.skill(concept: concept, difficulty: d) == nil {
                let skill = SkillState(concept: concept, difficulty: d)
                skill.chapter = chapter
                context.insert(skill)
            }
        }
        try? context.save()
    }
}
