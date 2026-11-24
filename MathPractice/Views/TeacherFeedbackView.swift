import SwiftUI

/// "Teacher's feedback" on the chapter page: Claude's notes on her answers, rewritten every 30 minutes of practice.
/// Shows nothing until there are enough answers to say something useful.
struct TeacherFeedbackCard: View {
    let set: StudySet
    let holder: FeedbackHolder
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @ObservedObject private var writer = TeacherFeedback.shared

    var body: some View {
        let seconds = TeacherFeedback.practiceSeconds(set)
        let writing = writer.writing.contains(holder.id)
        if TeacherFeedback.shouldShow(set, holder) {
            card(seconds: seconds, writing: writing)
                .padding(20)
                .card(theme)
                .task(id: Int(seconds / 60)) { writer.refreshIfDue(set, holder, context: context) }
        }
    }

    private func card(seconds: Double, writing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Teacher's feedback").font(theme.font(.section))
                Spacer()
                if writing { ProgressView().accessibilityLabel("Writing feedback") }
            }
            if holder.feedbackText.isEmpty {
                Text("Looking through your answers…").font(theme.font(.body)).foregroundStyle(.secondary)
            } else {
                MathText(markdown: "**" + holder.feedbackHeadline + "**", fontSize: 19)
                    .accessibilityIdentifier("feedbackHeadline")
                MathText(markdown: holder.feedbackText, fontSize: 17)
                Text(Self.footer(holder, seconds: seconds)).font(theme.font(.caption)).foregroundStyle(.secondary)
            }
            if let e = writer.errors[holder.id], !writing {
                Text("Couldn't write new feedback: \(e)").font(theme.font(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    static func footer(_ holder: FeedbackHolder, seconds: Double) -> String {
        let left = max(0, FeedbackSummary.refreshEvery - (seconds - holder.feedbackAtSeconds))
        let mins = Int((left / 60).rounded(.up))
        var parts: [String] = []
        if let d = holder.feedbackDate {
            parts.append("Written " + d.formatted(.relative(presentation: .named)))
        }
        parts.append(mins > 0 ? "new notes after \(mins) more min of practice" : "new notes coming")
        return parts.joined(separator: " · ")
    }
}
