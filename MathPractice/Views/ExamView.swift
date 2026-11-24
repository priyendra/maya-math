import SwiftUI
import SwiftData
import PencilKit

/// Timed mixed test across a study set. No feedback until the end.
struct ExamView: View {
    let set: StudySet
    @ObservedObject private var grading = GradingQueue.shared
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Phase { case intro, running, grading, results }

    @State private var phase: Phase = .intro
    @State private var exam: ExamSession?
    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var drawings: [UUID: PKDrawing] = [:]
    @State private var perQuestionSeconds: [UUID: TimeInterval] = [:]
    @State private var clock = ActiveClock()
    @State private var questionClock = ActiveClock()
    @State private var attempts: [Attempt] = []
    @State private var gradedCount = 0
    @State private var now = Date()
    @State private var confirmSubmit = false
    @State private var timedOut = false
    @State private var graphPaper = false
    @StateObject private var canvas = CanvasController()
    @AppStorage("examDifficulty") private var difficultyRaw = 0
    @AppStorage("examPace") private var paceRaw = 0
    @AppStorage("examLength") private var lengthIndex = 1
    /// The exam the intro shows (re-picked when a setting changes) and the time allowed per question.
    @State private var planned: [Question] = []
    @State private var allowed: [UUID: Double] = [:]
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var difficulty: ExamDifficulty { ExamDifficulty(rawValue: difficultyRaw) ?? .mixed }
    private var pace: ExamPace { ExamPace(rawValue: paceRaw) ?? .own }
    private var length: ExamLength { ExamLength.allCases[min(max(lengthIndex, 0), ExamLength.allCases.count - 1)] }
    /// The time limit she chose (DEBUG: -examSeconds N for UI tests).
    private var plannedLimit: TimeInterval {
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-examSeconds"),
           i + 1 < ProcessInfo.processInfo.arguments.count, let s = Double(ProcessInfo.processInfo.arguments[i + 1]) { return s }
        #endif
        return TimeInterval(length.rawValue * 60)
    }
    private var timeLimit: TimeInterval { TimeInterval(exam?.timeLimitSeconds ?? Int(plannedLimit)) }
    /// Strict wall-clock time: it keeps running if she leaves the app, as on a real test.
    private var elapsed: TimeInterval { exam.map { now.timeIntervalSince($0.startedAt) } ?? 0 }
    private var remaining: TimeInterval { timeLimit - elapsed }
    /// The last 5 minutes: the clock turns red.
    private var finalMinutes: Bool { remaining <= 5 * 60 }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro: intro
                case .running: running
                case .grading:
                    VStack(spacing: 16) {
                        if timedOut {
                            Label("Time's up — your exam was handed in.", systemImage: "timer")
                                .font(.title2.bold()).foregroundStyle(Theme.classic.notQuite)
                                .accessibilityIdentifier("timesUp")
                        }
                        ProgressView(value: Double(gradedCount), total: Double(max(attempts.count, 1)))
                            .frame(maxWidth: 400)
                        Text("Grading your exam… \(gradedCount)/\(attempts.count)")
                    }
                case .results:
                    ExamResultsView(attempts: attempts, timeLimit: timeLimit,
                                    timeUsed: min(clock.elapsed(), timeLimit), targets: allowed, pace: pace, timedOut: timedOut) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase == .intro || phase == .results { Button("Close") { dismiss() } }
                }
            }
        }
        .onReceive(ticker) { t in
            now = t
            if phase == .running && Int(t.timeIntervalSince1970) % 5 == 0 { saveDraft() }
            if phase == .running && remaining <= 0 { timedOut = true; submitAll() }
        }
        .onChange(of: grading.version) { _, _ in
            guard phase == .grading else { return }
            gradedCount = attempts.filter(\.isGraded).count
            if gradedCount == attempts.count { phase = .results }
        }
        .onChange(of: scenePhase) { _, p in
            // The exam clock never pauses (strict); time on the current question does.
            if p == .active {
                now = Date()
                questionClock.resume()
                if phase == .running && remaining <= 0 { timedOut = true; submitAll() }
            } else { questionClock.pause(); saveDraft() }
        }
        .alert("Hand in your exam?", isPresented: $confirmSubmit) {
            Button("Keep working", role: .cancel) {}
            Button("Hand in") { submitAll() }
        } message: {
            let blank = questions.filter { (drawings[$0.id]?.strokes.isEmpty ?? true) }.count
            Text((blank > 0 ? "\(blank) question\(blank == 1 ? " is" : "s are") still blank. " : "All questions have an answer. ")
                 + "You have \(formatClock(remaining)) left.")
        }
    }

    private var intro: some View {
        VStack(spacing: 22) {
            Image(systemName: "timer").font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 96, height: 96).background(Theme.classic.accent2.gradient, in: Circle())
            Text("Exam mode").font(.largeTitle.bold())
            Text("Questions from \(MathPlain.render(set.title)), like the real test.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            StepSlider(title: "How hard", icon: "chart.bar.fill", value: $difficultyRaw,
                       names: ExamDifficulty.allCases.map(\.name), detail: difficulty.detail)
                .accessibilityIdentifier("examDifficulty")
            StepSlider(title: "How fast", icon: "hare.fill", value: $paceRaw,
                       names: ExamPace.allCases.map(\.name), detail: pace.detail)
                .accessibilityIdentifier("examPace")
            StepSlider(title: "How long", icon: "clock.fill", value: $lengthIndex,
                       names: ExamLength.allCases.map(\.name), detail: "\(planned.count) questions in \(length.rawValue) minutes")
                .accessibilityIdentifier("examLength")
            Button { begin() } label: { Text("Start exam").font(.headline).padding(.horizontal, 24) }
                .buttonStyle(.borderedProminent).tint(Theme.classic.accent2).controlSize(.large)
                .disabled(planned.isEmpty)
            NavigationLink { ExamHistoryView(set: set) } label: {
                let n = ExamHistoryView.exams(set).count
                Label(n == 0 ? "My exams" : "My exams (\(n))", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("myExams")
        }
        .onAppear { if !resumeUnfinished() { plan() } }
        .onChange(of: difficultyRaw) { _, _ in plan() }
        .onChange(of: paceRaw) { _, _ in plan() }
        .onChange(of: lengthIndex) { _, _ in plan() }
        .padding(40)
        .frame(maxWidth: 620)
        .background(Theme.classic.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.classic.background.ignoresSafeArea())
    }

    private func examFact(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var running: some View {
        VStack(spacing: 0) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(questions.indices, id: \.self) { i in
                            let answered = !(drawings[questions[i].id]?.strokes.isEmpty ?? true)
                            Button("\(i + 1)") { go(to: i) }
                                .frame(width: 36, height: 36)
                                .background(i == index ? Theme.classic.accent2 : (answered ? Theme.classic.accent2.opacity(0.25) : Color.secondary.opacity(0.12)),
                                            in: Circle())
                                .foregroundStyle(i == index ? .white : .primary)
                        }
                    }
                }
                Spacer()
                Label(formatClock(remaining), systemImage: "timer")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(finalMinutes ? Color.white : Color.primary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(finalMinutes ? Color.red : Color.secondary.opacity(0.12), in: Capsule())
                    .animation(.easeInOut, value: finalMinutes)
                    .accessibilityIdentifier("examClock")
                Button("Hand in") { if questions.indices.contains(index) { drawings[questions[index].id] = canvas.drawing }; confirmSubmit = true }.buttonStyle(.borderedProminent).tint(Theme.classic.accent2)
            }
            .padding()
            if questions.indices.contains(index) {
                let q = questions[index]
                QuestionPanel(question: q, label: "Question \(index + 1) of \(questions.count)")
                    .padding(.horizontal).padding(.bottom)
                ZStack(alignment: .topTrailing) {
                    WritingCanvas(controller: canvas, graphPaper: graphPaper)
                    Toggle(isOn: $graphPaper) { Image(systemName: "squareshape.split.3x3") }.toggleStyle(.button).padding(8)
                }
                .overlay(alignment: .top) {
                    HStack {
                        Button { go(to: index - 1) } label: { Label("Previous", systemImage: "chevron.left") }.disabled(index == 0)
                        Spacer()
                        Button { go(to: index + 1) } label: { Label("Next", systemImage: "chevron.right") }.disabled(index == questions.count - 1)
                    }
                    .buttonStyle(.bordered)
                    .padding(.leading, 16).padding(.trailing, 64).padding(.top, 8)
                }
            }
        }
    }

    /// Picks the exam for the current settings. Time allowed per question = her own time ÷ the pace factor (Normal 1,
    /// Fast 1.25, Fastest 1.5); as many questions as fit in the chosen length at that pace.
    private func plan() {
        let byID = Dictionary(uniqueKeysWithValues: set.questions.map { ($0.id, $0) })
        var own: [UUID: Double] = [:]
        for q in set.questions { own[q.id] = set.baselineSeconds(q) }
        let infos = set.questions.compactMap(LearningStore.questionInfo)
        let factor = pace.factor
        let ids = ExamBuilder.build(questions: infos, minutes: length.rawValue, difficulty: difficulty,
                                    baseline: { (own[$0.id] ?? $0.estimatedSeconds) / factor })
        planned = ids.compactMap { byID[$0] }
        allowed = own.mapValues { $0 / pace.factor }
    }

    private func begin() {
        if planned.isEmpty { plan() }
        questions = planned
        let ids = questions.map(\.id)
        guard !questions.isEmpty else { dismiss(); return }
        let session = ExamSession(questionIDs: ids, timeLimitSeconds: Int(plannedLimit))
        session.difficultyRaw = difficultyRaw
        session.paceRaw = paceRaw
        session.allowedSeconds = ids.map { allowed[$0] ?? 0 }
        session.chapter = set.chapters.first
        session.startedAt = Date()
        context.insert(session)
        try? context.save()   // so a running exam is found again if the app closes
        exam = session
        now = Date()
        timedOut = false
        clock.reset()
        questionClock.reset()
        canvas.clear()
        index = 0
        phase = .running
    }

    private func go(to i: Int) {
        guard questions.indices.contains(i) else { return }
        let id = questions[index].id
        drawings[id] = canvas.drawing
        canvas.load(drawings[questions[i].id] ?? PKDrawing())
        perQuestionSeconds[id, default: 0] += questionClock.elapsed()
        questionClock.reset()
        index = i
        saveDraft()
    }

    // MARK: Drafts (every answer survives the app closing; the clock keeps running)

    /// Saves all answers so far: when she moves between questions, every few seconds, and when the app goes away.
    private func saveDraft() {
        guard phase == .running, let exam, questions.indices.contains(index) else { return }
        var ink = drawings.mapValues { $0.dataRepresentation() }
        let cur = questions[index].id
        ink[cur] = canvas.drawing.dataRepresentation()
        var seconds = perQuestionSeconds
        seconds[cur, default: 0] += questionClock.elapsed()
        DraftStore.save(Draft(questionIDs: questions.map(\.id), ink: ink, seconds: seconds, index: index),
                        key: DraftStore.examKey(exam.id))
    }

    /// An exam that was running when the app closed: carry on where she was (time kept running meanwhile), or, if
    /// time ran out, hand in what she had written.
    private func resumeUnfinished() -> Bool {
        let ids = Set(set.questions.map(\.id))
        guard let session = set.chapters.flatMap(\.exams)
            .filter({ $0.finishedAt == nil && $0.questionIDs.filter(ids.contains).count * 2 >= max($0.questionIDs.count, 1) })
            .max(by: { $0.startedAt < $1.startedAt }) else { return false }
        let draft = DraftStore.load(DraftStore.examKey(session.id))
        let byID = Dictionary(set.chapters.flatMap(\.questions).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let qs = session.questionIDs.compactMap { byID[$0] }
        // Nothing saved (an exam from before drafts existed): drop it rather than hand in blank answers.
        guard let draft, !qs.isEmpty else { context.delete(session); try? context.save(); return false }
        exam = session
        questions = qs
        allowed = Dictionary(zip(session.questionIDs, session.allowedSeconds), uniquingKeysWith: { a, _ in a })
        paceRaw = session.paceRaw
        drawings = draft.ink.compactMapValues { try? PKDrawing(data: $0) }
        perQuestionSeconds = draft.seconds
        index = min(max(draft.index, 0), qs.count - 1)
        canvas.load(drawings[qs[index].id] ?? PKDrawing())
        questionClock.reset()
        now = Date()
        phase = .running
        if remaining <= 0 { timedOut = true; submitAll() }
        return true
    }

    private func submitAll() {
        guard phase == .running, let exam else { return }
        confirmSubmit = false
        go(to: index) // bank time on the current question
        DraftStore.clear(DraftStore.examKey(exam.id))
        clock.pause()
        exam.finishedAt = min(Date(), exam.startedAt.addingTimeInterval(timeLimit))
        let start = exam.startedAt
        attempts = questions.map { q in
            let a = Attempt(mode: .exam, startedAt: start)
            let d = drawings[q.id] ?? PKDrawing()
            a.activeSeconds = perQuestionSeconds[q.id] ?? 0
            a.inkData = d.dataRepresentation()
            a.renderedImage = ImageUtils.renderDrawing(d)
            a.examSessionID = exam.id
            a.question = q
            context.insert(a)
            return a
        }
        try? context.save()
        phase = .grading
        gradedCount = 0

        for a in attempts { GradingQueue.shared.enqueue(a, context: context) }
        if attempts.allSatisfy(\.isGraded) { phase = .results }
    }
}

struct ExamResultsView: View {

    let attempts: [Attempt]
    let timeLimit: TimeInterval
    let timeUsed: TimeInterval
    let targets: [UUID: Double]
    var pace: ExamPace = .own
    var showDone = true
    var timedOut = false
    let onDone: () -> Void
    @State private var selected: Attempt?

    var body: some View {
        let stats = SessionStats(attempts: attempts)
        List {
            Section {
                if timedOut {
                    Label("Time's up — your exam was handed in.", systemImage: "timer")
                        .font(.headline).foregroundStyle(Theme.classic.notQuite)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("timesUp")
                }
                HStack(spacing: 40) {
                    VStack { Text("\(stats.correct)/\(stats.total)").font(.largeTitle.bold()); Text("correct") }
                    VStack { Text("\(Int(stats.accuracy * 100))%").font(.largeTitle.bold()); Text("score") }
                    VStack { Text(formatClock(timeUsed)).font(.largeTitle.bold().monospacedDigit()); Text("of \(formatClock(timeLimit))") }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            Section("Question by question") {
                ForEach(Array(attempts.enumerated()), id: \.element.id) { i, a in
                    Button { selected = a } label: {
                        HStack {
                            Text("\(i + 1)").font(.headline).frame(width: 30)
                            VerdictBadge(verdict: a.effectiveVerdict)
                            Text(MathText.plainPreview(a.question?.text ?? "")).lineLimit(1)
                            Spacer()
                            if let target = a.question.flatMap({ targets[$0.id] }) {
                                Text("\(formatClock(a.activeSeconds)) / \(formatClock(target))")
                                    .monospacedDigit()
                                    .foregroundStyle(a.activeSeconds > target * 1.25 ? .orange : .secondary)
                            } else {
                                Text(formatClock(a.activeSeconds)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                if showDone { Button("Done", action: onDone).frame(maxWidth: .infinity) }
            } footer: {
                Text("Your time on each question vs. the time allowed (\(pace.name) pace). Orange = much slower.")
            }
        }
        .sheet(item: $selected) { a in
            if let q = a.question {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        QuestionPanel(question: q)
                        if let data = a.renderedImage, let img = UIImage(data: data) {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 360)
                        }
                        FeedbackCard(attempt: a, question: q, showWork: false)
                    }
                    .padding()
                }
            }
        }
    }
}

/// A slider with a few named stops (exam settings).
struct StepSlider: View {
    let title: String
    let icon: String
    @Binding var value: Int
    let names: [String]
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                Text(names[min(max(value, 0), names.count - 1)]).font(.headline).foregroundStyle(Theme.classic.accent2)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: 0...Double(names.count - 1), step: 1)
                .tint(Theme.classic.accent2)
                .accessibilityValue(names[min(max(value, 0), names.count - 1)])
            HStack {
                ForEach(names.indices, id: \.self) { i in
                    Button { value = i } label: {
                        Text(names[i]).font(.caption.weight(i == value ? .bold : .regular))
                            .foregroundStyle(i == value ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    if i < names.count - 1 { Spacer() }
                }
            }
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
