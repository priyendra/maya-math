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
    }

    @State private var pages: [DraftPage] = []
    @State private var showScanner = false
    @State private var showPDFImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var title = ""
    @State private var splitSpreads = true
    @State private var importing = false
    @State private var previewID: UUID?

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

                Toggle("Split two-page spreads into left and right pages", isOn: $splitSpreads)
                    .font(.subheadline)
                    .frame(maxWidth: 520)

                TextField("Chapter name (optional — Claude will suggest one)", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                if importing { ProgressView("Adding pages…") }

                if pages.isEmpty {
                    ContentUnavailableView("No pages yet", systemImage: "book.pages",
                                           description: Text("Scan the textbook pages with the exercises (the scanner takes up to 24 pages at a time; tap Scan more pages to continue). Add the answer-key pages too if you have them, and mark them below. Tap a page to check it."))
                } else {
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
                    Button("Create") { create() }
                        .disabled(pages.isEmpty || pages.allSatisfy(\.isAnswerKey) || importing)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner(onFinish: { images in
                    showScanner = false
                    add(images)
                }, onCancel: { showScanner = false })
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case let .success(url) = result { add(PDFPages.images(from: url), split: false) }
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
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(page.wrappedValue.isAnswerKey ? Color.orange : Color.secondary.opacity(0.3), lineWidth: 2))
            Text("Page \(index)").font(.caption)
            Toggle("Answer key", isOn: page.isAnswerKey).font(.caption).toggleStyle(.button)
        }
    }

    /// Compresses new pages off the main thread (splitting spreads if enabled) and appends them.
    private func add(_ images: [UIImage], split: Bool? = nil) {
        guard !images.isEmpty else { return }
        let shouldSplit = split ?? splitSpreads
        importing = true
        Task.detached(priority: .userInitiated) {
            var drafts: [DraftPage] = []
            for image in images {
                autoreleasepool {
                    let parts = shouldSplit ? ImageUtils.splitSpread(image) : [ImageUtils.uprightImage(image)]
                    for part in parts {
                        guard let jpeg = ImageUtils.jpeg(part, maxEdge: 2400, quality: 0.85),
                              let thumbData = ImageUtils.jpeg(part, maxEdge: 400, quality: 0.7),
                              let thumb = UIImage(data: thumbData) else { continue }
                        drafts.append(DraftPage(jpeg: jpeg, thumbnail: thumb))
                    }
                }
            }
            await MainActor.run {
                pages += drafts
                importing = false
            }
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
