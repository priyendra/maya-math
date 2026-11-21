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
        context.insert(chapter)

        let specs: [(String, String, [(String, Int, String, String)])] = [
            ("One-step equations", "Undo one operation to isolate the variable.", [
                ("Solve $x + 7 = 15$.", 1, "$x = 8$", "Subtract 7 from both sides: $x = 15 - 7 = 8$."),
                ("Solve $\\frac{y}{4} = 3$.", 1, "$y = 12$", "Multiply both sides by 4."),
                ("Solve $-3m = 21$.", 2, "$m = -7$", "Divide both sides by $-3$."),
            ]),
            ("Multi-step equations", "Combine like terms, distribute, then isolate the variable.", [
                ("Solve $2(x - 3) + 4 = 10$.", 1, "$x = 6$", "$2x - 6 + 4 = 10 \\Rightarrow 2x = 12 \\Rightarrow x = 6$."),
                ("Solve $5a - 2 = 3a + 8$.", 2, "$a = 5$", "$2a = 10$, so $a = 5$."),
                ("A phone plan costs \\$20 per month plus \\$0.10 per text. Maya's bill was \\$27.50. How many texts did she send?", 3, "75 texts", "$20 + 0.10t = 27.50 \\Rightarrow t = 75$."),
            ]),
            ("Literal equations", "Solve a formula for one of its variables.", [
                ("Solve $A = lw$ for $w$.", 1, "$w = \\frac{A}{l}$", "Divide both sides by $l$."),
                ("Solve $P = 2l + 2w$ for $l$.", 2, "$l = \\frac{P - 2w}{2}$", "Subtract $2w$, then divide by 2."),
            ]),
        ]
        for (i, spec) in specs.enumerated() {
            let concept = Concept(name: spec.0, summary: spec.1, bookOrder: i,
                                  workedExample: "**Example:** Solve $3x + 2 = 11$.\n\n$3x = 9$, so $x = 3$.")
            concept.chapter = chapter
            context.insert(concept)
            for (j, q) in spec.2.enumerated() {
                let question = Question(text: q.0, difficulty: q.1, source: .book, bookRef: "2.\(i + 1) #\(j + 1)")
                question.referenceAnswer = q.2
                question.referenceSolution = q.3
                question.estimatedSeconds = 60 * q.1
                question.concept = concept
                question.chapter = chapter
                context.insert(question)
            }
        }
        try? context.save()
        ChapterProcessor.shared.ensureSkills(chapter, context: context)
    }
}
#endif
