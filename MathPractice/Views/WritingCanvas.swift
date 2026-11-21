import SwiftUI
import PencilKit

/// Large, scrollable Apple Pencil canvas. Fingers scroll; the pencil writes.
struct WritingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var graphPaper: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
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
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
        canvas.contentSize = CGSize(width: max(canvas.bounds.width, 800), height: max(4000, drawing.bounds.maxY + 1200))
        context.coordinator.grid?.isHidden = !graphPaper
        context.coordinator.grid?.frame = CGRect(origin: .zero, size: canvas.contentSize)
        context.coordinator.parent = self
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
        var parent: WritingCanvas
        var toolPicker: PKToolPicker?
        var grid: UIView?
        init(_ parent: WritingCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            parent.drawing = canvas.drawing
        }
    }
}
