import SwiftUI
import SwiftData

/// One answer: your work, Claude's grading, and a way to correct the grade.
struct AttemptReviewView: View {
    @Bindable var attempt: Attempt
    @Environment(\.modelContext) private var context
    @State private var mistake: MistakeType = .procedural

    var body: some View {
        Form {
            if let q = attempt.question {
                Section("Question") {
                    MathText(markdown: q.text, fontSize: 18)
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
                LabeledContent("Mode", value: attempt.mode == .exam ? "Exam" : "Practice")
            }
            Section("Claude's grading") {
                HStack { VerdictBadge(verdict: attempt.verdict); Text(attempt.verdict.rawValue.capitalized) }
                if !attempt.transcribedAnswer.isEmpty { LabeledContent("Claude read your answer as", value: attempt.transcribedAnswer) }
                if !attempt.ownAnswer.isEmpty { LabeledContent("Claude's own answer", value: attempt.ownAnswer) }
                if let m = attempt.mistakeType { LabeledContent("Mistake type", value: m.displayName) }
                if !attempt.errorStep.isEmpty { MathText(markdown: "**Where it went wrong:** \(attempt.errorStep)", fontSize: 16) }
                if !attempt.feedback.isEmpty { MathText(markdown: attempt.feedback, fontSize: 16) }
                LabeledContent("Confidence", value: String(format: "%.0f%%", attempt.graderConfidence * 100))
                if !attempt.workedSolution.isEmpty {
                    DisclosureGroup("Solution") { MathText(markdown: attempt.workedSolution, fontSize: 16) }
                }
            }
            Section {
                if let override = attempt.correction {
                    HStack { Text("You changed the grade to:"); VerdictBadge(verdict: override); Text(override.rawValue.capitalized) }
                    Button("Undo my change") { setCorrection(nil) }
                }
                Button("My answer was actually correct") { setCorrection(.correct) }
                Picker("Mistake type", selection: $mistake) {
                    ForEach(MistakeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Button("My answer was actually wrong") { setCorrection(.incorrect) }
            } header: {
                Text("Disagree with the grade?")
            } footer: {
                Text("Changing a grade updates your progress for this chapter. Be honest — the app uses it to decide what you practice next.")
            }
            Section { ReportProblemButton(subject: .attempt(attempt)) }
        }
        .navigationTitle("Answer")
        .onAppear { if let m = attempt.mistakeType { mistake = m } }
    }

    private func setCorrection(_ verdict: Verdict?) {
        attempt.correction = verdict
        if verdict == .incorrect { attempt.mistakeType = mistake }
        if verdict == .correct { attempt.mistakeType = nil }
        if let chapter = attempt.question?.chapter { LearningStore.rebuild(chapter, context: context) }
    }
}
