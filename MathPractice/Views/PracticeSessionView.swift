import SwiftUI
import SwiftData
import PencilKit

/// A 30-minute adaptive practice session.
struct PracticeSessionView: View {
    let chapter: Chapter
    static let sessionSeconds: TimeInterval = 30 * 60

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Phase { case answering, grading, feedback, summary }

    @State private var phase: Phase = .answering
    @State private var session = SessionState()
    @State private var current: Question?
    @State private var currentPick: Pick?
    @State private var drawing = PKDrawing()
    @State private var graphPaper = false
    @State private var questionClock = ActiveClock()
    @State private var sessionClock = ActiveClock()
    @State private var lastAttempt: Attempt?
    @State private var gradingError: String?
    @State private var sessionAttempts: [Attempt] = []
    @State private var now = Date()
    @State private var confirmQuit = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .summary:
                    SessionSummaryView(attempts: sessionAttempts, chapter: chapter) { dismiss() }
                default:
                    if let q = current { questionScreen(q) } else { noQuestions }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .summary ? "Close" : "End") {
                        if phase == .summary || sessionAttempts.isEmpty { dismiss() } else { confirmQuit = true }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if phase != .summary {
                        Text("Session \(formatClock(sessionClock.elapsed(now: now))) / 30:00").monospacedDigit().font(.headline)
                    }
                }
            }
            .confirmationDialog("End this session?", isPresented: $confirmQuit) {
                Button("End and see summary") { phase = .summary }
            }
        }
        .onAppear(perform: start)
        .onReceive(ticker) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { questionClock.resume(); sessionClock.resume() }
            else { questionClock.pause(); sessionClock.pause() }
        }
    }

    // MARK: Screens

    private var noQuestions: some View {
        ContentUnavailableView("Nothing to practice", systemImage: "checkmark.seal",
                               description: Text("There are no questions ready in this chapter yet."))
    }

    private func questionScreen(_ q: Question) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(q.concept?.name ?? "").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(String(repeating: "●", count: q.difficulty)).font(.caption2).foregroundStyle(.orange)
                    if currentPick?.category == .reinforcement {
                        Label("Another one like the last", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.blue)
                    }
                    Spacer()
                    timerView(q)
                }
                QuestionPanel(question: q)
            }
            .padding()
            .background(.bar)

            ZStack(alignment: .topTrailing) {
                WritingCanvas(drawing: $drawing, graphPaper: graphPaper)
                    .disabled(phase != .answering)
                Toggle(isOn: $graphPaper) { Image(systemName: "squareshape.split.3x3") }
                    .toggleStyle(.button)
                    .padding(8)
            }
            .overlay(alignment: .top) { bottomBar(q).padding(.top, 8) }
        }
    }

    @ViewBuilder
    private func timerView(_ q: Question) -> some View {
        let elapsed = questionClock.elapsed(now: now)
        if phase == .answering && LearningStore.inSpeedStage(q, in: chapter) {
            let target = LearningStore.targetSeconds(for: q, in: chapter)
            Label("\(formatClock(elapsed)) · goal \(formatClock(target))", systemImage: "stopwatch")
                .monospacedDigit()
                .foregroundStyle(elapsed > target ? .orange : .green)
        } else {
            Label(formatClock(phase == .answering ? elapsed : (lastAttempt?.activeSeconds ?? elapsed)), systemImage: "stopwatch")
                .monospacedDigit().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func bottomBar(_ q: Question) -> some View {
        Group {
            switch phase {
            case .answering:
                HStack(spacing: 16) {
                    Button { submit(stuck: true) } label: { Label("I'm stuck", systemImage: "questionmark.bubble") }
                        .buttonStyle(.bordered)
                    Button { drawing = PKDrawing() } label: { Label("Clear", systemImage: "trash") }
                        .buttonStyle(.bordered)
                        .disabled(drawing.strokes.isEmpty)
                    Button { submit(stuck: false) } label: { Label("Check my answer", systemImage: "checkmark") .font(.title3.bold()) }
                        .buttonStyle(.borderedProminent)
                        .disabled(drawing.strokes.isEmpty)
                }
                .padding()
                .background(.regularMaterial, in: Capsule())
                // Sits at the top of the canvas so the PencilKit tool picker never covers it.
            case .grading:
                VStack(spacing: 10) {
                    if let gradingError {
                        Text(gradingError).foregroundStyle(.red).multilineTextAlignment(.center)
                        HStack {
                            Button("Try again") { if let a = lastAttempt { grade(a) } }.buttonStyle(.borderedProminent)
                            Button("Skip — a parent will check") { skipGrading() }.buttonStyle(.bordered)
                        }
                    } else {
                        ProgressView()
                        Text("Checking your work…")
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            case .feedback:
                if let a = lastAttempt {
                    FeedbackCard(attempt: a, question: q, target: LearningStore.targetSeconds(for: q, in: chapter),
                                 showTime: LearningStore.inSpeedStage(q, in: chapter),
                                 willRepeat: a.effectiveVerdict == .incorrect) { next() }
                        .padding()
                }
            case .summary:
                EmptyView()
            }
        }
    }

    // MARK: Flow

    private func start() {
        sessionClock.reset()
        VariantGenerator.shared.refill(chapter, context: context)
        next()
    }

    private func next() {
        drawing = PKDrawing()
        lastAttempt = nil
        gradingError = nil
        if sessionClock.elapsed() >= Self.sessionSeconds, !sessionAttempts.isEmpty {
            phase = .summary
            return
        }
        let planner = LearningStore.planner(chapter)
        guard let pick = planner.next(session: session),
              let q = chapter.questions.first(where: { $0.id == pick.questionID }) else {
            current = nil
            if !sessionAttempts.isEmpty { phase = .summary }
            return
        }
        currentPick = pick
        current = q
        questionClock.reset()
        phase = .answering
    }

    private func submit(stuck: Bool) {
        guard let q = current else { return }
        questionClock.pause()
        let attempt = Attempt(mode: .practice, startedAt: Date().addingTimeInterval(-questionClock.elapsed()))
        attempt.activeSeconds = questionClock.elapsed()
        attempt.inkData = drawing.dataRepresentation()
        attempt.renderedImage = ImageUtils.renderDrawing(drawing)
        attempt.question = q
        context.insert(attempt)
        lastAttempt = attempt
        sessionAttempts.append(attempt)

        if stuck {
            attempt.verdict = .incorrect
            attempt.mistakeType = .conceptual
            attempt.feedback = "That's okay — let's look at how this one works. You'll get another one like it soon."
            attempt.graderConfidence = 1
            finish(attempt)
        } else {
            grade(attempt)
        }
    }

    private func grade(_ attempt: Attempt) {
        guard let q = attempt.question, let work = attempt.renderedImage else { skipGrading(); return }
        phase = .grading
        gradingError = nil
        let ctx = QuestionContext(text: q.text, figureJPEG: q.figureData, conceptName: q.concept?.name ?? "")
        let answer = q.referenceAnswer, solution = q.referenceSolution
        Task {
            do {
                let r = try await ClaudeServices.live.grade(ctx, referenceAnswer: answer, referenceSolution: solution, work: work)
                attempt.verdict = r.verdict
                attempt.mistakeType = r.mistake
                attempt.transcribedAnswer = r.transcribedAnswer
                attempt.errorStep = r.errorStep
                attempt.feedback = r.verdict == .needsReview
                    ? "I couldn't check this one for sure, so a parent will look at it. Let's keep going!"
                    : r.feedback
                attempt.graderConfidence = r.confidence
                finish(attempt)
            } catch {
                gradingError = error.localizedDescription
            }
        }
    }

    private func skipGrading() {
        guard let a = lastAttempt else { return }
        a.verdict = .needsReview
        a.feedback = "A parent will check this one."
        finish(a)
    }

    private func finish(_ attempt: Attempt) {
        attempt.isGraded = true
        LearningStore.apply(attempt, context: context)
        if let pick = currentPick {
            Planner.record(questionID: pick.questionID, cell: pick.cell,
                           correct: attempt.effectiveVerdict != .incorrect, in: &session)
        }
        try? context.save()
        phase = .feedback
        VariantGenerator.shared.refill(chapter, context: context)
    }
}

/// Result of one answer: verdict, where it went wrong, and help.
struct FeedbackCard: View {
    let attempt: Attempt
    let question: Question
    let target: Double
    let showTime: Bool
    let willRepeat: Bool
    let onNext: () -> Void
    @State private var showSolution = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                switch attempt.effectiveVerdict {
                case .correct:
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("Correct!").font(.title.bold())
                case .incorrect:
                    Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.red)
                    Text("Not quite").font(.title.bold())
                    if let m = attempt.mistakeType { Text(m.displayName).font(.subheadline).padding(6).background(.red.opacity(0.12), in: Capsule()) }
                case .needsReview:
                    Image(systemName: "questionmark.circle.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text("Saved for a parent").font(.title.bold())
                }
                Spacer()
                if showTime {
                    let fast = attempt.activeSeconds <= target
                    Label("\(formatClock(attempt.activeSeconds)) (goal \(formatClock(target)))", systemImage: fast ? "bolt.fill" : "tortoise.fill")
                        .foregroundStyle(fast ? .green : .orange).monospacedDigit()
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !attempt.feedback.isEmpty { MathText(markdown: attempt.feedback, fontSize: 19) }
                    if attempt.effectiveVerdict == .incorrect, !attempt.errorStep.isEmpty {
                        MathText(markdown: "**Where it went wrong:** \(attempt.errorStep)", fontSize: 17)
                    }
                    if attempt.effectiveVerdict == .incorrect, attempt.mistakeType == .conceptual,
                       let example = question.concept?.workedExample, !example.isEmpty {
                        Text("Worked example").font(.headline)
                        MathText(markdown: example, fontSize: 17)
                    }
                    if attempt.effectiveVerdict == .incorrect {
                        DisclosureGroup("See a full solution", isExpanded: $showSolution) {
                            MathText(markdown: question.referenceSolution, fontSize: 17)
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
            HStack {
                if willRepeat {
                    Label("You'll get another one like this soon.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onNext) { Label("Next question", systemImage: "arrow.right").font(.title3.bold()) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 12)
    }
}

struct SessionSummaryView: View {
    let attempts: [Attempt]
    let chapter: Chapter
    let onDone: () -> Void

    var body: some View {
        let stats = SessionStats(attempts: attempts)
        let mistakes = Dictionary(grouping: attempts.compactMap { $0.effectiveVerdict == .incorrect ? $0.mistakeType : nil }, by: { $0 })
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "star.circle.fill").font(.system(size: 64)).foregroundStyle(.yellow)
                Text("Session done!").font(.largeTitle.bold())
                HStack(spacing: 40) {
                    VStack { Text("\(stats.total)").font(.largeTitle.bold()); Text("questions") }
                    VStack { Text("\(stats.correct)").font(.largeTitle.bold()).foregroundStyle(.green); Text("correct") }
                    VStack { Text("\(Int(attempts.map(\.activeSeconds).reduce(0, +) / 60))").font(.largeTitle.bold()); Text("minutes") }
                }
                if !mistakes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Things to watch").font(.title3.bold())
                        ForEach(mistakes.keys.sorted { mistakes[$0]!.count > mistakes[$1]!.count }, id: \.self) { m in
                            Text("• \(m.displayName): \(mistakes[m]!.count)× — \(Self.tip(m))")
                        }
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                }
                MasteryGrid(chapter: chapter).frame(maxWidth: 700)
                Button("Done", action: onDone).buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(32)
        }
    }

    static func tip(_ m: MistakeType) -> String {
        switch m {
        case .conceptual: return "review the worked example before the next session."
        case .procedural: return "slow down on that step and write it out fully."
        case .careless: return "check each line once before moving on."
        case .misread: return "underline what the question asks before starting."
        case .incomplete: return "make sure you answer every part."
        }
    }
}
