import SwiftUI
import PencilKit

/// Owns the PencilKit canvas so views read the ink directly from it (not via a binding that can lag or be
/// overwritten during SwiftUI updates).
@MainActor
final class CanvasController: ObservableObject {
    @Published private(set) var hasInk = false
    fileprivate weak var canvas: PKCanvasView?
    /// Drawing to load once the canvas exists (e.g. returning to an exam question).
    fileprivate var pending: PKDrawing?

    var drawing: PKDrawing { canvas?.drawing ?? pending ?? PKDrawing() }

    func load(_ drawing: PKDrawing) {
        pending = drawing
        canvas?.drawing = drawing
        hasInk = !drawing.strokes.isEmpty
    }

    func clear() { load(PKDrawing()) }

    fileprivate func changed() {
        let ink = !(canvas?.drawing.strokes.isEmpty ?? true)
        if ink != hasInk { hasInk = ink }
    }
}

/// Large, scrollable Apple Pencil canvas. Fingers scroll; the pencil writes.
struct WritingCanvas: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var graphPaper: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = controller.pending ?? PKDrawing()
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif
        // PencilKit adapts black ink for dark mode itself.
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.contentSize = CGSize(width: 2000, height: 4000)

        // Grid lives inside the scroll view so it scrolls with the ink.
        let grid = UIView()
        grid.backgroundColor = UIColor(patternImage: Self.gridTile)
        grid.isUserInteractionEnabled = false
        grid.isHidden = !graphPaper
        canvas.insertSubview(grid, at: 0)
        context.coordinator.grid = grid

        let picker = PKToolPicker()
        context.coordinator.toolPicker = picker
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        controller.canvas = canvas
        let height = max(4000, canvas.drawing.bounds.maxY + 1200)
        let size = CGSize(width: max(canvas.bounds.width, 800), height: height)
        if canvas.contentSize != size { canvas.contentSize = size }
        context.coordinator.grid?.isHidden = !graphPaper
        context.coordinator.grid?.frame = CGRect(origin: .zero, size: size)
    }

    static let gridTile: UIImage = {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemBlue.withAlphaComponent(0.13).setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: 0.5)); path.addLine(to: CGPoint(x: size.width, y: 0.5))
            path.move(to: CGPoint(x: 0.5, y: 0)); path.addLine(to: CGPoint(x: 0.5, y: size.height))
            path.lineWidth = 1
            path.stroke()
        }
    }()

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController
        var toolPicker: PKToolPicker?
        var grid: UIView?
        init(controller: CanvasController) { self.controller = controller }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            MainActor.assumeIsolated { controller.changed() }
        }
    }
}

/// Ticking clock that redraws only itself (not the canvas around it).
struct ClockLabel: View {
    let clock: ActiveClock
    var target: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = clock.elapsed(now: context.date)
            if let target {
                Label("\(formatClock(elapsed)) · goal \(formatClock(target))", systemImage: "stopwatch")
                    .monospacedDigit().foregroundStyle(elapsed > target ? .orange : .green)
            } else {
                Label(formatClock(elapsed), systemImage: "stopwatch").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
