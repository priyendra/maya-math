import Foundation
import SwiftData
import AVFoundation

/// A part of a page the tutor can point at.
struct PagePart: Identifiable, Equatable {
    let id: String          // "question", "work", "wrong", "s1"…, "b1"…, "p2e3"…
    let title: String       // for Claude: what this part is
    let markdown: String    // its text ("" for her handwriting)
}

/// What the student sees right now: a picture of the visible part of the page with her ink, and which parts it shows.
struct PageSnapshot {
    let jpeg: Data
    let visibleParts: [String]
    let newMarks: Bool
}

/// The voice tutor engine shared by the solution page and lessons: speaks tagged replies (SAY / WRITE / POINT) as
/// they stream in, listens hands-free (a short silence ends her turn; tapping the page stops the tutor), keeps the
/// board and the cursor. Subclasses supply what the conversation is about.
@MainActor
class VoiceTutor: ObservableObject {
    enum State: Equatable {
        case off, starting, thinking, speaking, listening, waiting(String)
    }

    @Published var state: State = .off
    /// What she is saying, live.
    @Published var heard = ""
    /// Lines the tutor wrote on the board (ids b1, b2…).
    @Published var board: [PagePart] = []
    /// The page part the cursor is on.
    @Published var pointer: String?
    /// The tutor's current sentence (caption).
    @Published var caption = ""

    /// Set by the page: captures what she's looking at.
    var snapshot: () -> PageSnapshot? = { nil }

    let speaker = Speaker()
    let listener = Listener()
    var history: [[String: Any]] = []
    var run: Task<Void, Never>?
    let fake: Bool
    /// The last live reply ended with CONTINUE.
    private(set) var resumeRequested = false
    private var timedOut = false
    private enum TutorError: Error { case tooSlow }

    var isOn: Bool { state != .off }

    init() {
        #if DEBUG
        fake = ProcessInfo.processInfo.arguments.contains("-fakeTutor")
        #else
        fake = false
        #endif
        speaker.silent = fake
        listener.onHeard = { [weak self] in self?.heard = $0 }
        listener.onFinished = { [weak self] in self?.studentSaid($0) }
        listener.onGaveUp = { [weak self] in self?.gaveUpListening() }
    }

    // MARK: Hooks for subclasses

    var systemPrompt: String { Prompts.tutor }
    /// Everything the cursor may point at (besides the board).
    var pageParts: [PagePart] { [] }
    /// Sent before her first words if the conversation hasn't started yet (cached context).
    func openingContext() -> [[String: Any]] { [] }
    /// Extra text sent with each of her turns.
    func turnContext() -> String { boardSummary() }
    /// Saves a turn of the conversation.
    func recordTurn(fromStudent: Bool, text: String, snapshot: Data?) {}
    /// After a reply was spoken. Default: listen for her answer.
    func replyFinished() { listen() }
    func gaveUpListening() { state = .waiting("Tap Talk when you want to say something.") }
    /// Canned replies for UI tests.
    func fakeScript(turn: Int) -> String { "SAY: Okay.\n" }

    // MARK: Control

    /// Mic permission and audio session (once per talk). Returns false (and says why) if she can't talk.
    func prepareAudio() async -> Bool {
        guard !fake else { return true }
        let ok = await Listener.requestPermissions()
        guard ok else {
            state = .waiting("To talk with the tutor, allow the microphone and speech recognition in Settings → Maya Math.")
            return false
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        return true
    }

    /// She tapped the page or the stop button: stop talking and listen.
    func interrupt() {
        guard state == .speaking || state == .thinking else { return }
        run?.cancel()
        speaker.stop()
        listen()
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
    }

    /// Her pencil moved: she may be marking something while she talks.
    func inkChanged() { listener.noteActivity() }

    #if DEBUG
    /// UI tests can't speak: stands in for a finished spoken turn.
    func debugSay(_ text: String) { if state == .listening { studentSaid(text) } }
    #endif

    // MARK: Turns

    func listen() {
        heard = ""
        caption = ""
        state = .listening
        guard !fake else { return }
        do { try listener.start() } catch { state = .waiting(error.localizedDescription) }
    }

    func studentSaid(_ text: String) {
        listener.stop()
        heard = text
        let snap = snapshot()
        recordTurn(fromStudent: true, text: text, snapshot: snap?.jpeg)
        var content: [[String: Any]] = history.isEmpty ? openingContext() : []
        content.append(["type": "text", "text": "She said: \"\(text)\""])
        if let snap { content.append(contentsOf: snapshotBlocks(snap)) }
        content.append(["type": "text", "text": turnContext()])
        ask(content)
    }

    /// Sends a user turn and plays the reply.
    func ask(_ content: [[String: Any]]) {
        history.append(["role": "user", "content": content])
        run = Task { await reply() }
    }

    /// No reply text in this long: give up on this turn rather than sit on "Thinking…".
    static let replyTimeout: TimeInterval = 60

    func reply() async {
        guard !Task.isCancelled, state != .off else { return }
        state = .thinking
        caption = ""
        resumeRequested = false
        let (beats, feed) = AsyncStream.makeStream(of: TutorBeat.self)
        final class Box { var parser = TutorScriptParser(); var text = "" }
        let box = Box()
        let system = systemPrompt
        let messages = history
        let fake = self.fake
        let script = fakeScript(turn: history.filter { $0["role"] as? String == "assistant" }.count)
        let network = Task.detached { () -> Error? in
            let onText: (String) -> Void = { chunk in
                box.text += chunk
                for b in box.parser.feed(chunk) { feed.yield(b) }
            }
            do {
                if fake {
                    for line in script.components(separatedBy: "\n") {
                        try await Task.sleep(nanoseconds: 120_000_000)
                        onText(line + "\n")
                    }
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
            recordTurn(fromStudent: false, text: said, snapshot: nil)
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
        replyFinished()
    }

    func perform(_ beat: TutorBeat) async {
        switch beat {
        case let .point(id):
            pointer = id.flatMap(resolvePointer)
        case let .write(md):
            let id = "b\(board.count + 1)"
            board.append(PagePart(id: id, title: "Board line \(board.count + 1)", markdown: md))
            boardWritten(id)
            pointer = id
            try? await Task.sleep(nanoseconds: 350_000_000)   // let it render and scroll into view
        case let .say(text):
            state = .speaking
            caption = text
            await speaker.speak(text)
        case .resume:
            resumeRequested = true
        }
    }

    /// A pointer id as written by Claude → a part on the page (nil if unknown).
    func resolvePointer(_ id: String) -> String? {
        (pageParts + board).contains { $0.id == id } ? id : nil
    }

    /// A board line was added (lessons place it under the current part).
    func boardWritten(_ id: String) {}

    // MARK: Context helpers

    func snapshotBlocks(_ s: PageSnapshot) -> [[String: Any]] {
        var note = "What she is looking at right now"
        if !s.visibleParts.isEmpty { note += " (showing: \(s.visibleParts.joined(separator: ", ")))" }
        note += s.newMarks ? ". Her new pencil marks are pink:" : ":"
        return [["type": "text", "text": note], ClaudeClient.Block.jpeg(s.jpeg).json]
    }

    func boardSummary() -> String {
        board.isEmpty ? "The board is empty." : "The board so far:\n" + board.map { "[\($0.id)] \($0.markdown)" }.joined(separator: "\n")
    }
}
