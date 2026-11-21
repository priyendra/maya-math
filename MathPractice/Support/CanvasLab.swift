#if DEBUG
import SwiftUI
import PencilKit

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

