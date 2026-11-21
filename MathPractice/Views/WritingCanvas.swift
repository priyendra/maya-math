import SwiftUI
import PencilKit

/// Owns the PencilKit canvas so views read the ink directly from it (not via a binding that can lag or be
/// overwritten during SwiftUI updates).
@MainActor
final class CanvasController: ObservableObject {
    @Published private(set) var hasInk = false
    /// Bumped on every load/clear: each answer gets a brand-new PKCanvasView. Replacing the drawing of a live
    /// canvas right after a stroke sometimes leaves the old ink on screen until the next stroke.
    @Published private(set) var generation = 0
    fileprivate weak var canvas: PKCanvasView?
    /// Drawing the next canvas starts with (e.g. returning to an exam question).
    fileprivate var pending = PKDrawing()
    /// One tool picker for the whole session, so her pen/color choice carries over between questions.
    fileprivate lazy var toolPicker: PKToolPicker = {
        let picker = PKToolPicker()
        picker.selectedTool = PKInkingTool(.pen, color: .black, width: 3)
        return picker
    }()

    var drawing: PKDrawing { canvas?.drawing ?? pending }

    func load(_ drawing: PKDrawing) {
        pending = drawing
        canvas = nil
        hasInk = !drawing.strokes.isEmpty
        generation += 1
    }

    func clear() { load(PKDrawing()) }

    #if DEBUG
    func markInk() { hasInk = true }
    #endif

    /// Only the current generation's canvas may register or report; a replaced canvas can still get a late
    /// SwiftUI update or delegate callback while it is being torn down.
    fileprivate func attach(_ c: PKCanvasView, generation g: Int) {
        if g == generation { canvas = c }
    }

    fileprivate func changed(_ c: PKCanvasView, generation g: Int) {
        guard g == generation, canvas === c || canvas == nil else { return }
        canvas = c
        let ink = !c.drawing.strokes.isEmpty
        if ink != hasInk { hasInk = ink }
    }
}

/// Large, scrollable Apple Pencil canvas. Fingers scroll; the pencil writes.
struct WritingCanvas: View {
    @ObservedObject var controller: CanvasController
    var graphPaper: Bool = false

    var body: some View {
        CanvasRepresentable(controller: controller, generation: controller.generation, graphPaper: graphPaper)
            .id(controller.generation)
    }

    static let gridTile = CanvasRepresentable.gridTile
}

struct CanvasRepresentable: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    let generation: Int
    var graphPaper: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, generation: generation) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = controller.pending
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif
        let picker = controller.toolPicker
        canvas.tool = picker.selectedTool
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

        picker.addObserver(canvas)
        canvas.accessibilityIdentifier = "writingCanvas"
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        controller.attach(canvas, generation: generation)
        return canvas
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.controller.toolPicker.removeObserver(canvas)
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        controller.attach(canvas, generation: generation)
        // An empty drawing's bounds are CGRect.null (maxY = +∞); an infinite content size silently stops PencilKit
        // from drawing at all.
        let inkBottom = canvas.drawing.strokes.isEmpty ? 0 : canvas.drawing.bounds.maxY
        let height = max(4000, inkBottom + 1200)
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
        let generation: Int
        var grid: UIView?
        init(controller: CanvasController, generation: Int) { self.controller = controller; self.generation = generation }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            MainActor.assumeIsolated { controller.changed(canvas, generation: generation) }
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
