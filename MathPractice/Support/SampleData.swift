#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample chapter (launch with `-seedSample`) for trying the UI without scanning or an API key.
@MainActor
enum SampleData {
    static func seedIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSample") else { return }
        let existing = (try? context.fetch(FetchDescriptor<Chapter>())) ?? []
        guard existing.isEmpty else { return }

        let chapter = Chapter(title: "Ch. 2 · Solving Linear Equations")
        chapter.status = .ready
        chapter.formatVersion = 2
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
            ("2-3 Literal equations", "Solve a formula for one of its variables.", [
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
        try? context.save()
        ChapterProcessor.shared.ensureSkills(chapter, context: context)
    }
}
#endif
