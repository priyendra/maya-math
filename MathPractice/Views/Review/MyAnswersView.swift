import SwiftUI
import SwiftData

/// Your answers in a chapter or study plan: what needs you first (to check, still being checked), then every
/// answer, filterable by skill, level and mistake type.
struct MyAnswersView: View {
    let set: StudySet

    var body: some View {
        AnswersBrowser(set: set, showInbox: true, filter: AnswerFilter()) { EmptyView() }
            .navigationTitle("My answers")
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
