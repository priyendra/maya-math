import Foundation
import SwiftData

/// Teaches a lesson part by part: shows the part's book content, plays its saved narration (pointing and writing
/// as it goes), stops for questions whenever she taps or speaks, then gives her a problem to try, which is graded
/// like practice. Her questions and wrong answers get live tutor replies.
@MainActor
final class LessonSession: VoiceTutor {
    enum Phase: Equatable {
        case preparing          // writing the next part's script
        case narrating          // playing the script (may be paused for a question)
        case questions          // part explained: "any questions before you try one?"
        case yourTurn           // she's working on a problem
        case checking           // grading her answer
        case reviewing          // the tutor is going over her wrong answer
        case done
        case failed(String)
    }

    /// One thing on the lesson page, in the order it appeared (the page only grows, so her ink stays put).
    enum Element: Identifiable, Equatable {
        case header(part: Int, title: String, earlier: Bool)
        case item(LessonPartScript.Item)
        case board(PagePart)
        case turn(id: String, question: UUID)
        case finished

        var id: String {
            switch self {
            case let .header(p, _, _): return "h\(p)"
            case let .item(i): return i.id
            case let .board(b): return b.id
            case let .turn(id, _): return id
            case .finished: return "finished"
            }
        }
    }

    let lesson: Lesson
    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var elements: [Element] = []
    @Published private(set) var currentPart = 0
    /// Her answers in this lesson, by turn id.
    @Published private(set) var answers: [String: Attempt] = [:]
    /// Ask the page to scroll something into view (e.g. the writing space under a problem).
    @Published private(set) var revealRequest: String?
    /// Called by the page to get her work for a turn: the ink written below the problem.
    var workBelow: (String) -> (ink: Data, image: Data)? = { _ in nil }

    private var context: ModelContext? { lesson.modelContext }
    private var script: LessonPartScript?
    private var beats: [TutorBeat] = []
    private var beatIndex = 0
    private var spoken: [String] = []
    private var tryNumber = 1
    private var currentTurn: (id: String, question: Question)?
    private var writing: [Int: Task<LessonPartScript, Error>] = [:]
    private var started = false

    init(lesson: Lesson) {
        self.lesson = lesson
        super.init()
    }

    var parts: [LessonPart] { lesson.parts }
    var questionsByID: [UUID: Question] {
        Dictionary(uniqueKeysWithValues: (lesson.chapter?.questions ?? []).map { ($0.id, $0) })
    }

    // MARK: Flow

    func start() {
        guard !started else { return }
        started = true
        lesson.lastOpened = Date()
        if lesson.status == .notStarted { lesson.status = .inProgress }
        if lesson.status == .done { lesson.partsDone = 0; lesson.status = .inProgress }   // taking it again
        try? context?.save()
        for i in 0..<min(lesson.partsDone, parts.count) {
            elements.append(.header(part: i, title: parts[i].title, earlier: true))
        }
        state = .starting
        run = Task {
            guard await prepareAudio() else { return }
            await begin(part: lesson.partsDone)
        }
    }

    private func begin(part i: Int) async {
        guard i < parts.count else { finishLesson(); return }
        currentPart = i
        tryNumber = 1
        currentTurn = nil
        phase = .preparing
        state = .starting
        do {
            let s = try await scriptFor(i)
            guard !Task.isCancelled else { return }
            script = s
            if i + 1 < parts.count { _ = writeScript(i + 1) }   // get the next part ready while she listens
            elements.append(.header(part: i, title: parts[i].title, earlier: false))
            elements += s.items.map(Element.item)
            beats = s.narration.components(separatedBy: "\n").compactMap(TutorScriptParser.beat)
            beatIndex = 0
            phase = .narrating
            play()
        } catch {
            guard !Task.isCancelled else { return }
            let msg: String
            if case ClaudeClient.ClientError.missingAPIKey? = error as? ClaudeClient.ClientError {
                msg = "Lessons need a Claude API key. Add one in Settings."
            } else if error is URLError {
                msg = "Couldn't get this part ready. Check the internet connection, then tap Try again."
            } else {
                msg = "Couldn't get this part ready. Tap Try again."
            }
            phase = .failed(msg)
            state = .waiting(msg)
        }
    }

    private func writeScript(_ i: Int) -> Task<LessonPartScript, Error> {
        if let t = writing[i] { return t }
        let lesson = self.lesson
        let context = self.context
        let t = Task { @MainActor () throws -> LessonPartScript in
            guard let context else { throw CancellationError() }
            return try await LessonWriter.script(lesson, part: i, context: context)
        }
        writing[i] = t
        return t
    }

    private func scriptFor(_ i: Int) async throws -> LessonPartScript {
        do { return try await writeScript(i).value } catch { writing[i] = nil; throw error }
    }

    func retry() {
        guard case .failed = phase else { return }
        run = Task { await begin(part: currentPart) }
    }

    /// Plays the narration from where it stopped.
    private func play() {
        run = Task {
            while beatIndex < beats.count {
                if Task.isCancelled { return }
                // Have the next few sentences' voice ready before they're needed.
                var ahead = 0
                for b in beats[beatIndex...] where ahead < 3 {
                    if case let .say(t) = b { speaker.prefetch(t); ahead += 1 }
                }
                await perform(beats[beatIndex])
                if Task.isCancelled { return }   // interrupted mid-sentence: that sentence plays again on resume
                if case let .say(t) = beats[beatIndex] { spoken.append(t) }
                beatIndex += 1
            }
            narrationEnded()
        }
    }

    private func narrationEnded() {
        pointer = nil
        if script?.questionIDs.isEmpty ?? true {
            completePart()
            return
        }
        phase = .questions
        listen()
    }

    /// "Go on": carry on with whatever comes next.
    func goOn() {
        listener.stop()
        speaker.stop()
        run?.cancel()
        heard = ""
        switch phase {
        case .narrating: play()
        case .questions: startYourTurn()
        case .reviewing:
            if tryNumber == 1, let ids = script?.questionIDs, ids.count > 1 {
                tryNumber = 2
                startYourTurn()
            } else {
                completePart()
            }
        case .yourTurn, .checking, .preparing, .done, .failed: break
        }
    }

    /// She wants to ask something (Ask button, or Pause while the tutor talks).
    func ask() {
        if state == .speaking || state == .thinking { interrupt(); return }
        speaker.stop()
        listen()
    }

    private func startYourTurn() {
        guard let ids = script?.questionIDs, ids.indices.contains(tryNumber - 1),
              let q = questionsByID[ids[tryNumber - 1]] else { completePart(); return }
        let id = "turn\(currentPart + 1)_\(tryNumber)"
        currentTurn = (id, q)
        elements.append(.turn(id: id, question: q.id))
        pointer = id
        revealRequest = id + "_room"
        phase = .yourTurn
        run = Task {
            state = .speaking
            let line = tryNumber == 1 ? "Here's one for you to try. Write your answer under the problem, then tap Check."
                                      : "Let's try another one. Write your answer under it, then tap Check."
            caption = line
            await speaker.speak(line)
            guard !Task.isCancelled, phase == .yourTurn else { return }
            state = .waiting("Write your answer under the problem, then tap Check.")
        }
    }

    /// She tapped Check.
    func check() {
        guard phase == .yourTurn, let turn = currentTurn, let context else { return }
        guard let work = workBelow(turn.id) else {
            state = .waiting("Write your answer under the problem first, then tap Check.")
            return
        }
        speaker.stop()
        run?.cancel()
        let attempt = Attempt(mode: .lesson)
        attempt.inkData = work.ink
        attempt.renderedImage = work.image
        attempt.question = turn.question
        context.insert(attempt)
        try? context.save()
        answers[turn.id] = attempt
        phase = .checking
        state = .waiting("Checking your answer…")
        if fake {
            let wrong = ProcessInfo.processInfo.arguments.contains("-fakeWrongOnce") && answers.count == 1
            let r = GradeResult(verdict: wrong ? .incorrect : .correct, mistake: wrong ? .procedural : nil,
                                transcribedAnswer: "(x+5)(x-5)", ownAnswer: "(x+5)(x-5)", errorStep: wrong ? "The signs" : "",
                                feedback: wrong ? "Check the signs." : "", workedSolution: "", questionFlawed: false, confidence: 1)
            GradingQueue.shared.record(attempt, r, context: context)
        } else {
            GradingQueue.shared.enqueue(attempt, context: context)
        }
        run = Task {
            var waited = 0.0
            while !attempt.isGraded {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                waited += 0.4
                if waited > 15, attempt.gradingError != nil {
                    state = .waiting("Still checking… (\(attempt.gradingError ?? "")). It will keep trying.")
                }
            }
            await graded(attempt)
        }
    }

    private func graded(_ a: Attempt) async {
        switch a.effectiveVerdict {
        case .correct:
            state = .speaking
            caption = "That's right! Well done."
            await speaker.speak(caption)
            guard !Task.isCancelled else { return }
            completePart()
        case .needsReview:
            state = .speaking
            caption = "I couldn't quite read that one, so let's keep going."
            await speaker.speak(caption)
            guard !Task.isCancelled else { return }
            completePart()
        case .incorrect:
            phase = .reviewing
            var content: [[String: Any]] = history.isEmpty ? openingContext() : []
            func text(_ s: String) { content.append(["type": "text", "text": s]) }
            text("She answered the \"your turn\" problem [turn] (try \(tryNumber) of 2):\n\(a.question?.text ?? "")")
            if let img = a.renderedImage { text("Her work:"); content.append(ClaudeClient.Block.png(img).json) }
            var g = "Grading: not correct"
            if let m = a.mistakeType, a.effectiveVerdict == .incorrect { g += " (mistake type: \(m.displayName.lowercased()))" }
            if !a.transcribedAnswer.isEmpty { g += "\nHer answer read as: \(a.transcribedAnswer)" }
            if !a.errorStep.isEmpty { g += "\nWhere it went wrong: \(a.errorStep)" }
            if !a.feedback.isEmpty { g += "\nFeedback: \(a.feedback)" }
            if !a.ownAnswer.isEmpty { g += "\nCorrect answer: \(a.ownAnswer)" }
            text(g)
            if let snap = snapshot() { content += snapshotBlocks(snap) }
            text(turnContext())
            text(tryNumber == 1 && (script?.questionIDs.count ?? 0) > 1
                 ? "Explain briefly what went wrong; she will get one more problem like it after this."
                 : "Explain briefly what went wrong and show the right answer; then the lesson moves on.")
            ask(content)
        }
    }

    private func completePart() {
        pointer = nil
        lesson.partsDone = max(lesson.partsDone, currentPart + 1)
        try? context?.save()
        run = Task { await begin(part: currentPart + 1) }
    }

    private func finishLesson() {
        lesson.status = .done
        lesson.partsDone = parts.count
        try? context?.save()
        phase = .done
        elements.append(.finished)
        run = Task {
            state = .speaking
            caption = "That's the end of this lesson. Great work!"
            await speaker.speak(caption)
            guard !Task.isCancelled else { return }
            state = .off
        }
    }

    // MARK: Voice hooks

    override var systemPrompt: String { Prompts.lessonTutor }

    override var pageParts: [PagePart] {
        elements.compactMap { e in
            switch e {
            case let .item(i): return PagePart(id: i.id, title: i.kind, markdown: i.markdown)
            case let .turn(id, q): return PagePart(id: id, title: "Your-turn problem", markdown: questionsByID[q]?.text ?? "")
            default: return nil
            }
        }
    }

    override func resolvePointer(_ raw: String) -> String? {
        var id = raw
        if id == "turn", let t = currentTurn { id = t.id }
        if id.range(of: "^e\\d+$", options: .regularExpression) != nil { id = "p\(currentPart + 1)" + id }
        return super.resolvePointer(id)
    }

    override func boardWritten(_ id: String) {
        if let b = board.last, b.id == id { elements.append(.board(b)) }
    }

    override func studentSaid(_ text: String) {
        if Self.isGoOn(text) && phase != .yourTurn {
            goOn()
            return
        }
        super.studentSaid(text)
    }

    override func replyFinished() {
        if resumeRequested && phase != .yourTurn { goOn() } else if phase == .yourTurn { state = .waiting("Write your answer under the problem, then tap Check.") } else { listen() }
    }

    override func gaveUpListening() {
        state = .waiting(phase == .questions ? "Tap Go on when you're ready, or Ask if you have a question."
                                              : "Tap Go on to carry on, or Ask to say something.")
    }

    override func openingContext() -> [[String: Any]] {
        var s = "The lesson: \(lesson.title)\n\(lesson.summary)\nParts:\n"
        for (i, p) in parts.enumerated() { s += "\(i + 1). \(p.title)\n" }
        if let chapter = lesson.chapter {
            let sections = Set(parts.flatMap(\.sectionIDs))
            let text = chapter.sortedBlocks
                .filter { sections.contains($0.sectionID) && ["heading", "text", "example"].contains($0.kind) }
                .map(\.markdown).joined(separator: "\n\n")
            s += "\nThe book's content for this lesson:\n\n" + String(text.prefix(20000))
        }
        return [["type": "text", "text": s, "cache_control": ["type": "ephemeral"]]]
    }

    override func turnContext() -> String {
        var s = "Where we are: part \(currentPart + 1) of \(parts.count), \"\(parts.indices.contains(currentPart) ? parts[currentPart].title : "")\"."
        switch phase {
        case .narrating: s += " You were explaining it when she spoke."
        case .questions: s += " You just finished explaining it and asked if she has questions."
        case .yourTurn: s += " She is working on the your-turn problem."
        case .reviewing: s += " You are going over her answer to the your-turn problem."
        default: break
        }
        if !spoken.isEmpty { s += "\nWhat you said last:\n" + spoken.suffix(4).joined(separator: "\n") }
        let items = pageParts.filter { $0.id.hasPrefix("p\(currentPart + 1)") || $0.id.hasPrefix("turn") }
        s += "\n\nOn the page (ids you can POINT at):\n" + items.map { "[\($0.id)] \($0.markdown)" }.joined(separator: "\n")
        s += "\n\n" + boardSummary()
        return s
    }

    override func fakeScript(turn: Int) -> String {
        """
        SAY: Good question.
        POINT: e1
        SAY: This is the rule we are using.
        WRITE: $49 = 7^2$
        SAY: Does that help?
        CONTINUE
        """
    }

    /// "Go on", "no", "next"…: she's ready to carry on (no need to ask Claude).
    nonisolated static func isGoOn(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let phrases = ["go on", "continue", "next", "keep going", "carry on", "no", "nope", "no questions",
                       "no thanks", "no thank you", "i'm ready", "im ready", "ready", "let's go", "lets go",
                       "i'm good", "im good", "move on", "let's continue", "lets continue", "no i'm good", "got it",
                       "okay go on", "ok go on", "yes go on"]
        return phrases.contains(t)
    }
}
