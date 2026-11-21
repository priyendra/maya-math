import SwiftUI
import SwiftData
import PhotosUI

/// Collect pages (scan / photos / PDF), mark answer-key pages, then create + process the chapter.
struct NewChapterView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var processor = ChapterProcessor.shared

    struct DraftPage: Identifiable {
        let id = UUID()
        let image: UIImage
        var isAnswerKey = false
    }

    @State private var pages: [DraftPage] = []
    @State private var showScanner = false
    @State private var showPDFImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var title = ""

    var onCreated: (Chapter) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    if DocumentScanner.isSupported {
                        Button { showScanner = true } label: { Label("Scan pages", systemImage: "doc.viewfinder") }
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

                if pages.isEmpty {
                    ContentUnavailableView("No pages yet", systemImage: "book.pages",
                                           description: Text("Scan the textbook pages with the exercises. Add the answer-key pages too if you have them, and mark them below."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            ForEach($pages) { $page in
                                pageCell($page)
                            }
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
                        .disabled(pages.isEmpty || pages.allSatisfy(\.isAnswerKey))
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner(onFinish: { images in
                    pages += images.map { DraftPage(image: $0) }
                    showScanner = false
                }, onCancel: { showScanner = false })
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case let .success(url) = result {
                    pages += PDFPages.images(from: url).map { DraftPage(image: $0) }
                }
            }
            .onChange(of: photoItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            pages.append(DraftPage(image: image))
                        }
                    }
                    photoItems = []
                }
            }
        }
    }

    private func pageCell(_ page: Binding<DraftPage>) -> some View {
        let index = (pages.firstIndex { $0.id == page.wrappedValue.id } ?? 0) + 1
        return VStack(spacing: 6) {
            Image(uiImage: page.wrappedValue.image)
                .resizable()
                .scaledToFit()
                .frame(height: 220)
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

    private func create() {
        let chapter = Chapter(title: title.isEmpty ? "New chapter" : title)
        context.insert(chapter)
        for (i, draft) in pages.enumerated() {
            let data = ImageUtils.jpeg(draft.image, maxEdge: 2400, quality: 0.85) ?? Data()
            let page = PageImage(order: i, imageData: data, isAnswerKey: draft.isAnswerKey)
            page.chapter = chapter
            context.insert(page)
        }
        try? context.save()
        processor.start(chapter, context: context)
        onCreated(chapter)
        dismiss()
    }
}
