import SwiftUI
import SwiftData

/// Your answers in a chapter or study plan: ones to check, ones still being checked, and recent ones.
struct MyAnswersView: View {
    let set: StudySet
    @ObservedObject private var grading = GradingQueue.shared

    var body: some View {
        let _ = grading.version
        let all = set.allAttempts.sorted { $0.startedAt > $1.startedAt }
        let toCheck = all.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }
        let pending = all.filter { !$0.isGraded }
        let recent = Array(all.filter(\.isGraded).prefix(60))
        List {
            if !toCheck.isEmpty {
                Section {
                    ForEach(toCheck) { a in NavigationLink { AttemptReviewView(attempt: a) } label: { row(a) } }
                } header: {
                    Text("To check (\(toCheck.count))")
                } footer: {
                    Text("Claude wasn't sure how to grade these. Open one and decide whether your answer was right.")
                }
            }
            if !pending.isEmpty {
                Section("Still being checked (\(pending.count))") {
                    ForEach(pending) { a in row(a) }
                }
            }
            Section("Recent answers") {
                if recent.isEmpty { Text("No answers yet.").foregroundStyle(.secondary) }
                ForEach(recent) { a in NavigationLink { AttemptReviewView(attempt: a) } label: { row(a) } }
            }
        }
        .navigationTitle("My answers")
    }

    private func row(_ a: Attempt) -> some View {
        HStack(spacing: 14) {
            if a.isGraded { VerdictBadge(verdict: a.effectiveVerdict).font(.title2) } else { ProgressView() }
            VStack(alignment: .leading, spacing: 3) {
                Text(MathText.plainPreview(a.question?.text ?? "")).lineLimit(2)
                Text(a.startedAt.formatted(date: .abbreviated, time: .shortened) + " · \(Int(a.activeSeconds))s"
                     + (a.mistakeType.map { " · \($0.displayName)" } ?? "")
                     + (a.gradingError != nil && !a.isGraded ? " · waiting to retry" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct VerdictBadge: View {
    let verdict: Verdict
    var body: some View {
        switch verdict {
        case .correct: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.classic.done)
        case .incorrect: Image(systemName: "arrow.uturn.left.circle.fill").foregroundStyle(Theme.classic.notQuite)
        case .needsReview: Image(systemName: "questionmark.circle.fill").foregroundStyle(Theme.classic.attention)
        }
    }
}
