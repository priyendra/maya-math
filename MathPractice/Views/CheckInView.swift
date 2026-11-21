import SwiftUI

/// Shows background-graded results: a one-line summary, mistakes first (expanded), correct answers compact.
struct CheckInView: View {
    enum Kind { case regular, interruption, final }

    let items: [Attempt]
    let pending: Int
    let kind: Kind
    let onContinue: () -> Void
    @State private var detail: Attempt?

    private var mistakes: [Attempt] { items.filter { $0.effectiveVerdict == .incorrect } }
    private var unsure: [Attempt] { items.filter { $0.effectiveVerdict == .needsReview } }
    private var correct: [Attempt] { items.filter { $0.effectiveVerdict == .correct } }
    private var fast: Int {
        correct.filter { a in a.question.map { a.activeSeconds <= LearningStore.targetSeconds(for: $0) } ?? false }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(mistakes) { a in
                    if let q = a.question { FeedbackCard(attempt: a, question: q) }
                }
                if !unsure.isEmpty {
                    Text("Couldn't check for sure").font(.headline)
                    ForEach(unsure) { a in
                        if let q = a.question { FeedbackCard(attempt: a, question: q) }
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
                                        .background(Color.green.opacity(0.12), in: Capsule())
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
                .font(.title.bold()).foregroundStyle(.orange)
        case .regular, .final:
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .final ? "How you did" : "Check-in").font(.largeTitle.bold())
                let counted = items.filter { $0.effectiveVerdict != .needsReview }.count
                Text("\(counted) done · \(correct.count) right" + (fast > 0 ? " · \(fast) faster than your target" : ""))
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
    }
}
