import UIKit
#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample chapter (launch with `-seedSample`) for trying the UI without scanning or an API key.
@MainActor
enum SampleData {
    private static func putInFolders(_ chapter: Chapter, _ context: ModelContext) {
        let parent = Folder(name: "Student")
        let child = Folder(name: "School algebra")
        context.insert(parent); context.insert(child)
        child.parent = parent
        chapter.folder = child
        try? context.save()
    }

    /// A just-scanned chapter whose pages need fixing: a blurry page, a missing page, and a page scanned twice.
    static func seedRescan(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedRescan"),
              ((try? context.fetch(FetchDescriptor<Chapter>()))?.contains { $0.title == "Ch. 6 · Rescan test" } ?? false) == false
        else { return }
        let chapter = Chapter(title: "Ch. 6 · Rescan test")
        chapter.status = .needsRescan
        context.insert(chapter)
        let specs: [(Int, [ReadDTO.ScanProblem])] = [
            (212, []), (213, [ReadDTO.ScanProblem(kind: "cut_off", detail: "the bottom is cut off (exercises 31–40 are missing)")]),
            (216, []), (216, []), (217, []),
        ]
        for (i, (n, problems)) in specs.enumerated() {
            let img = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                ("Page \(n)\n\n1. Solve 2x + 3 = 7\n2. Factor x² − 9" as NSString)
                    .draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
            }
            let page = PageImage(order: i, imageData: img.jpegData(compressionQuality: 0.8) ?? Data())
            let dto = ReadDTO.Page(image_number: 1, printed_page_number: n, is_answer_key: false, blocks: [], scan_problems: problems)
            page.readJSON = String(data: (try? JSONEncoder().encode(dto)) ?? Data(), encoding: .utf8)
            page.printedPageNumber = n
            page.chapter = chapter
            context.insert(page)
        }
        try? context.save()
    }

    /// Two lessons as the planner would make them (fresh, not started), plus one skipped section.
    private static func seedLessons(_ chapter: Chapter, _ context: ModelContext) {
        let plan = LessonPlanner.Result(lessons: [
            .init(title: "One- and multi-step equations", summary: "Undo operations to get the variable alone.", optional: false,
                  parts: [LessonPart(title: "Undoing one operation", sectionIDs: [0], practiceSectionIDs: []),
                          LessonPart(title: "Several steps", sectionIDs: [1], practiceSectionIDs: [])]),
            .init(title: "Literal equations", summary: "Solve a formula for one of its letters.", optional: false,
                  parts: [LessonPart(title: "Solving formulas", sectionIDs: [2], practiceSectionIDs: [])]),
        ], skipped: [.init(section_id: 2, reason: "example only")], attached: [])
        LessonPlanner.save(plan, to: chapter, context: context)
    }

    static func seedIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSample") else { return }
        seedRescan(context)
        let existing = (try? context.fetch(FetchDescriptor<Chapter>())) ?? []
        if let first = existing.first {
            // Data left by an earlier test run: just make sure the requested folder layout exists.
            if ProcessInfo.processInfo.arguments.contains("-seedInFolder"), first.folder == nil { putInFolders(first, context) }
            if ProcessInfo.processInfo.arguments.contains("-seedLessons") { seedLessons(first, context) }
            return
        }

        let chapter = Chapter(title: "Ch. 2 · Solving Linear Equations")
        chapter.status = .ready
        chapter.formatVersion = Chapter.currentFormat
        context.insert(chapter)

        let specs: [(String, String, [(String, Int, Bool, Bool)])] = [
            ("2-1 One-step equations", "Undo one operation to isolate the variable.", [
                ("Solve $x + 7 = 15$.", 1, true, false),
                ("Solve $\\frac{y}{4} = 3$.", 1, true, false),
                ("Solve $-3m = 21$.", 2, true, false),
            ]),
            ("2-2 Multi-step equations", "Combine like terms, distribute, then isolate the variable.", [
                ("Solve $2(x - 3) + 4 = 10$.", 1, true, false),
                ("Solve $5a - 2 = 3a + 8$.", 2, true, false),
                ("A phone plan costs \\$20 per month plus \\$0.10 per text. Maya's bill was \\$27.50. How many texts did she send?", 3, true, false),
                ("Write a computer program that solves $ax + b = c$ for any inputs.", 2, false, false),
                ("Find all integers $n$ for which $\\frac{3n+7}{n+1}$ is an integer.", 3, true, true),
            ]),
            ("2-3 Literal equations like $A = lw$", "Solve a formula for one of its variables.", [
                ("Solve $A = lw$ for $w$.", 1, true, false),
                ("Solve $P = 2l + 2w$ for $l$.", 2, true, false),
            ]),
        ]
        var nodes: [SectionNode] = []
        var order = 0
        for (i, spec) in specs.enumerated() {
            nodes.append(SectionNode(id: i, title: spec.0, level: 1, parent: -1))
            let concept = Concept(name: String(spec.0.dropFirst(4)), summary: spec.1, bookOrder: i,
                                  workedExample: "**Example:** Solve $3x + 2 = 11$.\n\n$3x = 9$, so $x = 3$.")
            concept.chapter = chapter
            context.insert(concept)
            let intro = ContentBlock(order: order, kind: "text", markdown: spec.1, pageIndex: i, sectionID: i)
            intro.chapter = chapter; context.insert(intro); order += 1
            let example = ContentBlock(order: order, kind: "example", markdown: "Solve $3x + 2 = 11$.\n\n$3x = 9$, so $x = 3$.", pageIndex: i, sectionID: i)
            example.chapter = chapter; context.insert(example); order += 1
            for (j, q) in spec.2.enumerated() {
                let question = Question(text: q.0, difficulty: q.1, source: .book)
                question.printedNumber = "\(j + 1)"
                question.printedPage = 40 + i
                question.pageIndex = i
                question.sectionID = i
                question.pencilOK = q.2
                question.pencilReason = q.2 ? "" : "needs a computer"
                question.isChallenge = q.3
                question.estimatedSeconds = 60 * q.1
                question.concept = concept
                question.chapter = chapter
                context.insert(question)
                let block = ContentBlock(order: order, kind: "exercise", markdown: q.0, pageIndex: i, sectionID: i)
                block.printedNumber = "\(j + 1)"
                block.questionID = question.id
                block.chapter = chapter
                context.insert(block)
                order += 1
            }
        }
        chapter.outline = nodes
        if ProcessInfo.processInfo.arguments.contains("-seedInFolder") { putInFolders(chapter, context) }
        if ProcessInfo.processInfo.arguments.contains("-seedLessons") { seedLessons(chapter, context) }
        if ProcessInfo.processInfo.arguments.contains("-seedGraded"), let q = chapter.questions.first(where: { $0.difficulty == 3 }) {
            let a = Attempt(mode: .practice)
            a.question = q
            a.isGraded = true
            a.verdict = .incorrect
            a.mistakeType = .conceptual
            a.activeSeconds = 140
            a.errorStep = "In the second line, $0.10t$ was added to both sides instead of subtracted."
            a.feedback = "Good setup! Watch the step where you move the texts term — undo addition with subtraction."
            a.workedSolution = (1...14).map { i in
                "**Step \(i).** Rewrite the equation: $20 + 0.10t = 27.50$, so $0.10t = 27.50 - 20 = 7.50$ and $t = \\frac{7.50}{0.10} = 75$."
            }.joined(separator: "\n\n") + "\n\n**Answer:** $t = 75$ texts."
            context.insert(a)
        }
        try? context.save()
        ChapterProcessor.shared.ensureSkills(chapter, context: context)
    }
}
#endif
