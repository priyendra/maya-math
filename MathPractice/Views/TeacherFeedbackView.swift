import SwiftUI

/// "Teacher's feedback" on the chapter page: Claude's notes on her answers, rewritten every 30 minutes of practice.
struct TeacherFeedbackCard: View {
    let chapter: Chapter
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @ObservedObject private var writer = TeacherFeedback.shared

    var body: some View {
        let seconds = TeacherFeedback.practiceSeconds(chapter)
        let writing = writer.writing.contains(chapter.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Teacher's feedback").font(theme.font(.section))
                Spacer()
                if writing { ProgressView().accessibilityLabel("Writing feedback") }
            }
            if chapter.feedbackText.isEmpty {
                Text(writing ? "Looking through your answers…"
                     : "After your first \(FeedbackSummary.minimumAnswers) answers, you'll find notes here on what's going well and what to work on.")
                    .font(theme.font(.body)).foregroundStyle(.secondary)
            } else {
                MathText(markdown: "**" + chapter.feedbackHeadline + "**", fontSize: 19)
                    .accessibilityIdentifier("feedbackHeadline")
                MathText(markdown: chapter.feedbackText, fontSize: 17)
                Text(Self.footer(chapter, seconds: seconds)).font(theme.font(.caption)).foregroundStyle(.secondary)
            }
            if let e = writer.errors[chapter.id], !writing {
                Text("Couldn't write new feedback: \(e)").font(theme.font(.caption)).foregroundStyle(.secondary)
            }
        }
        .task(id: Int(seconds / 60)) { writer.refreshIfDue(chapter, context: context) }
    }

    static func footer(_ chapter: Chapter, seconds: Double) -> String {
        let left = max(0, FeedbackSummary.refreshEvery - (seconds - chapter.feedbackAtSeconds))
        let mins = Int((left / 60).rounded(.up))
        var parts: [String] = []
        if let d = chapter.feedbackDate {
            parts.append("Written " + d.formatted(.relative(presentation: .named)))
        }
        parts.append(mins > 0 ? "new notes after \(mins) more min of practice" : "new notes coming")
        return parts.joined(separator: " · ")
    }
}
