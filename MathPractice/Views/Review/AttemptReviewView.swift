import SwiftUI
import SwiftData

/// One answer: your work, Claude's grading, and a way to correct the grade.
struct AttemptReviewView: View {
    @Bindable var attempt: Attempt
    @Environment(\.modelContext) private var context
    @State private var mistake: MistakeType = .procedural
    @State private var showSolution = false
    @ObservedObject private var grading = GradingQueue.shared

    var body: some View {
        Form {
            if let q = attempt.question {
                Section("Question") {
                    MathText(markdown: q.text, fontSize: 18)
                    ChapterLink(question: q)
                    if let fig = q.figureData, let img = UIImage(data: fig) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220)
                    }
                }
            }
            Section("Your work") {
                if let data = attempt.renderedImage, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 500)
                } else {
                    Text("No work recorded").foregroundStyle(.secondary)
                }
                LabeledContent("Time", value: "\(Int(attempt.activeSeconds)) s")
                LabeledContent("Mode", value: attempt.mode == .exam ? "Exam" : attempt.mode == .lesson ? "Lesson" : "Practice")
            }
            let _ = grading.version
            if !attempt.isGraded {
                Section("Claude's grading") {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking your answer again…")
                    }
                    if let e = attempt.gradingError {
                        Text(e.contains("API key") ? "Couldn't check it: \(e)" : "Couldn't check it yet (\(e)). It will try again by itself.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
            Section("Claude's grading") {
                HStack { VerdictBadge(verdict: attempt.verdict); Text(attempt.verdict.label) }
                if !attempt.transcribedAnswer.isEmpty { MathRow(label: "Claude read your answer as", value: attempt.transcribedAnswer) }
                if !attempt.ownAnswer.isEmpty { MathRow(label: "Claude's own answer", value: attempt.ownAnswer) }
                if attempt.verdict == .incorrect, let m = attempt.mistakeType { LabeledContent("Mistake type", value: m.displayName) }
                if !attempt.errorStep.isEmpty { MathText(markdown: "**Where it went wrong:** \(attempt.errorStep)", fontSize: 16) }
                if !attempt.feedback.isEmpty { MathText(markdown: attempt.feedback, fontSize: 16) }
                LabeledContent("Confidence", value: String(format: "%.0f%%", attempt.graderConfidence * 100))
                if !attempt.workedSolution.isEmpty {
                    Button { showSolution = true } label: { Label("Show solution", systemImage: "doc.text.magnifyingglass") }
                }
                if attempt.verdict == .needsReview && attempt.correction == nil {
                    Button { grading.regrade(attempt, context: context) } label: { Label("Grade it again", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("regrade")
                }
            }
            }
            if !attempt.tutorTurns.isEmpty {
                Section("Your talks with the tutor") {
                    ForEach(attempt.tutorTurns.sorted { $0.createdAt < $1.createdAt }) { t in TutorTurnRow(turn: t) }
                }
            }
            Section {
                if let override = attempt.correction {
                    HStack { Text("You changed the grade to:"); VerdictBadge(verdict: override); Text(override.label) }
                    Button("Undo my change") { setCorrection(nil) }
                }
                // Offer only the other grade: a right answer can be marked wrong (with its kind of mistake), a wrong one right.
                let current = attempt.effectiveVerdict
                if current != .correct {
                    Button("My answer was actually correct") { setCorrection(.correct) }
                }
                if current != .incorrect {
                    Picker("Kind of mistake", selection: $mistake) {
                        ForEach(MistakeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Button("My answer was actually wrong") { setCorrection(.incorrect) }
                }
            } header: {
                Text("Disagree with the grade?")
            } footer: {
                Text("Changing a grade updates your progress for this chapter. Be honest — the app uses it to decide what you practice next.")
            }
            Section { ReportProblemButton(subject: .attempt(attempt)) }
        }
        .navigationTitle("Answer")
        .fullScreenCover(isPresented: $showSolution) {
            SolutionPage(attempt: attempt)
        }
        .onAppear { if let m = attempt.mistakeType { mistake = m } }
    }

    private func setCorrection(_ verdict: Verdict?) {
        attempt.correction = verdict
        if verdict == .incorrect { attempt.mistakeType = mistake }
        if verdict == .correct { attempt.mistakeType = nil }
        if let chapter = attempt.question?.chapter { LearningStore.rebuild(chapter, context: context) }
    }
}

/// One saved turn of a tutor conversation: what she said (with her page), or what the tutor said and wrote.
struct TutorTurnRow: View {
    let turn: TutorTurn
    @State private var zoom = false

    var body: some View {
        if turn.fromStudent {
            HStack(alignment: .top, spacing: 12) {
                Label("You", systemImage: "person.fill").font(.subheadline.bold()).foregroundStyle(.green).frame(width: 80, alignment: .leading)
                Text(turn.text)
                Spacer()
                if let d = turn.snapshot, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { zoom = true }
                        .sheet(isPresented: $zoom) { Image(uiImage: img).resizable().scaledToFit().padding() }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Label("Tutor", systemImage: "graduationcap.fill").font(.subheadline.bold()).foregroundStyle(Theme.classic.board).frame(width: 80, alignment: .leading)
                let beats = turn.text.components(separatedBy: "\n").compactMap(TutorScriptParser.beat)
                let md = beats.compactMap { b -> String? in
                    switch b {
                    case let .say(s): return s
                    case let .write(w): return "> " + w
                    case .point, .resume: return nil
                    }
                }.joined(separator: "\n\n")
                MathText(markdown: md, fontSize: 16)
            }
        }
    }
}

/// A label above a value written as Markdown with $...$ LaTeX (Claude's answers, the book's answer key).
struct MathRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).foregroundStyle(.secondary).font(.subheadline)
            MathText(markdown: value, fontSize: 18)
        }
    }
}

extension Verdict {
    var label: String {
        switch self {
        case .correct: return "Correct"
        case .incorrect: return "Not quite"
        case .needsReview: return "Not sure — to check"
        }
    }
}
