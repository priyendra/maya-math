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
    @StateObject private var canvas = CanvasController()
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
    @State private var confirmQuit = false
    /// "I'm stuck" help for the current question: a hint first (she keeps going), then the full solution.
    enum Help: Equatable { case none, loadingHint, hint, loadingSolution, solution }
    @State private var help: Help = .none
    @State private var hintText = ""
    @State private var solutionText = ""
    @State private var helpError: String?
    /// Break: clocks stopped, question and canvas hidden.
    @State private var solutionAttempt: Attempt?
    @State private var tutorOpen = false
    @State private var paused = false
    /// Looking back at earlier questions of this session: clocks stopped.
    @State private var browsing = false
    /// Reading the question's place in the book: clocks stopped.
    @State private var reading = false
    /// She looked at the book on the current question (counts as a hint), and the "counts as a hint" question.
    @State private var lookedAtBook = false
    @State private var confirmBook = false
    private var onHold: Bool { paused || browsing || reading }
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

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
                    let done = sessionAttempts.filter(\.isGraded).count
                    VStack(spacing: 16) {
                        Text("Checking your answers…").font(.title3)
                        ProgressView(value: Double(done), total: Double(max(sessionAttempts.count, 1)))
                            .frame(maxWidth: 400)
                        Text("\(done) of \(sessionAttempts.count) checked").monospacedDigit().foregroundStyle(.secondary)
                            .accessibilityIdentifier("checkedCount")
                    }
                case .answering:
                    if paused { pausedScreen }
                    else if browsing { PreviousQuestionsView(attempts: sessionAttempts) { resumeFromHold() } }
                    else if let q = current { questionScreen(q) } else { noQuestions }
                }
            }
            .navigationDestination(isPresented: $reading) {
                if let q = current, let chapter = q.chapter { ReadChapterView(chapter: chapter, focus: ChapterLink.base(q)) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .summary ? "Close" : "End") {
                        if phase == .summary || (sessionAttempts.isEmpty && !canvas.hasInk) { DraftStore.clear(draftKey); dismiss() } else { confirmQuit = true }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if phase != .summary {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text("Session \(formatClock(sessionClock.elapsed(now: ctx.date))) / 30:00" + (onHold ? " · paused" : ""))
                                .monospacedDigit().font(.headline)
                        }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if phase == .answering, current != nil {
                        if onHold {
                            Button { resumeFromHold() } label: { HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Resume") } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button { hold(browse: true) } label: { HStack(spacing: 6) { Image(systemName: "clock.arrow.circlepath"); Text("Previous") } }
                                .disabled(sessionAttempts.isEmpty)
                            Button { hold(browse: false) } label: { HStack(spacing: 6) { Image(systemName: "pause.fill"); Text("Pause") } }
                        }
                    }
                }
            }
            .alert("Look at the book?", isPresented: $confirmBook) {
                Button("Not now", role: .cancel) {}
                Button("Open the book") { lookedAtBook = true; reading = true }
            } message: {
                Text("Looking at the book counts as a hint: this answer won't change your mastery points, and a similar question comes back later.")
            }
            // A centered alert (not a popover): hard to miss, and "Keep practicing" is the safe default.
            .alert("End this session?", isPresented: $confirmQuit) {
                Button("Keep practicing", role: .cancel) {}
                Button("End session") { DraftStore.clear(draftKey); sessionAttempts.isEmpty ? dismiss() : finish() }
            } message: {
                let n = sessionAttempts.count
                let minutes = Int(sessionClock.elapsed() / 60)
                Text(n == 0 ? "Your work on this question won't be saved."
                     : "You've done \(n) question\(n == 1 ? "" : "s") in " + (minutes < 1 ? "under a minute" : "\(minutes) minute\(minutes == 1 ? "" : "s")") + ". Your answers will be checked and you'll see how you did.")
            }
        }
        .onAppear(perform: start)
        .onChange(of: reading) { _, now in
            if now { questionClock.pause(); sessionClock.pause() }
            else if !onHold { sessionClock.resume(); if phase == .answering { questionClock.resume() } }
        }
        .fullScreenCover(isPresented: $tutorOpen, onDismiss: { if !onHold { questionClock.resume() } }) {
            if let solutionAttempt { SolutionPage(attempt: solutionAttempt) }
        }
        .onReceive(ticker) { t in
            saveDraft()
            if phase == .finishing, let since = finishingSince, t.timeIntervalSince(since) > Self.finalWaitSeconds { showFinal() }
        }
        .onChange(of: grading.version) { _, _ in absorbGrades() }
        .onChange(of: scenePhase) { _, p in
            if p == .active {
                if !onHold {
                    sessionClock.resume()
                    if phase == .answering { questionClock.resume() }
                }
                GradingQueue.shared.resumePending(context: context)
            } else { questionClock.pause(); sessionClock.pause(); saveDraft() }
        }
    }

    // MARK: Screens

    private var noQuestions: some View {
        ContentUnavailableView("Nothing to practice", systemImage: "checkmark.seal",
                               description: Text("There are no questions in this scope yet."))
    }

    private func questionScreen(_ q: Question) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    chip(MathPlain.render(q.concept?.name ?? ""), Theme.classic.learn)
                    chip(["Basic", "Medium", "Hard"][max(0, min(2, q.difficulty - 1))], .secondary)
                    if q.isChallenge { chip("Challenge", Theme.classic.attention, icon: "flame.fill") }
                    if q.chapter != nil {
                        Button { if lookedAtBook { reading = true } else { confirmBook = true } } label: {
                            chip(ChapterLink.label(question: q, base: ChapterLink.base(q)), Theme.classic.accent, icon: "book.pages")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("practiceSeeInChapter")
                    }
                    if currentPick?.category == .reinforcement {
                        chip("Like an earlier one", Theme.classic.learn, icon: "arrow.triangle.2.circlepath")
                    }
                    Spacer()
                }
                QuestionPanel(question: q)
                helpPanel
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .background(Theme.classic.surface)
            .overlay(alignment: .bottom) { Divider() }
            .shadow(color: .black.opacity(0.04), radius: 6, y: 3)

            ZStack(alignment: .topTrailing) {
                WritingCanvas(controller: canvas, graphPaper: graphPaper)
                Toggle(isOn: $graphPaper) { Image(systemName: "squareshape.split.3x3") }
                    .toggleStyle(.button)
                    .padding(8)
            }
            .overlay(alignment: .top) { actionBar.padding(.top, 8) }
        }
    }

    private var pausedScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "pause.circle.fill").font(.system(size: 72)).foregroundStyle(.blue)
            Text("Taking a break").font(.largeTitle.bold())
            Text("The clock is stopped. Your work on this question is saved.").foregroundStyle(.secondary)
            Button { resumeFromHold() } label: { Label("Resume", systemImage: "play.fill").font(.title2.bold()) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hold(browse: Bool) {
        // The canvas leaves the screen; keep her ink so the next canvas starts with it.
        canvas.load(canvas.drawing)
        questionClock.pause()
        sessionClock.pause()
        if browse { browsing = true } else { paused = true }
    }

    private func resumeFromHold() {
        paused = false
        browsing = false
        sessionClock.resume()
        if help != .loadingHint && help != .loadingSolution { questionClock.resume() }
    }

    @ViewBuilder
    private var helpPanel: some View {
        switch help {
        case .none:
            if let helpError { Text(helpError).font(.callout).foregroundStyle(Theme.classic.notQuite) }
        case .loadingHint, .loadingSolution:
            HStack(spacing: 10) {
                ProgressView()
                Text(help == .loadingHint ? "Getting a hint…" : "Getting the solution…").foregroundStyle(.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.classic.attention.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .hint:
            VStack(alignment: .leading, spacing: 6) {
                if !hintText.isEmpty {
                    Label("Hint", systemImage: "lightbulb.fill").font(.headline).foregroundStyle(Theme.classic.attention)
                    MathText(markdown: hintText, fontSize: 18)
                }
                if let helpError { Text(helpError).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.classic.attention.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .solution:
            VStack(alignment: .leading, spacing: 6) {
                Label("Solution", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.classic.learn)
                MathText(markdown: solutionText, fontSize: 18, maxHeight: 380)
                HStack {
                    Text("Read it through, try writing it out yourself below, then tap Next. You'll get another one like this soon.")
                        .font(.callout).foregroundStyle(.secondary)
                    if solutionAttempt != nil {
                        Button { questionClock.pause(); tutorOpen = true } label: {
                            Label("Talk to the tutor", systemImage: "waveform.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func chip(_ text: String, _ color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    /// Sits at the top of the canvas so the PencilKit tool picker never covers it.
    private var actionBar: some View {
        HStack(spacing: 12) {
            switch help {
            case .none, .loadingHint:
                Button { getHint() } label: { Label("I'm stuck", systemImage: "lightbulb") }
                    .buttonStyle(.bordered).tint(Theme.classic.attention).disabled(help == .loadingHint)
            case .hint, .loadingSolution:
                Button { getSolution() } label: { Label("Show solution", systemImage: "eye") }
                    .buttonStyle(.bordered).disabled(help == .loadingSolution)
            case .solution:
                EmptyView()
            }
            Button { canvas.clear() } label: { Label("Clear", systemImage: "trash") }
                .buttonStyle(.bordered).tint(.secondary)
                .disabled(!canvas.hasInk)
            Button { next() } label: {
                Label("Next", systemImage: "arrow.right").font(.headline).padding(.horizontal, 8)
            }
                .buttonStyle(.borderedProminent)
                .disabled(help == .solution ? false : (!canvas.hasInk || help == .loadingHint || help == .loadingSolution))
        }
        .controlSize(.large)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    // MARK: Flow

    // MARK: Drafts (the current question's ink survives the app closing)

    private var draftKey: String { DraftStore.practiceKey(set.key) }

    /// Saves the ink on the current question (every few seconds and when the app goes to the background).
    private func saveDraft() {
        guard phase == .answering, help != .solution, let q = current else { return }
        guard canvas.hasInk || lookedAtBook else { DraftStore.clear(draftKey); return }
        var d = Draft(questionIDs: [q.id], ink: [q.id: canvas.drawing.dataRepresentation()], seconds: [q.id: questionClock.elapsed()])
        d.lookedAtBook = lookedAtBook
        DraftStore.save(d, key: draftKey)
    }

    /// The question she was writing on when the app closed, if it's recent and still unanswered.
    private func restorableDraft() -> (Question, Draft)? {
        guard let d = DraftStore.load(draftKey), Date().timeIntervalSince(d.savedAt) < DraftStore.practiceMaxAge,
              let id = d.questionIDs.first, let q = set.questions.first(where: { $0.id == id }),
              !q.attempts.contains(where: { $0.startedAt > d.savedAt.addingTimeInterval(-(d.seconds[id] ?? 0) - 5) })
        else { return nil }
        return (q, d)
    }

    private func start() {
        sessionClock.reset()
        GradingQueue.shared.resumePending(context: context)
        VariantGenerator.shared.refill(set, context: context)
        if startQuestionID == nil, let (q, d) = restorableDraft(), let cell = LearningStore.cellKey(q) {
            show(q, pick: Pick(questionID: q.id, cell: cell, category: .weak))
            if let data = d.ink[q.id], let drawing = try? PKDrawing(data: data) { canvas.load(drawing) }
            questionClock.reset(elapsed: d.seconds[q.id] ?? 0)
            lookedAtBook = d.lookedAtBook ?? false
        } else if let id = startQuestionID, let q = set.questions.first(where: { $0.id == id }) ?? set.chapters.lazy.flatMap(\.questions).first(where: { $0.id == id }),
           let cell = LearningStore.cellKey(q) {
            show(q, pick: Pick(questionID: q.id, cell: cell, category: .weak))
        } else {
            nextQuestion()
        }
    }

    private func show(_ q: Question, pick: Pick) {
        DraftStore.clear(draftKey)
        lookedAtBook = false
        canvas.clear()
        help = .none
        hintText = ""
        solutionText = ""
        solutionAttempt = nil
        helpError = nil
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
        // Top up generated questions between questions (never while she is writing), reusing this planner.
        VariantGenerator.shared.refill(set, planner: planner, context: context)
    }

    private func context(for q: Question) -> QuestionContext {
        QuestionContext(text: q.text, figureJPEG: q.figureData, conceptName: q.concept?.name ?? "", bookAnswer: q.answerKeyAnswer)
    }

    /// First "I'm stuck": wait for a hint, show it, and let her keep working on the same question.
    private func getHint() {
        guard let q = current else { return }
        help = .loadingHint
        helpError = nil
        questionClock.pause()
        let ctx = context(for: q)
        let work = canvas.hasInk ? ImageUtils.renderDrawing(canvas.drawing) : nil
        Task {
            do {
                let h = try await HelpProvider.hint(ctx, work)
                guard current?.id == q.id else { return }
                hintText = h
                help = .hint
            } catch {
                guard current?.id == q.id else { return }
                // Never a dead end: without a hint she can still ask for the solution.
                hintText = ""
                help = .hint
                helpError = "Sorry, a hint isn't available for this one right now. Keep trying, or tap Show solution."
            }
            if !onHold { questionClock.resume() }
        }
    }

    /// After a hint: the full solution. The question then counts as not solved, and a similar one comes back later.
    private func getSolution() {
        guard let q = current, let pick = currentPick else { return }
        help = .loadingSolution
        helpError = nil
        questionClock.pause()
        let ctx = context(for: q)
        Task {
            do {
                let r = try await HelpProvider.solution(ctx)
                guard current?.id == q.id else { return }
                let attempt = makeAttempt(q, pick: pick)
                attempt.wasStuck = true
                attempt.revealed = true
                GradingQueue.shared.record(attempt, r, context: context)
                solutionText = r.workedSolution
                solutionAttempt = attempt
                help = .solution
            } catch {
                guard current?.id == q.id else { return }
                help = .hint
                helpError = "Sorry, the solution isn't available right now. Check the internet connection and try again."
            }
            if !onHold { questionClock.resume() }
        }
    }

    private func next() {
        if help == .solution { advance() } else { submit() }
    }

    /// Creates and saves an attempt for the current question with her ink so far.
    private func makeAttempt(_ q: Question, pick: Pick) -> Attempt {
        let attempt = Attempt(mode: .practice, startedAt: Date().addingTimeInterval(-questionClock.elapsed()))
        attempt.activeSeconds = questionClock.elapsed()
        let drawing = canvas.drawing
        attempt.inkData = drawing.dataRepresentation()
        attempt.renderedImage = ImageUtils.renderDrawing(drawing)
        attempt.hintText = hintText
        attempt.lookedAtBook = lookedAtBook
        attempt.question = q
        context.insert(attempt)
        try? context.save()
        sessionAttempts.append(attempt)
        cellOfAttempt[attempt.id] = pick.cell
        Planner.asked(q.id, in: &session)
        return attempt
    }

    private func submit() {
        guard let q = current, let pick = currentPick else { return }
        questionClock.pause()
        let attempt = makeAttempt(q, pick: pick)
        GradingQueue.shared.enqueue(attempt, context: context)
        advance()
    }

    /// Decides what comes after a question: an interruption, a check-in, the end, or the next question.
    private func advance() {
        let unrevealed = sessionAttempts.filter { $0.isGraded && !$0.revealed }
        if let (earlier, latest) = repeatedMistake() {
            present([earlier, latest], kind: .repeated)
        } else if let c = unrevealed.first(where: { $0.effectiveVerdict == .incorrect && $0.mistakeType == .conceptual }) {
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

    /// The same kind of mistake twice on one skill this session, the newer one not yet shown.
    private func repeatedMistake() -> (Attempt, Attempt)? {
        let graded = sessionAttempts.filter(\.isGraded)
        let answers = graded.enumerated().map { i, a in
            RepeatedMistake.Answer(index: i, skill: a.question?.concept?.id, mistake: a.mistakeType,
                                   wrong: a.effectiveVerdict == .incorrect, revealed: a.revealed)
        }
        guard let r = RepeatedMistake.find(answers) else { return nil }
        return (graded[r.earlier], graded[r.latest])
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
        DraftStore.clear(draftKey)
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
                // A hinted answer still gets a similar question later.
                Planner.graded(cell: cell, correct: a.effectiveVerdict != .incorrect && !a.usedHint, in: &session)
            }
        }
        if phase == .finishing, sessionAttempts.allSatisfy(\.isGraded) { showFinal() }
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
                    Text(m.displayName).font(.subheadline.weight(.medium)).foregroundStyle(Theme.classic.notQuite)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.classic.notQuite.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(formatClock(attempt.activeSeconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            QuestionPanel(question: question, label: "Question")
            if attempt.lookedAtBook {
                Label("You looked at the book for this one, so it counts like a hint.", systemImage: "book.pages")
                    .font(.subheadline).foregroundStyle(Theme.classic.attention)
            }
            if !attempt.hintText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Hint you used", systemImage: "lightbulb.fill").font(.subheadline.bold()).foregroundStyle(Theme.classic.attention)
                    MathText(markdown: attempt.hintText, fontSize: 16)
                }
            }
            if showWork, !attempt.wasStuck, let data = attempt.renderedImage, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 260)
                    .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if attempt.effectiveVerdict == .incorrect, !attempt.errorStep.isEmpty, !attempt.wasStuck {
                MathText(markdown: "**Where it went wrong:** \(attempt.errorStep)", fontSize: 17)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.classic.notQuite.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !attempt.feedback.isEmpty, !attempt.wasStuck { MathText(markdown: attempt.feedback, fontSize: 17) }
            if attempt.effectiveVerdict == .incorrect, !attempt.workedSolution.isEmpty {
                if attempt.wasStuck {
                    MathText(markdown: attempt.workedSolution, fontSize: 17)
                    Button { showSolution = true } label: { Label("Talk to the tutor about it", systemImage: "waveform.circle") }
                } else {
                    Button { showSolution = true } label: { Label("Show solution", systemImage: "doc.text.magnifyingglass") }
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
        .fullScreenCover(isPresented: $showSolution) { SolutionPage(attempt: attempt) }
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
                SkillBarsGrid(set: set).frame(maxWidth: 820)
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

/// Earlier questions from this session (newest first): the full question, her work, and the result once it has
/// been shown at a check-in. Read-only; the clock is stopped while she looks.
struct PreviousQuestionsView: View {
    let attempts: [Attempt]
    let onResume: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Earlier questions").font(.largeTitle.bold())
                Text("The clock is stopped while you look back.").foregroundStyle(.secondary)
                ForEach(Array(attempts.enumerated().reversed()), id: \.element.id) { i, a in
                    if let q = a.question {
                        if a.isGraded && a.revealed {
                            FeedbackCard(attempt: a, question: q)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                QuestionPanel(question: q, label: "Question \(i + 1)")
                                if let data = a.renderedImage, let img = UIImage(data: data) {
                                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 260)
                                        .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                if !a.hintText.isEmpty {
                                    Label("You used a hint", systemImage: "lightbulb.fill").font(.subheadline).foregroundStyle(.orange)
                                }
                                if a.lookedAtBook {
                                    Label("You looked at the book", systemImage: "book.pages").font(.subheadline).foregroundStyle(.orange)
                                }
                                Label(a.isGraded ? "Checked. You'll see how you did at the next check-in."
                                                 : "Being checked. You'll see how you did at the next check-in.",
                                      systemImage: "hourglass").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(20)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(action: onResume) { Label("Resume", systemImage: "play.fill").font(.title3.bold()) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
}
