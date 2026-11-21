import Foundation
import SwiftData
import AVFoundation

/// A part of the solution page the tutor can point at.
struct PagePart: Identifiable, Equatable {
    let id: String          // "question", "work", "wrong", "s1"…, "b1"…
    let title: String       // for Claude: what this part is
    let markdown: String    // its text ("" for her handwriting)
}

/// What the student sees right now: a picture of the visible part of the page with her ink, and which parts it shows.
struct PageSnapshot {
    let jpeg: Data
    let visibleParts: [String]
    let newMarks: Bool
}

/// Voice conversation with the tutor about one answer. Hands-free: the tutor speaks, then listens; a short silence
/// ends her turn; tapping the page stops the tutor.
@MainActor
final class TutorSession: ObservableObject {
    enum State: Equatable {
        case off, starting, thinking, speaking, listening, waiting(String)
    }

    @Published private(set) var state: State = .off
    /// What she is saying, live.
    @Published private(set) var heard = ""
    /// Lines the tutor wrote on the board (ids b1, b2…).
    @Published private(set) var board: [PagePart] = []
    /// The page part the cursor is on.
    @Published private(set) var pointer: String?
    /// The tutor's current sentence (caption).
    @Published private(set) var caption = ""

    let attempt: Attempt
    let parts: [PagePart]
    /// Set by the page: captures what she's looking at.
    var snapshot: () -> PageSnapshot? = { nil }

    private var context: ModelContext? { attempt.modelContext }
    private let speaker = Speaker()
    private let listener = Listener()
    private var history: [[String: Any]] = []
    private var run: Task<Void, Never>?
    private var timedOut = false
    private enum TutorError: Error { case tooSlow }
    private let fake: Bool

    var isOn: Bool { state != .off }

    init(attempt: Attempt) {
        self.attempt = attempt
        self.parts = Self.parts(for: attempt)
        #if DEBUG
        fake = ProcessInfo.processInfo.arguments.contains("-fakeTutor")
        #else
        fake = false
        #endif
        speaker.silent = fake
        listener.onHeard = { [weak self] in self?.heard = $0 }
        listener.onFinished = { [weak self] in self?.studentSaid($0) }
        listener.onGaveUp = { [weak self] in self?.state = .waiting("Tap Talk when you want to say something.") }
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

    // MARK: Control

    func start() {
        guard state == .off else { return }
        state = .starting
        run = Task {
            if !fake {
                let ok = await Listener.requestPermissions()
                // Ended while the permission prompts were up: don't come back to life.
                guard !Task.isCancelled, state == .starting else { return }
                guard ok else {
                    state = .waiting("To talk with the tutor, allow the microphone and speech recognition in Settings → Maya Math.")
                    return
                }
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                try? session.setActive(true)
                let installed = Speaker.englishVoices.prefix(12).map { Speaker.describe($0) }
                CallLog.event("tutor_start", ["voice": Speaker.describe(Speaker.voice), "installed_english_voices": Array(installed)])
            }
            if history.isEmpty {
                var content = openingContext()
                content.append(["type": "text", "text": "She just opened the tutor. Greet her in one short sentence, then start with the most useful thing (usually where her answer went wrong; if she got it right or didn't answer, the key idea of the solution) and ask what she'd like to go over."])
                if let snap = snapshot() { content.append(contentsOf: snapshotBlocks(snap)) }
                history.append(["role": "user", "content": content])
            } else {
                history.append(["role": "user", "content": [["type": "text", "text": "She came back to talk again. Pick up briefly where you left off and ask what she'd like to go over."]]])
            }
            await reply()
        }
    }

    /// She tapped the page or the stop button: stop talking and listen.
    func interrupt() {
        guard state == .speaking || state == .thinking else { return }
        run?.cancel()
        speaker.stop()
        listen()
    }

    /// Start listening again after she stopped (or gave up waiting).
    func talk() {
        if state == .speaking || state == .thinking { interrupt(); return }
        let tutorSpoke = history.contains { $0["role"] as? String == "assistant" }
        if tutorSpoke { listen() } else { state = .off; start() }   // the opening never arrived: try it again
    }

    func end() {
        run?.cancel()
        run = nil
        speaker.stop()
        listener.stop()
        pointer = nil
        caption = ""
        heard = ""
        state = .off
        if !fake { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        try? context?.save()
    }

    /// Her pencil moved: she may be marking something while she talks.
    func inkChanged() { listener.noteActivity() }

    #if DEBUG
    /// UI tests can't speak: stands in for a finished spoken turn.
    func debugSay(_ text: String) { if state == .listening { studentSaid(text) } }
    #endif

    // MARK: Turns

    private func listen() {
        heard = ""
        caption = ""
        state = .listening
        guard !fake else { return }
        do { try listener.start() } catch { state = .waiting(error.localizedDescription) }
    }

    private func studentSaid(_ text: String) {
        listener.stop()
        heard = text
        let snap = snapshot()
        let turn = TutorTurn(fromStudent: true, text: text, snapshot: snap?.jpeg)
        context?.insert(turn)
        turn.attempt = attempt
        var content: [[String: Any]] = [["type": "text", "text": "She said: \"\(text)\""]]
        if let snap { content.append(contentsOf: snapshotBlocks(snap)) }
        content.append(["type": "text", "text": boardSummary()])
        history.append(["role": "user", "content": content])
        run = Task { await reply() }
    }

    /// No reply text in this long: give up on this turn rather than sit on "Thinking…".
    static let replyTimeout: TimeInterval = 60

    private func reply() async {
        guard !Task.isCancelled, state != .off else { return }
        state = .thinking
        caption = ""
        let (beats, feed) = AsyncStream.makeStream(of: TutorBeat.self)
        final class Box { var parser = TutorScriptParser(); var text = "" }
        let box = Box()
        let system = Prompts.tutor
        let messages = history
        let fake = self.fake
        let turnNumber = history.filter { $0["role"] as? String == "assistant" }.count
        let network = Task.detached { () -> Error? in
            let onText: (String) -> Void = { chunk in
                box.text += chunk
                for b in box.parser.feed(chunk) { feed.yield(b) }
            }
            do {
                if fake {
                    try await Self.fakeReply(turn: turnNumber, onText: onText)
                } else {
                    _ = try await ClaudeServices.live.client.converse(system: system, messages: messages, effort: .low,
                                                                       maxTokens: 6000, kind: "tutor", onText: onText)
                }
                for b in box.parser.finish() { feed.yield(b) }
                feed.finish()
                return nil
            } catch {
                feed.finish()
                return error
            }
        }
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.replyTimeout * 1_000_000_000))
            guard !Task.isCancelled, box.text.isEmpty else { return }
            self?.timedOut = true
            network.cancel()
        }
        for await beat in beats {
            if Task.isCancelled { break }
            await perform(beat)
        }
        watchdog.cancel()
        let cancelled = Task.isCancelled
        if cancelled { network.cancel() }
        var error = await network.value
        if timedOut { timedOut = false; error = TutorError.tooSlow }
        let said = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty {
            history.append(["role": "assistant", "content": [["type": "text", "text": said + (cancelled ? "\n[She interrupted you here.]" : "")]]])
            let turn = TutorTurn(fromStudent: false, text: said)
            context?.insert(turn)
            turn.attempt = attempt
            try? context?.save()
        } else {
            // Keep the conversation well-formed: no reply means her turn is dropped.
            history.removeLast()
        }
        guard !cancelled, state != .off else { return }
        if let error, said.isEmpty {
            let msg: String
            if case ClaudeClient.ClientError.missingAPIKey? = error as? ClaudeClient.ClientError {
                msg = "The tutor needs a Claude API key. Add one in Settings."
            } else if error is TutorError {
                msg = "The tutor is taking too long to answer. Tap Talk to try again."
            } else if error is URLError {
                msg = "Couldn't reach the tutor. Check the internet connection, then tap Talk."
            } else {
                msg = "Sorry, the tutor couldn't answer that one. Tap Talk to try again."
            }
            state = .waiting(msg)
            return
        }
        listen()
    }

    private func perform(_ beat: TutorBeat) async {
        switch beat {
        case let .point(id):
            pointer = id.flatMap { id in (parts + board).contains { $0.id == id } ? id : nil }
        case let .write(md):
            let id = "b\(board.count + 1)"
            board.append(PagePart(id: id, title: "Board line \(board.count + 1)", markdown: md))
            pointer = id
            try? await Task.sleep(nanoseconds: 350_000_000)   // let it render and scroll into view
        case let .say(text):
            state = .speaking
            caption = text
            await speaker.speak(text)
        }
    }

    // MARK: Context for Claude

    private func openingContext() -> [[String: Any]] {
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

    private func snapshotBlocks(_ s: PageSnapshot) -> [[String: Any]] {
        var note = "What she is looking at right now"
        if !s.visibleParts.isEmpty { note += " (showing: \(s.visibleParts.joined(separator: ", ")))" }
        note += s.newMarks ? ". Her new pencil marks are pink:" : ":"
        return [["type": "text", "text": note], ClaudeClient.Block.jpeg(s.jpeg).json]
    }

    private func boardSummary() -> String {
        board.isEmpty ? "The board is empty." : "The board so far:\n" + board.map { "[\($0.id)] \($0.markdown)" }.joined(separator: "\n")
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

    private static func fakeReply(turn: Int, onText: (String) -> Void) async throws {
        let script = turn == 0 ? """
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
        for line in script.components(separatedBy: "\n") {
            try await Task.sleep(nanoseconds: 120_000_000)
            onText(line + "\n")
        }
    }
}
