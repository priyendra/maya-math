import SwiftUI

/// Question text + figure (tap the figure to enlarge).
struct QuestionPanel: View {
    let question: Question
    var label: String?
    @State private var zoomFigure = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let label { Text(label).font(.caption.bold()).foregroundStyle(.secondary) }
                MathText(markdown: question.text, fontSize: 22)
            }
            if let data = question.figureData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { zoomFigure = true }
            }
        }
        .sheet(isPresented: $zoomFigure) {
            if let data = question.figureData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().padding().background(Color.white)
            }
        }
    }
}

/// Measures time the app is actually in the foreground.
struct ActiveClock {
    private(set) var accumulated: TimeInterval = 0
    private var resumedAt: Date? = Date()

    mutating func pause(now: Date = Date()) {
        if let r = resumedAt { accumulated += now.timeIntervalSince(r) }
        resumedAt = nil
    }
    mutating func resume(now: Date = Date()) { if resumedAt == nil { resumedAt = now } }
    mutating func reset(now: Date = Date()) { accumulated = 0; resumedAt = now }
    /// Restart running, with time already spent (a restored draft).
    mutating func reset(elapsed: TimeInterval, now: Date = Date()) { accumulated = elapsed; resumedAt = now }
    func elapsed(now: Date = Date()) -> TimeInterval { accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0) }
}

func formatClock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}
