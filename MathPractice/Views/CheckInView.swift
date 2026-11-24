import SwiftUI

/// Shows background-graded results: a one-line summary, mistakes first (expanded), correct answers compact.
struct CheckInView: View {
    enum Kind { case regular, interruption, repeated, final }

    let items: [Attempt]
    let pending: Int
    let kind: Kind
    let onContinue: () -> Void
    @State private var detail: Attempt?

    private var mistakes: [Attempt] { items.filter { $0.effectiveVerdict == .incorrect } }
    private var unsure: [Attempt] { items.filter { $0.effectiveVerdict == .needsReview } }
    private var correct: [Attempt] { items.filter { $0.effectiveVerdict == .correct } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(mistakes) { a in
                    if let q = a.question { FeedbackCard(attempt: a, question: q).card(Theme.classic) }
                }
                if !unsure.isEmpty {
                    Text("Couldn't check for sure").font(.headline)
                    ForEach(unsure) { a in
                        if let q = a.question { FeedbackCard(attempt: a, question: q).card(Theme.classic) }
                    }
                }
                if !correct.isEmpty {
                    Text("Correct").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(correct) { a in
                                Button { detail = a } label: {
                                    Label(MathText.plainPreview(a.question?.text ?? "").prefix(28) + "…", systemImage: "checkmark.circle.fill")
                                        .lineLimit(1)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Theme.classic.done.opacity(0.12), in: Capsule())
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if pending > 0, kind != .final {
                    Text("\(pending) more still being checked — you'll see them next time.").foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(action: onContinue) {
                        Label(kind == .final ? "Finish" : "Keep going", systemImage: "arrow.right").font(.title3.bold())
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $detail) { a in
            ScrollView { if let q = a.question { FeedbackCard(attempt: a, question: q).padding() } }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch kind {
        case .interruption:
            Label("Before you go on, look at this one", systemImage: "hand.raised.fill")
                .font(.title.bold()).foregroundStyle(Theme.classic.attention)
        case .repeated:
            VStack(alignment: .leading, spacing: 10) {
                Label("Same mistake twice", systemImage: "repeat")
                    .font(.title.bold()).foregroundStyle(Theme.classic.attention)
                    .accessibilityIdentifier("repeatedMistake")
                if let m = items.last?.mistakeType {
                    Text(RepeatedMistake.habit(m)).font(.title3)
                }
            }
        case .regular, .final:
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .final ? "How you did" : "Check-in").font(.largeTitle.bold())
                let counted = items.filter { $0.effectiveVerdict != .needsReview }.count
                Text("\(counted) done · \(correct.count) right")
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
    }
}
