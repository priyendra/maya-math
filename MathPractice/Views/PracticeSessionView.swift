import SwiftUI
import SwiftData
import PencilKit

/// A 30-minute adaptive practice session. Answers are graded in the background; results are shown at
/// check-ins (~every 10 minutes and at the end), except conceptual mistakes, which are shown at the next
/// question boundary.
struct PracticeSessionView: View {
    let set: StudySet
    /// Start with this question (e.g. "Practice this question" from the chapter).
    var startQuestionID: UUID?
    static let sessionSeconds: TimeInterval = 30 * 60
    static let checkInSeconds: TimeInterval = 10 * 60
    static let finalWaitSeconds: TimeInterval = 90

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var grading = GradingQueue.shared

    enum Phase: Equatable { case answering, checkIn, finishing, summary }

    @State private var phase: Phase = .answering
    @State private var session = SessionState()
    @State private var current: Question?
    @State private var currentPick: Pick?
    @State private var drawing = PKDrawing()
    @State private var graphPaper = false
    @State private var questionClock = ActiveClock()
    @State private var sessionClock = ActiveClock()
    @State private var sessionAttempts: [Attempt] = []
    @State private var cellOfAttempt: [UUID: CellKey] = [:]
    @State private var processed: Set<UUID> = []
    @State private var lastCheckInAt: TimeInterval = 0
    @State private var checkInItems: [Attempt] = []
    @State private var checkInKind: CheckInView.Kind = .regular
    @State private var finishingSince: Date?
    @State private var now = Date()
    @State private var confirmQuit = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .summary:
                    SessionSummaryView(attempts: sessionAttempts, set: set) { dismiss() }
                case .checkIn:
                    CheckInView(items: checkInItems, pending: sessionAttempts.filter { !$0.isGraded }.count,
                                kind: checkInKind, onContinue: continueAfterCheckIn)
                case .finishing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Checking your last answers…").font(.title3)
                        Text("\(sessionAttempts.filter { !$0.isGraded }.count) still being checked").foregroundStyle(.secondary)
                    }
                case .answering:
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
                Button("End and see how I did") { finish() }
            }
        }
        .onAppear(perform: start)
        .onReceive(ticker) { t in
            now = t
            if phase == .finishing, let since = finishingSince, t.timeIntervalSince(since) > Self.finalWaitSeconds { showFinal() }
        }
        .onChange(of: grading.version) { _, _ in absorbGrades() }
        .onChange(of: scenePhase) { _, p in
            if p == .active {
                sessionClock.resume()
                if phase == .answering { questionClock.resume() }
                GradingQueue.shared.resumePending(context: context)
            } else { questionClock.pause(); sessionClock.pause() }
        }
    }

    // MARK: Screens

    private var noQuestions: some View {
        ContentUnavailableView("Nothing to practice", systemImage: "checkmark.seal",
                               description: Text("There are no questions in this scope yet."))
    }

    private func questionScreen(_ q: Question) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(q.concept?.name ?? "").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(String(repeating: "●", count: q.difficulty)).font(.caption2).foregroundStyle(.orange)
                    if q.isChallenge { Label("Challenge", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.red) }
                    if currentPick?.category == .reinforcement {
                        Label("Another one like an earlier one", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.blue)
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
                Toggle(isOn: $graphPaper) { Image(systemName: "squareshape.split.3x3") }
                    .toggleStyle(.button)
                    .padding(8)
            }
            .overlay(alignment: .top) { actionBar.padding(.top, 8) }
        }
    }

    @ViewBuilder
    private func timerView(_ q: Question) -> some View {
        let elapsed = questionClock.elapsed(now: now)
        if LearningStore.inSpeedStage(q) {
            let target = LearningStore.targetSeconds(for: q)
            Label("\(formatClock(elapsed)) · goal \(formatClock(target))", systemImage: "stopwatch")
                .monospacedDigit()
                .foregroundStyle(elapsed > target ? .orange : .green)
        } else {
            Label(formatClock(elapsed), systemImage: "stopwatch").monospacedDigit().foregroundStyle(.secondary)
        }
    }

    /// Sits at the top of the canvas so the PencilKit tool picker never covers it.
    private var actionBar: some View {
        HStack(spacing: 16) {
            Button { submit(stuck: true) } label: { Label("I'm stuck", systemImage: "questionmark.bubble") }
                .buttonStyle(.bordered)
            Button { drawing = PKDrawing() } label: { Label("Clear", systemImage: "trash") }
                .buttonStyle(.bordered)
                .disabled(drawing.strokes.isEmpty)
            Button { submit(stuck: false) } label: { Label("Next", systemImage: "arrow.right").font(.title3.bold()) }
                .buttonStyle(.borderedProminent)
                .disabled(drawing.strokes.isEmpty)
        }
        .padding()
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: Flow

    private func start() {
        sessionClock.reset()
        GradingQueue.shared.resumePending(context: context)
        VariantGenerator.shared.refill(set, context: context)
        if let id = startQuestionID, let q = set.questions.first(where: { $0.id == id }) ?? set.chapters.lazy.flatMap(\.questions).first(where: { $0.id == id }),
           let cell = LearningStore.cellKey(q) {
            show(q, pick: Pick(questionID: q.id, cell: cell, category: .weak))
        } else {
            nextQuestion()
        }
    }

    private func show(_ q: Question, pick: Pick) {
        drawing = PKDrawing()
        currentPick = pick
        current = q
        questionClock.reset()
        phase = .answering
    }

    private func nextQuestion() {
        let planner = LearningStore.planner(set)
        guard let pick = planner.next(session: session),
              let q = set.questions.first(where: { $0.id == pick.questionID }) else {
            current = nil
            if !sessionAttempts.isEmpty { finish() }
            return
        }
        show(q, pick: pick)
    }

    private func submit(stuck: Bool) {
        guard let q = current, let pick = currentPick else { return }
        questionClock.pause()
        let attempt = Attempt(mode: .practice, startedAt: Date().addingTimeInterval(-questionClock.elapsed()))
        attempt.activeSeconds = questionClock.elapsed()
        attempt.inkData = drawing.dataRepresentation()
        attempt.renderedImage = ImageUtils.renderDrawing(drawing)
        attempt.wasStuck = stuck
        attempt.question = q
        context.insert(attempt)
        try? context.save()
        sessionAttempts.append(attempt)
        cellOfAttempt[attempt.id] = pick.cell
        Planner.asked(q.id, in: &session)
        GradingQueue.shared.enqueue(attempt, context: context)
        advance()
    }

    /// Decides what comes after a question: an interruption, a check-in, the end, or the next question.
    private func advance() {
        let unrevealed = sessionAttempts.filter { $0.isGraded && !$0.revealed }
        if let c = unrevealed.first(where: { $0.effectiveVerdict == .incorrect && $0.mistakeType == .conceptual }) {
            present([c], kind: .interruption)
        } else if sessionClock.elapsed() - lastCheckInAt >= Self.checkInSeconds, !unrevealed.isEmpty {
            lastCheckInAt = sessionClock.elapsed()
            present(unrevealed, kind: .regular)
        } else if sessionClock.elapsed() >= Self.sessionSeconds {
            finish()
        } else {
            nextQuestion()
        }
    }

    private func present(_ items: [Attempt], kind: CheckInView.Kind) {
        checkInItems = items
        checkInKind = kind
        phase = .checkIn
    }

    private func continueAfterCheckIn() {
        for a in checkInItems { a.revealed = true }
        try? context.save()
        if checkInKind == .final { phase = .summary; return }
        if sessionClock.elapsed() >= Self.sessionSeconds { finish(); return }
        nextQuestion()
    }

    private func finish() {
        questionClock.pause()
        current = nil
        if sessionAttempts.allSatisfy(\.isGraded) { showFinal() }
        else {
            finishingSince = Date()
            phase = .finishing
            GradingQueue.shared.resumePending(context: context)
        }
    }

    private func showFinal() {
        finishingSince = nil
        let unrevealed = sessionAttempts.filter { $0.isGraded && !$0.revealed }
        if unrevealed.isEmpty { phase = .summary } else { present(unrevealed, kind: .final) }
    }

    /// Feeds newly arrived grades into the session (re-practice after a miss).
    private func absorbGrades() {
        for a in sessionAttempts where a.isGraded && !processed.contains(a.id) {
            processed.insert(a.id)
            if let cell = cellOfAttempt[a.id], a.question?.isChallenge == false {
                Planner.graded(cell: cell, correct: a.effectiveVerdict != .incorrect, in: &session)
            }
        }
        if phase == .finishing, sessionAttempts.allSatisfy(\.isGraded) { showFinal() }
        VariantGenerator.shared.refill(set, context: context)
    }
}

/// One graded answer in detail: verdict, where it went wrong, tip, and the solution on request.
struct FeedbackCard: View {
    let attempt: Attempt
    let question: Question
    var showWork = true
    @State private var showSolution = false
    @State private var disagree = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VerdictBadge(verdict: attempt.effectiveVerdict).font(.title)
                switch attempt.effectiveVerdict {
                case .correct: Text("Correct").font(.title2.bold())
                case .incorrect: Text(attempt.wasStuck ? "Let's see how this one works" : "Not quite").font(.title2.bold())
                case .needsReview: Text("Couldn't check this one for sure").font(.title2.bold())
                }
                if attempt.effectiveVerdict == .incorrect, !attempt.wasStuck, let m = attempt.mistakeType {
                    Text(m.displayName).font(.subheadline).padding(6).background(.red.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(formatClock(attempt.activeSeconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            QuestionPanel(question: question)
            if showWork, !attempt.wasStuck, let data = attempt.renderedImage, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 260)
                    .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if attempt.effectiveVerdict == .incorrect, !attempt.errorStep.isEmpty, !attempt.wasStuck {
                MathText(markdown: "**Where it went wrong:** \(attempt.errorStep)", fontSize: 17)
            }
            if !attempt.feedback.isEmpty, !attempt.wasStuck { MathText(markdown: attempt.feedback, fontSize: 17) }
            if attempt.effectiveVerdict == .incorrect, !attempt.workedSolution.isEmpty {
                if attempt.wasStuck {
                    MathText(markdown: attempt.workedSolution, fontSize: 17)
                } else {
                    DisclosureGroup("Show solution", isExpanded: $showSolution) {
                        MathText(markdown: attempt.workedSolution, fontSize: 17)
                    }
                }
                Label("You'll get another one like this soon.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !attempt.wasStuck {
                Button("Disagree with the grade?") { disagree = true }.font(.subheadline)
            }
        }
        .padding(20)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $disagree) { NavigationStack { AttemptReviewView(attempt: attempt) } }
    }
}

struct SessionSummaryView: View {
    let attempts: [Attempt]
    let set: StudySet
    let onDone: () -> Void

    var body: some View {
        let stats = SessionStats(attempts: attempts)
        let mistakes = Dictionary(grouping: attempts.compactMap { $0.effectiveVerdict == .incorrect && !$0.wasStuck ? $0.mistakeType : nil }, by: { $0 })
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
                MasteryGrid(set: set).frame(maxWidth: 700)
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
