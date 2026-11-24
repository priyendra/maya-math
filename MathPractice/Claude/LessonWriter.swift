import Foundation
import SwiftData

/// Claude's script for one part of a lesson. The book itself is shown above the board, so the script only talks,
/// points at the book's blocks (k1, k2…), writes on the board and asks fill-in-the-blank questions.
struct LessonScriptDTO: Codable {
    let narration: String
    let your_turn: [String]

    static let schema = Schema.object([
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
        /// Book blocks shown to her, in order: k1 = blocks[0]…
        var blocks: [UUID] = []
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
        if let f = part.fromExample, let t = part.toExample {
            head += "\nThis part teaches worked example\(f == t ? " \(f)" : "s \(f)–\(t)") of its section and the explanation " +
                "leading up to \(f == t ? "it" : "them"); the rest of the section is taught in the other parts. " +
                "Choose your_turn exercises that practise what these examples teach.\n"
        }
        input.content.append(.text(head))

        let teach = Set(part.sectionIDs)
        var book = "Book content for this part (as she sees it in the book, block ids k1, k2…):\n"
        let blocks = slice(chapter.sortedBlocks.filter { teach.contains($0.sectionID) }, part: part)
        for b in blocks where ["heading", "text", "example", "figure"].contains(b.kind) {
            input.blocks.append(b.id)
            let label = "k\(input.blocks.count)"
            if let img = b.imageData {
                book += "\n[\(label)] (\(b.kind))\n\(b.markdown)\n(picture below)\n"
                input.content.append(.text(book))
                input.content.append(.jpeg(img))
                book = ""
            } else {
                book += "\n[\(label)] (\(b.kind))\n\(b.markdown)\n"
            }
        }
        if !book.isEmpty { input.content.append(.text(book)) }

        // Exercises: this part's own practice sections first, then its teaching sections.
        let questions = Dictionary(uniqueKeysWithValues: chapter.questions.map { ($0.id, $0) })
        var list = "Exercises from the book for this part:\n"
        var nq = 0
        for b in exerciseBlocks(chapter.sortedBlocks, part: part, taught: blocks) {
            guard nq < 15, let qid = b.questionID, let q = questions[qid], q.isAvailable,
                  !input.questions.values.contains(qid) else { continue }
            nq += 1
            input.questions["q\(nq)"] = qid
            list += "\n[q\(nq)] \(b.printedNumber.isEmpty ? "" : "#\(b.printedNumber) ")\(q.text)\n"
        }
        input.content.append(.text(nq == 0 ? "There are no exercises for this part (your_turn must be empty)." : list))
        return input
    }

    /// The exercises a part can use for "your turn": its practice sections' first (from the whole chapter: books
    /// usually keep exercises in their own sections), then any among the blocks it teaches.
    static func exerciseBlocks(_ all: [ContentBlock], part: LessonPart, taught: [ContentBlock]) -> [ContentBlock] {
        let practice = Set(part.practiceSectionIDs)
        let fromPractice = all.filter { $0.kind == "exercise" && practice.contains($0.sectionID) }
        let seen = Set(fromPractice.map(\.id))
        return fromPractice + taught.filter { $0.kind == "exercise" && !seen.contains($0.id) }
    }

    /// The blocks a part teaches: for a part that covers examples f…t of a section, the explanation and figures
    /// before each of those examples go with it; anything after the section's last example goes with the last part.
    static func slice(_ blocks: [ContentBlock], part: LessonPart) -> [ContentBlock] {
        guard let f = part.fromExample, let t = part.toExample, let split = part.sectionIDs.first else { return blocks }
        let total = blocks.filter { $0.sectionID == split && $0.kind == "example" }.count
        var seen = 0
        var out: [ContentBlock] = []
        for b in blocks {
            if b.sectionID != split {
                out.append(b)   // another section attached to this part: taught whole
            } else if b.kind == "example" {
                seen += 1
                if seen >= f && seen <= t { out.append(b) }
            } else {
                let upcoming = seen + 1
                if (upcoming >= f && upcoming <= t) || (seen >= total && t >= total) { out.append(b) }
            }
        }
        return out
    }

    /// The saved script for a part, writing it if needed.
    static func script(_ lesson: Lesson, part index: Int, context: ModelContext) async throws -> LessonPartScript {
        // A saved script with nothing to say (an earlier bad reply), or an older one that drew its own copy of the
        // book, is written again.
        if let s = lesson.scripts[index], s.bookBlocks != nil, isUsable(s) { return s }
        let input = input(lesson, part: index)
        var script: LessonPartScript?
        if ProcessInfo.processInfo.arguments.contains("-fakeTutor") {
            try await Task.sleep(nanoseconds: 300_000_000)
            script = convert(fake(index, blocks: input.blocks.count, questions: input.questions.keys.sorted()), part: index, input: input)
        } else {
            // Claude occasionally returns the page but an empty narration: ask again (twice at most).
            for attempt in 0..<2 where script == nil {
                let dto = try await ClaudeServices.live.client.structured(
                    LessonScriptDTO.self, system: Prompts.lessonScript, content: input.content,
                    schema: LessonScriptDTO.schema, effort: .high, maxTokens: 16000, kind: "lesson_script")
                let s = convert(dto, part: index, input: input)
                if isUsable(s) { script = s } else { CallLog.event("lesson_script_unusable", ["attempt": attempt, "part": index]) }
            }
        }
        guard let script else { throw ScriptError.empty }
        var all = lesson.scripts
        all[index] = script
        lesson.scripts = all
        try? context.save()
        return script
    }

    /// A part needs something said about it.
    static func isUsable(_ s: LessonPartScript) -> Bool {
        let says = s.narration.components(separatedBy: "\n").filter { line in
            if case .say? = TutorScriptParser.beat(line) { return true } else { return false }
        }
        return says.count >= 3
    }

    enum ScriptError: LocalizedError {
        case empty
        var errorDescription: String? { "The tutor couldn't prepare this part. Try again." }
    }

    /// Book labels (k3) become "book:<block id>"; exercise labels become question ids.
    static func convert(_ dto: LessonScriptDTO, part index: Int, input: Input) -> LessonPartScript {
        let narration = dto.narration.components(separatedBy: "\n").map { line -> String in
            guard let b = TutorScriptParser.beat(line), case let .point(id?) = b else { return line }
            guard let block = bookBlock(id, input.blocks) else { return "POINT: none" }
            return "POINT: book:\(block.uuidString)"
        }.joined(separator: "\n")
        let ids = dto.your_turn.compactMap { input.questions[$0.lowercased().trimmingCharacters(in: .whitespaces)] }
        return LessonPartScript(items: [], narration: narration, questionIDs: ids, bookBlocks: input.blocks)
    }

    /// "k3" → the third book block.
    static func bookBlock(_ label: String, _ blocks: [UUID]) -> UUID? {
        guard label.hasPrefix("k"), let n = Int(label.dropFirst()), blocks.indices.contains(n - 1) else { return nil }
        return blocks[n - 1]
    }

    private static func fake(_ index: Int, blocks: Int, questions: [String]) -> LessonScriptDTO {
        LessonScriptDTO(narration: """
        SAY: Here is the idea for part \(index + 1).
        POINT: k1
        SAY: Read along with me in the book.
        POINT: k\(min(2, max(blocks, 1)))
        WRITE: $3x + 2 = 11$
        SAY: First we take away two from both sides. What is eleven minus two?
        BLANK: $3x =$ ___ || 9 || Eleven minus two is nine.
        SAY: Then we divide by three, so [x] is three.
        SAY: Any questions before you try one?
        """, your_turn: Array(questions.prefix(2)))
    }
}
