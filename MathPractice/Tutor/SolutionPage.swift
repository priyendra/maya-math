import SwiftUI
import PencilKit

/// One answer, all on one page she can write anywhere on: the question, her work, where it went wrong, the
/// solution, and a voice tutor that points at the page and writes on a board at the bottom.
struct SolutionPage: View {
    let attempt: Attempt
    @StateObject private var tutor: TutorSession
    @StateObject private var ink = PageInk()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(attempt: Attempt) {
        self.attempt = attempt
        _tutor = StateObject(wrappedValue: TutorSession(attempt: attempt))
    }

    var body: some View {
        NavigationStack {
            InkPageView(ink: ink)
                .background(Color(uiColor: .systemBackground))
                .safeAreaInset(edge: .bottom) { bottomBar }
                .navigationTitle(attempt.wasStuck ? "Solution" : "Your answer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let q = attempt.question {
                        ToolbarItem(placement: .topBarLeading) { ChapterLink(question: q) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { tutor.end(); dismiss() }
                    }
                }
        }
        .onAppear {
            ink.install(PageContent(attempt: attempt, tutor: tutor, ink: ink))
            ink.onInk = { [weak tutor] in tutor?.inkChanged() }
            ink.onTap = { [weak tutor] in tutor?.interrupt() }
            tutor.snapshot = { [weak ink] in ink?.snapshot() }
        }
        .onChange(of: tutor.pointer) { _, id in ink.reveal(id) }
        // Only a real trip to the background ends the talk (permission prompts make the app briefly inactive).
        .onChange(of: scenePhase) { _, p in if p == .background { tutor.end() } }
        .onDisappear { tutor.end() }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $ink.tool) {
                Image(systemName: "pencil.tip").accessibilityLabel("Pencil").tag(PageInk.Tool.pen)
                Image(systemName: "highlighter").accessibilityLabel("Highlighter").tag(PageInk.Tool.highlighter)
                Image(systemName: "eraser").accessibilityLabel("Eraser").tag(PageInk.Tool.eraser)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            Button { ink.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .accessibilityLabel("Undo")
            Button { ink.clear() } label: { Image(systemName: "trash") }
                .accessibilityLabel("Clear my writing")
                .disabled(!ink.hasInk)
            Divider().frame(height: 30)
            tutorControls
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    @ViewBuilder private var tutorControls: some View {
        switch tutor.state {
        case .off:
            Spacer()
            Button { tutor.start() } label: {
                Label("Talk to the tutor", systemImage: "waveform.circle.fill").font(.title3.bold())
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("talkToTutor")
        default:
            status.frame(maxWidth: .infinity, alignment: .leading)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-fakeTutor"), tutor.state == .listening {
                Button("Say") { tutor.debugSay("Why is it three a?") }.accessibilityIdentifier("debugSay")
            }
            #endif
            if case .waiting = tutor.state {
                Button { tutor.talk() } label: { Label("Talk", systemImage: "mic.fill") }.buttonStyle(.borderedProminent)
            }
            Button(role: .destructive) { tutor.end() } label: { Label("End talk", systemImage: "xmark.circle.fill") }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 10) {
            switch tutor.state {
            case .off:
                EmptyView()
            case .starting:
                ProgressView()
                Text("Getting ready…").foregroundStyle(.secondary)
            case .thinking:
                ProgressView()
                Text("Thinking…").foregroundStyle(.secondary)
            case .speaking:
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.blue).symbolEffect(.variableColor.iterative)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MathPlain.render(tutor.caption)).lineLimit(2)
                    Text("Tap the page to interrupt").font(.caption).foregroundStyle(.secondary)
                }
            case .listening:
                Image(systemName: "mic.fill").foregroundStyle(.green).symbolEffect(.pulse)
                Text(tutor.heard.isEmpty ? "Listening… ask anything, and circle what you mean" : tutor.heard)
                    .lineLimit(2).foregroundStyle(tutor.heard.isEmpty ? .secondary : .primary)
                    .accessibilityIdentifier("tutorListening")
            case let .waiting(message):
                Image(systemName: "mic.slash").foregroundStyle(.secondary)
                Text(message).font(.callout).lineLimit(3)
            }
        }
    }
}

// MARK: - Page content (rendered under the ink)

struct PartFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Marks a part of the page the tutor can point at.
    func part(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: PartFrames.self, value: [id: g.frame(in: .named("page"))])
        })
    }
}

private struct PageContent: View {
    let attempt: Attempt
    @ObservedObject var tutor: TutorSession
    let ink: PageInk

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(tutor.parts.filter { !$0.id.hasPrefix("s") }) { p in
                section(p)
            }
            let steps = tutor.parts.filter { $0.id.hasPrefix("s") }
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    header("Solution", "checkmark.seal.fill", .blue)
                    ForEach(steps) { s in MathText(markdown: s.markdown, fontSize: 20).part(s.id) }
                }
            }
            if !tutor.board.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    header("Tutor's board", "rectangle.and.pencil.and.ellipsis", Theme.classic.board)
                    ForEach(tutor.board) { b in
                        MathText(markdown: b.markdown, fontSize: 22).part(b.id)
                    }
                }
                .padding(16)
                .background(Theme.classic.board.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("Room to write ↓").font(.caption).foregroundStyle(.tertiary)
            Color.clear.frame(height: 420)
        }
        .padding(28)
        .frame(maxWidth: 820, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "page")
        .overlayPreferenceValue(PartFrames.self) { frames in
            PointerOverlay(target: tutor.pointer.flatMap { frames[$0] })
        }
        .background(GeometryReader { g in Color.clear.preference(key: ContentHeight.self, value: g.size.height) })
        .onPreferenceChange(PartFrames.self) { ink.setFrames($0) }
        .onPreferenceChange(ContentHeight.self) { ink.setContentHeight($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func section(_ p: PagePart) -> some View {
        switch p.id {
        case "question":
            if let q = attempt.question {
                QuestionPanel(question: q, label: "Question")
                    .padding(16)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .part(p.id)
            }
        case "hint":
            VStack(alignment: .leading, spacing: 6) {
                header("Hint you used", "lightbulb.fill", .orange)
                MathText(markdown: p.markdown, fontSize: 18)
            }
            .part(p.id)
        case "work":
            VStack(alignment: .leading, spacing: 6) {
                header("Your work", "pencil.and.scribble", .secondary)
                if let data = attempt.renderedImage, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 420, alignment: .leading)
                        .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                }
            }
            .part(p.id)
        case "wrong":
            VStack(alignment: .leading, spacing: 6) {
                header("Where it went wrong", "arrow.uturn.left.circle.fill", Theme.classic.notQuite)
                MathText(markdown: p.markdown, fontSize: 19)
            }
            .padding(14)
            .background(Theme.classic.notQuite.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .part(p.id)
        default:
            EmptyView()
        }
    }

    private func header(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
    }
}

/// The tutor's cursor: glides to what the voice is talking about and softly highlights it.
struct PointerOverlay: View {
    let target: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let f = target {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.yellow.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.55), lineWidth: 2))
                    .frame(width: f.width + 20, height: f.height + 12)
                    .position(x: f.midX, y: f.midY)
                    .transition(.opacity)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.black)
                    .background(Image(systemName: "cursorarrow").font(.system(size: 34, weight: .heavy)).foregroundStyle(.white))
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 1, y: 2)
                    // The arrow's tip touches the target's lower-left corner, so it never covers what it points at.
                    .position(x: f.minX - 6 + 12, y: f.maxY + 4 + 16)
                    .accessibilityIdentifier("tutorCursor")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.55), value: target)
        .allowsHitTesting(false)
    }
}

// MARK: - The ink layer

struct InkPageView: UIViewRepresentable {
    let ink: PageInk
    func makeUIView(context: Context) -> PKCanvasView { ink.canvas }
    func updateUIView(_ view: PKCanvasView, context: Context) {}
}

/// A scrolling Pencil canvas with the page content hosted underneath the ink. Pencil writes, fingers scroll.
@MainActor
final class PageInk: NSObject, ObservableObject, PKCanvasViewDelegate {
    enum Tool: Hashable { case pen, highlighter, eraser }
    @Published var tool: Tool = .pen { didSet { applyTool() } }
    @Published private(set) var hasInk = false

    let canvas = LayoutCanvas()
    var onInk: () -> Void = {}
    var onTap: () -> Void = {}

    private var host: UIHostingController<AnyView>?
    /// Where each part is on the page (page coordinates), and how far the page is scrolled.
    @Published private(set) var frames: [String: CGRect] = [:]
    @Published private(set) var offset: CGPoint = .zero
    private var contentHeight: CGFloat = 3000
    private var pendingReveal: String?
    private var strokesAtLastTurn = 0

    override init() {
        super.init()
        canvas.delegate = self
        // Transparent: an opaque canvas paints its background over the hosted page content.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        // Fingers scroll, the Pencil writes. (Simulator tests can opt into finger ink with -fingerInk.)
        canvas.drawingPolicy = ProcessInfo.processInfo.arguments.contains("-fingerInk") ? .anyInput : .pencilOnly
        applyTool()
        canvas.onLayout = { [weak self] in self?.layout() }
        canvas.accessibilityIdentifier = "solutionPage"
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)
    }

    func install<V: View>(_ content: V) {
        guard host == nil else { return }
        let h = UIHostingController(rootView: AnyView(content))
        h.safeAreaRegions = []
        h.view.backgroundColor = .clear
        h.view.isUserInteractionEnabled = false
        canvas.insertSubview(h.view, at: 0)
        host = h
        layout()
    }

    private func applyTool() {
        switch tool {
        case .pen: canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 3)
        case .highlighter: canvas.tool = PKInkingTool(.marker, color: UIColor.systemYellow.withAlphaComponent(0.35), width: 24)
        case .eraser: canvas.tool = PKEraserTool(.vector)
        }
    }

    func undo() { canvas.undoManager?.undo() }

    func clear() {
        canvas.drawing = PKDrawing()
        strokesAtLastTurn = 0
    }

    // MARK: Layout

    private func layout() {
        let width = canvas.bounds.width
        guard width > 0 else { return }
        host?.view.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        let inkBottom = canvas.drawing.strokes.isEmpty ? 0 : canvas.drawing.bounds.maxY + 300
        let height = max(contentHeight, inkBottom, canvas.bounds.height)
        if canvas.contentSize != CGSize(width: width, height: height) {
            canvas.contentSize = CGSize(width: width, height: height)
        }
    }

    func setContentHeight(_ h: CGFloat) {
        guard h > 0, abs(h - contentHeight) > 0.5 else { return }
        contentHeight = h
        layout()
        revealPending()
    }

    func setFrames(_ f: [String: CGRect]) {
        if frames != f { frames = f }
        revealPending()
    }

    /// Scrolls so the part the tutor is talking about is on screen.
    func reveal(_ id: String?) {
        pendingReveal = id
        revealPending()
    }

    private func revealPending() {
        guard let id = pendingReveal, let r = frames[id] else { return }
        pendingReveal = nil
        let visible = CGRect(origin: canvas.contentOffset, size: canvas.bounds.size).inset(by: canvas.adjustedContentInset)
        guard !visible.contains(r) else { return }
        canvas.scrollRectToVisible(r.insetBy(dx: 0, dy: -80), animated: true)
    }

    // MARK: Ink

    nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        MainActor.assumeIsolated {
            hasInk = !canvas.drawing.strokes.isEmpty
            if canvas.drawing.strokes.count < strokesAtLastTurn { strokesAtLastTurn = canvas.drawing.strokes.count }
            layout()
            onInk()
        }
    }

    @objc private func tapped() { onTap() }

    nonisolated func scrollViewDidScroll(_ scrollView: UIScrollView) {
        MainActor.assumeIsolated { if offset != canvas.contentOffset { offset = canvas.contentOffset } }
    }

    /// A picture of her handwriting inside a part of the page (e.g. a blank), or nil if she wrote nothing there.
    func image(in id: String) -> Data? {
        guard let r = frames[id]?.insetBy(dx: -16, dy: -16) else { return nil }
        let strokes = canvas.drawing.strokes.filter { $0.renderBounds.intersects(r) }
        guard !strokes.isEmpty else { return nil }
        return ImageUtils.renderDrawing(PKDrawing(strokes: strokes))
    }

    /// Her handwriting below a part of the page (e.g. under a problem): the strokes and a picture of them.
    func work(below id: String) -> (ink: Data, image: Data)? {
        guard let top = frames[id]?.minY else { return nil }
        let strokes = canvas.drawing.strokes.filter { $0.renderBounds.maxY > top + 8 }
        guard !strokes.isEmpty else { return nil }
        let drawing = PKDrawing(strokes: strokes)
        guard let image = ImageUtils.renderDrawing(drawing) else { return nil }
        return (drawing.dataRepresentation(), image)
    }

    /// What she's looking at: the visible page with her ink, marks made since the last snapshot drawn in pink.
    func snapshot() -> PageSnapshot? {
        let b = canvas.bounds
        guard b.width > 0, b.height > 0 else { return nil }
        let strokes = canvas.drawing.strokes
        let fresh = strokes.count > strokesAtLastTurn ? Array(strokes[strokesAtLastTurn...]) : []
        strokesAtLastTurn = strokes.count
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.25
        // The canvas is transparent: capture it, then lay it on the page background (an opaque capture comes out black).
        let page = UIGraphicsImageRenderer(size: b.size, format: format).image { _ in
            canvas.drawHierarchy(in: CGRect(origin: .zero, size: b.size), afterScreenUpdates: false)
        }
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: b.size, format: format).image { ctx in
            UIColor.systemBackground.resolvedColor(with: canvas.traitCollection).setFill()
            ctx.fill(CGRect(origin: .zero, size: b.size))
            page.draw(at: .zero)
            if !fresh.isEmpty {
                let pink = fresh.map { s -> PKStroke in
                    var s = s
                    // Highlights stay highlights (translucent marker), just pink like her other new marks.
                    s.ink = s.ink.inkType == .marker ? PKInk(.marker, color: .systemPink) : PKInk(.pen, color: .systemPink)
                    return s
                }
                PKDrawing(strokes: pink).image(from: b, scale: format.scale).draw(in: CGRect(origin: .zero, size: b.size))
            }
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.75) else { return nil }
        let visible = frames.filter { $0.value.intersects(b) }.sorted { $0.value.minY < $1.value.minY }.map(\.key)
        return PageSnapshot(jpeg: jpeg, visibleParts: visible, newMarks: !fresh.isEmpty)
    }
}

final class LayoutCanvas: PKCanvasView {
    var onLayout: () -> Void = {}
    private var lastWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            onLayout()
        }
    }
}
