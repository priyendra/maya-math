import SwiftUI
import WebKit
import PencilKit

/// Her ink on the book half of a lesson: a Pencil layer inside the book's scroll view, so marks stay on the text
/// they were made on. Fingers scroll the book; the Pencil writes.
@MainActor
final class BookInk: NSObject, ObservableObject {
    let canvas = PKCanvasView()
    weak var web: WKWebView?
    var onTap: () -> Void = {}
    /// Where the highlighted block is in the book's view (nil: none, or not reported yet).
    @Published var saidRect: CGRect?

    override init() {
        super.init()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = ProcessInfo.processInfo.arguments.contains("-fingerInk") ? .anyInput : .pencilOnly
        setTool(.pen)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)
    }

    @objc private func tapped() { onTap() }

    func setTool(_ t: PageInk.Tool) {
        switch t {
        case .pen: canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 3)
        case .highlighter: canvas.tool = PKInkingTool(.marker, color: UIColor.systemYellow.withAlphaComponent(0.35), width: 24)
        case .eraser: canvas.tool = PKEraserTool(.vector)
        }
    }

    func clear() { canvas.drawing = PKDrawing() }

    /// What she sees of the book right now, with her marks.
    func snapshot() -> UIImage? {
        guard let web, web.bounds.width > 0, web.bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.25
        format.opaque = true
        return UIGraphicsImageRenderer(size: web.bounds.size, format: format).image { ctx in
            UIColor.systemBackground.resolvedColor(with: web.traitCollection).setFill()
            ctx.fill(CGRect(origin: .zero, size: web.bounds.size))
            web.drawHierarchy(in: CGRect(origin: .zero, size: web.bounds.size), afterScreenUpdates: false)
        }
    }
}

/// The book half: the section exactly as the chapter reader shows it, the block being taught highlighted.
struct BookPane: UIViewRepresentable {
    let chapter: Chapter
    let section: Int
    let pointAt: UUID?
    let ink: BookInk

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var section: Int?
        var pointed: UUID?
        var sizeObservation: NSKeyValueObservation?
        weak var ink: BookInk?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let d = message.body as? [String: Any] else { return }
            if d["none"] != nil { ink?.saidRect = nil; return }
            let n = { (k: String) in CGFloat((d[k] as? NSNumber)?.doubleValue ?? 0) }
            ink?.saidRect = CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h"))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "said")
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        context.coordinator.ink = ink
        config.userContentController.add(context.coordinator, name: "said")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "lessonBook"
        view.scrollView.addSubview(ink.canvas)
        let canvas = ink.canvas
        context.coordinator.sizeObservation = view.scrollView.observe(\.contentSize, options: [.initial, .new]) { sv, _ in
            MainActor.assumeIsolated { canvas.frame = CGRect(origin: .zero, size: sv.contentSize) }
        }
        ink.web = view
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let c = context.coordinator
        if c.section != section {
            c.section = section
            c.pointed = pointAt
            ink.clear()
            ink.saidRect = nil
            view.loadHTMLString(ReadChapterView.html(chapter, section: section, said: pointAt),
                                baseURL: Bundle.main.url(forResource: "katex", withExtension: nil))
        } else if c.pointed != pointAt {
            c.pointed = pointAt
            let arg = pointAt.map { "'\($0.uuidString)'" } ?? "null"
            view.evaluateJavaScript("window.pointAt && window.pointAt(\(arg))")
        }
    }
}
