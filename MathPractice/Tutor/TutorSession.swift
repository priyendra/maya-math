import Foundation
import SwiftData
import AVFoundation

/// Voice conversation with the tutor about one answer (the solution page).
@MainActor
final class TutorSession: VoiceTutor {
    let attempt: Attempt
    let parts: [PagePart]

    private var context: ModelContext? { attempt.modelContext }

    init(attempt: Attempt) {
        self.attempt = attempt
        self.parts = Self.parts(for: attempt)
        super.init()
    }

    static func parts(for a: Attempt) -> [PagePart] {
        var parts: [PagePart] = []
        if let q = a.question { parts.append(PagePart(id: "question", title: "The question", markdown: q.text)) }
        if !a.hintText.isEmpty { parts.append(PagePart(id: "hint", title: "The hint she used", markdown: a.hintText)) }
        if !a.wasStuck, a.renderedImage != nil { parts.append(PagePart(id: "work", title: "Her handwritten work (picture)", markdown: "")) }
        if a.effectiveVerdict == .incorrect, !a.wasStuck, !a.errorStep.isEmpty || !a.feedback.isEmpty {
            parts.append(PagePart(id: "wrong", title: "Where it went wrong",
                                  markdown: [a.errorStep, a.feedback].filter { !$0.isEmpty }.joined(separator: "\n\n")))
        }
        for (i, step) in TutorScriptParser.steps(a.workedSolution).enumerated() {
            parts.append(PagePart(id: "s\(i + 1)", title: "Solution step \(i + 1)", markdown: step))
        }
        return parts
    }

    override var pageParts: [PagePart] { parts }

    // MARK: Control

    func start() {
        guard state == .off else { return }
        state = .starting
        run = Task {
            guard await prepareAudio() else { return }
            // Ended while the permission prompts were up: don't come back to life.
            guard !Task.isCancelled, state == .starting else { return }
            if !fake {
                let installed = Speaker.englishVoices.prefix(12).map { Speaker.describe($0) }
                CallLog.event("tutor_start", ["voice": Speaker.describe(Speaker.voice), "installed_english_voices": Array(installed)])
            }
            var content: [[String: Any]]
            if history.isEmpty {
                content = openingContext()
                content.append(["type": "text", "text": "She just opened the tutor. Greet her in one short sentence, then start with the most useful thing (usually where her answer went wrong; if she got it right or didn't answer, the key idea of the solution) and ask what she'd like to go over."])
                if let snap = snapshot() { content.append(contentsOf: snapshotBlocks(snap)) }
            } else {
                content = [["type": "text", "text": "She came back to talk again. Pick up briefly where you left off and ask what she'd like to go over."]]
            }
            history.append(["role": "user", "content": content])
            await reply()
        }
    }

    /// Start listening again after she stopped (or gave up waiting).
    func talk() {
        if state == .speaking || state == .thinking { interrupt(); return }
        let tutorSpoke = history.contains { $0["role"] as? String == "assistant" }
        if tutorSpoke { listen() } else { state = .off; start() }   // the opening never arrived: try it again
    }

    override func end() {
        super.end()
        try? context?.save()
    }

    override func recordTurn(fromStudent: Bool, text: String, snapshot: Data?) {
        let turn = TutorTurn(fromStudent: fromStudent, text: text, snapshot: snapshot)
        context?.insert(turn)
        turn.attempt = attempt
        if !fromStudent { try? context?.save() }
    }

    // MARK: Context for Claude

    override func openingContext() -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        func text(_ s: String) { blocks.append(["type": "text", "text": s]) }
        let a = attempt
        if let q = a.question {
            text("The question:\n\(q.text)")
            if let fig = q.figureData { text("Figure for the question:"); blocks.append(ClaudeClient.Block.jpeg(fig).json) }
            if let c = q.concept { text("Skill: \(c.name)") }
            if let key = q.answerKeyAnswer, !key.isEmpty { text("The book's answer key says: \(key)") }
        }
        if a.wasStuck {
            text("She got stuck on this question and asked to see the solution.")
        } else if let img = a.renderedImage {
            text("Her handwritten answer:")
            blocks.append(ClaudeClient.Block.png(img).json)
            var g = "Grading: \(a.effectiveVerdict == .correct ? "correct" : a.effectiveVerdict == .incorrect ? "not correct" : "uncertain")"
            if let m = a.mistakeType, a.effectiveVerdict == .incorrect { g += " (mistake type: \(m.displayName.lowercased()))" }
            if !a.transcribedAnswer.isEmpty { g += "\nHer answer read as: \(a.transcribedAnswer)" }
            text(g)
        }
        let listing = parts.map { p in "[\(p.id)] \(p.title)" + (p.markdown.isEmpty ? "" : ":\n\(p.markdown)") }
        text("The page she sees, with the ids you can POINT at:\n\n" + listing.joined(separator: "\n\n"))
        let book = Self.bookSection(for: a.question)
        if !book.isEmpty { text("From her textbook, the section this question comes from:\n\n" + book) }
        // Everything above is the same on every turn: cache it.
        if var last = blocks.popLast() {
            last["cache_control"] = ["type": "ephemeral"]
            blocks.append(last)
        }
        return blocks
    }

    /// The textbook's explanation and worked examples for the lesson this question belongs to.
    static func bookSection(for q: Question?) -> String {
        guard let q, let chapter = q.chapter, q.sectionID >= 0 else { return "" }
        let nodes = Dictionary(chapter.outline.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let blocks = chapter.sortedBlocks
        let teaching = Set(blocks.filter { ["text", "example"].contains($0.kind) }.map(\.sectionID))
        // The lesson: the nearest section at or above the question that has explanation or worked examples of its
        // own (exercise sections usually don't). Works for any book's outline depth.
        var lesson = q.sectionID
        var probe: Int? = q.sectionID
        while let id = probe {
            if teaching.contains(id) { lesson = id; break }
            probe = nodes[id].flatMap { $0.parent >= 0 ? $0.parent : nil }
        }
        var inLesson: Set<Int> = [lesson]
        var grew = true
        while grew {
            grew = false
            for n in nodes.values where inLesson.contains(n.parent) && !inLesson.contains(n.id) { inLesson.insert(n.id); grew = true }
        }
        let text = blocks
            .filter { inLesson.contains($0.sectionID) && ["heading", "text", "example"].contains($0.kind) }
            .map(\.markdown)
            .joined(separator: "\n\n")
        return String(text.prefix(20000))
    }

    // MARK: Debug

    override func fakeScript(turn: Int) -> String {
        turn == 0 ? """
        SAY: Hi! Let's look at this one together.
        POINT: wrong
        SAY: Here's where it went off track.
        WRITE: $\\sqrt{9a^2} = 3a$
        SAY: The square root of nine a squared is three a, because three a times three a is nine a squared.
        SAY: What would you like to go over?
        """ : """
        SAY: Good question.
        POINT: s1
        SAY: Look at this step first.
        WRITE: $4x^2 - 25 = (2x - 5)(2x + 5)$
        SAY: Here's another one like it. Try factoring sixteen y squared minus one on your page.
        """
    }
}
