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
    @State private var graphPaper = false
    @StateObject private var canvas = CanvasController()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timeLimit: TimeInterval { TimeInterval(set.examMinutes * 60) }
    private var remaining: TimeInterval { timeLimit - clock.elapsed(now: now) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro: intro
                case .running: running
                case .grading:
                    VStack(spacing: 16) {
                        ProgressView(value: Double(gradedCount), total: Double(max(attempts.count, 1)))
                            .frame(maxWidth: 400)
                        Text("Grading your exam… \(gradedCount)/\(attempts.count)")
                    }
                case .results:
                    ExamResultsView(attempts: attempts, timeLimit: timeLimit,
                                    timeUsed: clock.elapsed(), targets: targets) { dismiss() }
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
            if phase == .running && remaining <= 0 { submitAll() }
        }
        .onChange(of: grading.version) { _, _ in
            guard phase == .grading else { return }
            gradedCount = attempts.filter(\.isGraded).count
            if gradedCount == attempts.count { phase = .results }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { clock.resume(); questionClock.resume() } else { clock.pause(); questionClock.pause() }
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
            Text("A mix of questions from \(MathPlain.render(set.title)), like the real test.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                examFact("clock", "\(set.examMinutes) minutes")
                examFact("list.number", "\(min(set.questions.count, 20)) questions")
                examFact("chart.bar", "Results at the end")
            }
            Button { begin() } label: { Text("Start exam").font(.headline).padding(.horizontal, 24) }
                .buttonStyle(.borderedProminent).tint(Theme.classic.accent2).controlSize(.large)
        }
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
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(remaining < 120 ? Theme.classic.notQuite : .primary)
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

    private var targets: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.id, LearningStore.targetSeconds(for: $0)) })
    }

    private func begin() {
        let infos = set.questions.compactMap(LearningStore.questionInfo)
        let ids = ExamBuilder.build(questions: infos, minutes: set.examMinutes)
        questions = ids.compactMap { id in set.questions.first { $0.id == id } }
        guard !questions.isEmpty else { dismiss(); return }
        let session = ExamSession(questionIDs: ids, timeLimitSeconds: set.examMinutes * 60)
        session.chapter = set.chapters.first
        context.insert(session)
        exam = session
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
    }

    private func submitAll() {
        guard phase == .running, let exam else { return }
        go(to: index) // bank time on the current question
        clock.pause()
        exam.finishedAt = Date()
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
    let onDone: () -> Void
    @State private var selected: Attempt?

    var body: some View {
        let stats = SessionStats(attempts: attempts)
        List {
            Section {
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
                            let target = a.question.flatMap { targets[$0.id] } ?? 0
                            Text("\(formatClock(a.activeSeconds)) / \(formatClock(target))")
                                .monospacedDigit()
                                .foregroundStyle(a.activeSeconds > target * 1.25 ? .orange : .secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                Button("Done", action: onDone).frame(maxWidth: .infinity)
            } footer: {
                Text("Times show how long you spent vs. your goal time. Orange = much slower than goal.")
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
