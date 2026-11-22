import Foundation
import SwiftData

/// Claude's script for one part of a lesson.
struct LessonScriptDTO: Codable {
    struct Item: Codable {
        let id: String
        let kind: String
        let markdown: String
        let figure: String
    }
    let items: [Item]
    let narration: String
    let your_turn: [String]

    static let schema = Schema.object([
        "items": Schema.array(Schema.object([
            "id": Schema.string,
            "kind": Schema.enumeration(["heading", "text", "example", "figure"]),
            "markdown": Schema.string,
            "figure": Schema.string,
        ])),
        "narration": Schema.string,
        "your_turn": Schema.array(Schema.string),
    ])
}

/// Writes (and saves) the script for a part of a lesson the first time she reaches it.
@MainActor
enum LessonWriter {
    /// What one part draws on, gathered from the chapter (labels f1…, q1… as Claude sees them).
    struct Input {
        var text: [String] = []
        var content: [ClaudeClient.Block] = []
        var figures: [String: UUID] = [:]
        var questions: [String: UUID] = [:]
    }

    static func input(_ lesson: Lesson, part index: Int) -> Input {
        var input = Input()
        guard let chapter = lesson.chapter, lesson.parts.indices.contains(index) else { return input }
        let part = lesson.parts[index]
        var head = "Lesson: \(lesson.title)\nParts of this lesson:\n"
        for (i, p) in lesson.parts.enumerated() {
            head += "\(i + 1). \(p.title)\(i == index ? "   ← you are preparing this part" : "")\n"
        }
        input.content.append(.text(head))

        let teach = Set(part.sectionIDs)
        var book = "Book content for this part:\n"
        var nf = 0
        let blocks = chapter.sortedBlocks
        for b in blocks where teach.contains(b.sectionID) && ["heading", "text", "example", "figure"].contains(b.kind) {
            if let img = b.imageData {
                nf += 1
                let label = "f\(nf)"
                input.figures[label] = b.id
                book += "\n[\(b.kind)]\n\(b.markdown)\n(picture \(label) below)\n"
                input.content.append(.text(book))
                input.content.append(.text("Picture \(label):"))
                input.content.append(.jpeg(img))
                book = ""
            } else {
                book += "\n[\(b.kind)]\n\(b.markdown)\n"
            }
        }
        if !book.isEmpty { input.content.append(.text(book)) }

        // Exercises: this part's own practice sections first, then its teaching sections.
        let questions = Dictionary(uniqueKeysWithValues: chapter.questions.map { ($0.id, $0) })
        var list = "Exercises from the book for this part:\n"
        var nq = 0
        for sections in [Set(part.practiceSectionIDs), teach] {
            for b in blocks where b.kind == "exercise" && sections.contains(b.sectionID) {
                guard nq < 15, let qid = b.questionID, let q = questions[qid], q.isAvailable,
                      !input.questions.values.contains(qid) else { continue }
                nq += 1
                input.questions["q\(nq)"] = qid
                list += "\n[q\(nq)] \(b.printedNumber.isEmpty ? "" : "#\(b.printedNumber) ")\(q.text)\n"
            }
        }
        input.content.append(.text(nq == 0 ? "There are no exercises for this part (your_turn must be empty)." : list))
        return input
    }

    /// The saved script for a part, writing it if needed.
    static func script(_ lesson: Lesson, part index: Int, context: ModelContext) async throws -> LessonPartScript {
        if let s = lesson.scripts[index] { return s }
        let input = input(lesson, part: index)
        let dto: LessonScriptDTO
        if ProcessInfo.processInfo.arguments.contains("-fakeTutor") {
            try await Task.sleep(nanoseconds: 300_000_000)
            dto = fake(index, questions: input.questions.keys.sorted())
        } else {
            dto = try await ClaudeServices.live.client.structured(
                LessonScriptDTO.self, system: Prompts.lessonScript, content: input.content,
                schema: LessonScriptDTO.schema, effort: .high, maxTokens: 16000, kind: "lesson_script")
        }
        let script = convert(dto, part: index, input: input)
        var all = lesson.scripts
        all[index] = script
        lesson.scripts = all
        try? context.save()
        return script
    }

    /// Item ids become unique in the lesson ("e3" in part 2 → "p2e3"), labels become ids.
    static func convert(_ dto: LessonScriptDTO, part index: Int, input: Input) -> LessonPartScript {
        let prefix = "p\(index + 1)"
        var known = Set<String>()
        var items: [LessonPartScript.Item] = []
        for it in dto.items {
            let local = it.id.lowercased().trimmingCharacters(in: .whitespaces)
            known.insert(local)
            let figure = input.figures[it.figure.lowercased().trimmingCharacters(in: .whitespaces)]
            if it.kind == "figure" && figure == nil { continue }   // a picture we don't have
            items.append(.init(id: prefix + local, kind: it.kind, markdown: it.markdown, blockID: figure))
        }
        let narration = dto.narration.components(separatedBy: "\n").map { line -> String in
            guard let b = TutorScriptParser.beat(line), case let .point(id?) = b, known.contains(id) else { return line }
            return "POINT: \(prefix)\(id)"
        }.joined(separator: "\n")
        let ids = dto.your_turn.compactMap { input.questions[$0.lowercased().trimmingCharacters(in: .whitespaces)] }
        return LessonPartScript(items: items, narration: narration, questionIDs: ids)
    }

    private static func fake(_ index: Int, questions: [String]) -> LessonScriptDTO {
        LessonScriptDTO(items: [
            .init(id: "e1", kind: "text", markdown: "To factor a difference of two squares, use $a^2 - b^2 = (a + b)(a - b)$.", figure: ""),
            .init(id: "e2", kind: "example", markdown: "Factor $x^2 - 25$.", figure: ""),
            .init(id: "e3", kind: "example", markdown: "$x^2 - 25 = x^2 - 5^2 = (x + 5)(x - 5)$", figure: ""),
        ], narration: """
        SAY: Here is the idea for part \(index + 1).
        POINT: e1
        SAY: A difference of two squares always factors the same way.
        POINT: e3
        SAY: Twenty five is five squared, so we get [x] plus five times [x] minus five.
        SAY: Any questions before you try one?
        """, your_turn: Array(questions.prefix(2)))
    }
}
