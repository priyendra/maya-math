import SwiftUI
import SwiftData
import PhotosUI

/// Collect pages (scan / photos / PDF), mark answer-key pages, then create + process the chapter.
/// Pages are compressed as soon as they arrive so large chapters (70+ pages) don't exhaust memory.
struct NewChapterView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var processor = ChapterProcessor.shared

    struct DraftPage: Identifiable {
        let id = UUID()
        var jpeg: Data
        var thumbnail: UIImage
        var isAnswerKey = false
        var issues: [ScanQuality.Issue] = []
    }

    @State private var pages: [DraftPage] = []
    @State private var showScanner = false
    @State private var showPDFImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var title = ""
    @State private var importing = false
    @State private var previewID: UUID?
    /// The page being retaken (its new photo replaces it).
    @State private var retakeID: UUID?
    @State private var confirmCreate = false

    var onCreated: (Chapter) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if DocumentScanner.isSupported {
                        Button { showScanner = true } label: {
                            Label(pages.isEmpty ? "Scan pages" : "Scan more pages", systemImage: "doc.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    Button { showPDFImporter = true } label: { Label("PDF", systemImage: "doc.richtext") }
                        .buttonStyle(.bordered)
                }
                .padding(.top)

                TextField("Chapter name (optional — Claude will suggest one)", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                if importing { ProgressView("Checking pages…") }

                if pages.isEmpty {
                    ContentUnavailableView("No pages yet", systemImage: "book.pages", description: Text(Self.tips))
                } else {
                    let flagged = pages.filter { !$0.issues.isEmpty }.count
                    if flagged > 0 {
                        Label("\(flagged) page\(flagged == 1 ? " needs" : "s need") another try. Tap Retake under \(flagged == 1 ? "it" : "each one").",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.orange)
                    }
                    Text("\(pages.count) pages · \(pages.filter(\.isAnswerKey).count) answer-key pages · tap a page to check it")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                            ForEach($pages) { $page in pageCell($page) }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("New chapter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { if pages.contains(where: { !$0.issues.isEmpty }) { confirmCreate = true } else { create() } }
                        .disabled(pages.isEmpty || pages.allSatisfy(\.isAnswerKey) || importing)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner(onFinish: { images in
                    showScanner = false
                    add(images, replacing: retakeID)
                    retakeID = nil
                }, onCancel: { showScanner = false; retakeID = nil })
                .ignoresSafeArea()
            }
            .alert("Some pages need another try", isPresented: $confirmCreate) {
                Button("Retake them", role: .cancel) {}
                Button("Create anyway") { create() }
            } message: {
                Text("Blurry or dark pages can't be read well, so some questions may be missing. Retake them now while the book is open?")
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case let .success(url) = result { add(PDFPages.images(from: url)) }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    photoItems = []
                    add(images)
                }
            }
            .fullScreenCover(item: Binding(get: { previewID.map { PreviewTarget(id: $0) } }, set: { previewID = $0?.id })) { target in
                PagePreview(pages: $pages, startID: target.id) { previewID = nil }
            }
        }
    }

    private struct PreviewTarget: Identifiable { let id: UUID }

    private func pageCell(_ page: Binding<DraftPage>) -> some View {
        let index = (pages.firstIndex { $0.id == page.wrappedValue.id } ?? 0) + 1
        return VStack(spacing: 6) {
            Image(uiImage: page.wrappedValue.thumbnail)
                .resizable()
                .scaledToFit()
                .frame(height: 190)
                .onTapGesture { previewID = page.wrappedValue.id }
                .overlay(alignment: .topTrailing) {
                    Button { pages.removeAll { $0.id == page.wrappedValue.id } } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white, .red)
                    }
                    .padding(4)
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(!page.wrappedValue.issues.isEmpty ? Color.red : page.wrappedValue.isAnswerKey ? Color.orange : Color.secondary.opacity(0.3),
                                                                  lineWidth: page.wrappedValue.issues.isEmpty ? 2 : 4))
                .overlay(alignment: .topLeading) {
                    if !page.wrappedValue.issues.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.white, .orange).padding(4)
                    }
                }
            Text("Page \(index)").font(.caption)
            if let issue = page.wrappedValue.issues.first {
                Text(issue.advice).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if DocumentScanner.isSupported {
                    Button { retakeID = page.wrappedValue.id; showScanner = true } label: {
                        Label("Retake", systemImage: "camera.rotate")
                    }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                }
            } else {
                Toggle("Answer key", isOn: page.isAnswerKey).font(.caption).toggleStyle(.button)
            }
        }
    }

    static let tips = """
    Scan the pages with the lessons and exercises. Tips for a good scan:
    • Lay the book flat in a bright spot.
    • Fit the whole page inside the frame, page number too.
    • Hold the iPad still until it takes the picture.
    The scanner takes up to 24 pages at a time; tap Scan more pages to keep going. Add the answer pages from the back of the book too if you have them, and mark them below.
    """

    /// Compresses and checks new pages off the main thread. With `replacing`, the first new page takes that page's
    /// place (a retake) and any others follow it.
    private func add(_ images: [UIImage], replacing: UUID? = nil) {
        guard !images.isEmpty else { return }
        importing = true
        Task {
            let scanned = await ScannedPage.process(images)
            let drafts = scanned.compactMap { s in
                UIImage(data: s.thumbnail).map { DraftPage(jpeg: s.jpeg, thumbnail: $0, issues: s.issues) }
            }
            if let replacing, let i = pages.firstIndex(where: { $0.id == replacing }), let first = drafts.first {
                var fixed = first
                fixed.isAnswerKey = pages[i].isAnswerKey
                pages[i] = fixed
                pages.insert(contentsOf: drafts.dropFirst(), at: i + 1)
            } else {
                pages += drafts
            }
            importing = false
        }
    }

    private func create() {
        let chapter = Chapter(title: title.isEmpty ? "New chapter" : title)
        context.insert(chapter)
        for (i, draft) in pages.enumerated() {
            let page = PageImage(order: i, imageData: draft.jpeg, isAnswerKey: draft.isAnswerKey)
            page.chapter = chapter
            context.insert(page)
        }
        try? context.save()
        processor.start(chapter, context: context)
        onCreated(chapter)
        dismiss()
    }
}

/// Full-screen page check: zoom, rotate, mark as answer key, delete; swipe between pages.
private struct PagePreview: View {
    @Binding var pages: [NewChapterView.DraftPage]
    let startID: UUID
    let onClose: () -> Void
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(pages) { page in
                    ZoomableImage(image: UIImage(data: page.jpeg) ?? page.thumbnail)
                        .tag(Optional(page.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: onClose) }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { rotate() } label: { Label("Rotate", systemImage: "rotate.right") }
                    Spacer()
                    if let i = currentIndex {
                        Toggle("Answer key", isOn: $pages[i].isAnswerKey).toggleStyle(.button)
                    }
                    Spacer()
                    Button(role: .destructive) { delete() } label: { Label("Delete page", systemImage: "trash") }
                }
            }
        }
        .onAppear { selection = startID }
    }

    private var currentIndex: Int? { pages.firstIndex { $0.id == selection } }
    private var title: String { currentIndex.map { "Page \($0 + 1) of \(pages.count)" } ?? "" }

    private func rotate() {
        guard let i = currentIndex, let data = ImageUtils.rotated90(pages[i].jpeg) else { return }
        pages[i].jpeg = data
        if let thumbData = UIImage(data: data).flatMap({ ImageUtils.jpeg($0, maxEdge: 400, quality: 0.7) }),
           let thumb = UIImage(data: thumbData) {
            pages[i].thumbnail = thumb
        }
    }

    private func delete() {
        guard let i = currentIndex else { return }
        pages.remove(at: i)
        if pages.isEmpty { onClose(); return }
        selection = pages[min(i, pages.count - 1)].id
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = imageView
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}
