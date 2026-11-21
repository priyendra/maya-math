#if DEBUG
import SwiftUI
import PencilKit
import SwiftData

/// Debug-only: `-canvasLab 0|1|2` shows a stock PKCanvasView (0) or our WritingCanvas (1, 2 = inside a
/// NavigationStack) full screen, so UI tests can check that drawing registers.
struct CanvasLab: View {
    let variant: Int
    @StateObject private var controller = CanvasController()

    var body: some View {
        VStack(spacing: 0) {
            Text(controller.hasInk ? "INK" : "EMPTY").accessibilityIdentifier("inkState").padding()
            switch variant {
            case 0: BareCanvas(onChange: { controller.markInk() })
            case 1: WritingCanvas(controller: controller)
            default:
                NavigationStack { WritingCanvas(controller: controller).toolbar { Text("x") } }
            }
        }
    }

    static var requested: Int? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-canvasLab"), i + 1 < a.count else { return nil }
        return Int(a[i + 1])
    }
}

struct BareCanvas: UIViewRepresentable {
    let onChange: () -> Void
    func makeCoordinator() -> C { C(onChange: onChange) }
    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.delegate = context.coordinator
        v.accessibilityIdentifier = "writingCanvas"
        return v
    }
    func updateUIView(_ v: PKCanvasView, context: Context) {}
    final class C: NSObject, PKCanvasViewDelegate {
        let onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ c: PKCanvasView) { onChange() }
    }
}
#endif


#if DEBUG
/// Debug-only: `-checkInLab` shows a check-in with the seeded graded attempts (use with -seedSample -seedGraded).
struct CheckInLab: View {
    @Query private var attempts: [Attempt]
    var body: some View {
        let stuckOnly = ProcessInfo.processInfo.arguments.contains("-stuckOnly")
        CheckInView(items: attempts.filter { $0.isGraded && $0.effectiveVerdict == .incorrect && (!stuckOnly || $0.wasStuck) },
                    pending: 0, kind: stuckOnly ? .interruption : .regular, onContinue: {})
    }
}
#endif

#if DEBUG
struct SeededCheckInLab: View {
    @Environment(\.modelContext) private var context
    @State private var ready = false
    var body: some View {
        Group { if ready { CheckInLab() } else { ProgressView() } }
            .onAppear { SampleData.seedIfRequested(context: context); ready = true }
    }
}
#endif
