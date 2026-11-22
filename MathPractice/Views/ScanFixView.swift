import SwiftUI
import SwiftData
import PhotosUI

/// After the pages are read: what to scan again, in words a kid can follow, with a one-tap fix for each.
struct ScanFixCard: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @ObservedObject private var processor = ChapterProcessor.shared

    /// What the next scan is for.
    enum Fix: Identifiable {
        case replace(PageImage), fillGap(after: PageImage?)
        var id: String {
            switch self {
            case let .replace(p): return "r\(p.id)"
            case let .fillGap(a): return "g\(a?.id.uuidString ?? "start")"
            }
        }
    }

    @State private var fixing: Fix?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var stillBad: (fix: Fix, pages: [ScannedPage])?
    @State private var zoom: PageImage?

    var body: some View {
        let issues = ScanReport.issues(chapter)
        let pending = ScanReport.pendingCount(chapter)
        let running = processor.isRunning(chapter)
        VStack(alignment: .leading, spacing: 16) {
            Label("Some pages need another scan", systemImage: "doc.viewfinder").font(.title2.bold()).foregroundStyle(.orange)
            Text("Fix the pages below, then tap **Check again**. Lay the book flat in a bright spot, fit the whole page in the frame, and hold still until it takes the picture.")
                .font(.body)
            ForEach(issues) { issue in row(issue) }
            if pending > 0 {
                Label("\(pending) new page\(pending == 1 ? "" : "s") ready to check", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green)
            }
            HStack(spacing: 12) {
                Button { processor.start(chapter, context: context) } label: {
                    Label(running ? "Checking…" : "Check again", systemImage: "arrow.clockwise").font(.headline)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(pending == 0 || running)
                Button("Continue anyway") { processor.continueAnyway(chapter, context: context) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(running)
            }
            Text("Continue anyway builds the chapter now. Questions on pages that couldn't be read may be missing or wrong.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        // One page: the retake sheet (which page to turn to, a single photo).
        .sheet(item: Binding(get: { if case .replace = fixing { return fixing } else { return nil } }, set: { fixing = $0 })) { fix in
            if case let .replace(page) = fix {
                RetakeSheet(pageLabel: page.printedPageNumber.map { "page \($0)" },
                            thumbnail: UIImage(data: page.imageData)?.preparingThumbnail(of: CGSize(width: 420, height: 560)),
                            advice: nil,
                            onPicked: { image in fixing = nil; received([image], for: fix) },
                            onCancel: { fixing = nil })
            }
        }
        // Missing pages (maybe several): the document scanner.
        .fullScreenCover(item: Binding(get: { if case .fillGap = fixing, DocumentScanner.isSupported { return fixing } else { return nil } },
                                       set: { fixing = $0 })) { fix in
            DocumentScanner(onFinish: { images in fixing = nil; received(images, for: fix) }, onCancel: { fixing = nil })
                .ignoresSafeArea()
        }
        // Without a camera scanner (simulator), pick photos instead.
        .photosPicker(isPresented: Binding(get: { if case .fillGap = fixing { return !DocumentScanner.isSupported } else { return false } },
                                           set: { if !$0 && pickerItems.isEmpty { fixing = nil } }),
                      selection: $pickerItems, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty, let fix = fixing else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { images.append(img) }
                }
                pickerItems = []
                fixing = nil
                received(images, for: fix)
            }
        }
        .alert("This one still needs another try",
               isPresented: Binding(get: { stillBad != nil }, set: { if !$0 { stillBad = nil } })) {
            Button("Try again", role: .cancel) { if let f = stillBad?.fix { stillBad = nil; fixing = f } }
            Button("Use it anyway") { if let s = stillBad { stillBad = nil; apply(s.pages, for: s.fix) } }
        } message: {
            Text(stillBad?.pages.first(where: { !$0.issues.isEmpty })?.issues.first?.advice ?? "")
        }
        .sheet(item: $zoom) { p in
            if let img = UIImage(data: p.imageData) { Image(uiImage: img).resizable().scaledToFit().padding() }
        }
    }

    // MARK: Rows

    @ViewBuilder private func row(_ issue: ScanIssue) -> some View {
        HStack(alignment: .center, spacing: 16) {
            switch issue.kind {
            case let .badPage(page, details):
                thumb(page)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name(page)).font(.headline)
                    ForEach(details, id: \.self) { Text($0).font(.subheadline) }
                }
                Spacer()
                Button { fixing = .replace(page) } label: { Label("Scan again", systemImage: "camera") }
                    .buttonStyle(.borderedProminent).tint(.orange)
            case let .missing(from, to, after):
                Image(systemName: "doc.badge.plus").font(.system(size: 34)).foregroundStyle(.orange).frame(width: 64)
                let label = from == to ? "Page \(from)" : "Pages \(from)–\(to)"
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(label) \(from == to ? "is" : "are") missing").font(.headline)
                    Text("Find \(from == to ? "it" : "them") in the book and scan \(from == to ? "it" : "them").").font(.subheadline)
                }
                Spacer()
                if ScanReport.gapFilled(after: after, in: chapter) {
                    Label("Scanned", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button { fixing = .fillGap(after: after) } label: { Label("Scan \(label.lowercased())", systemImage: "camera") }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
            case let .duplicate(number, extra):
                thumb(extra)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(number) was scanned twice").font(.headline)
                    Text("The extra copy can go.").font(.subheadline)
                }
                Spacer()
                Button { processor.removePage(extra, from: chapter, context: context) } label: {
                    Label("Remove extra copy", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func thumb(_ page: PageImage) -> some View {
        Group {
            if let img = UIImage(data: page.imageData)?.preparingThumbnail(of: CGSize(width: 128, height: 170)) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "doc")
            }
        }
        .frame(width: 64, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture { zoom = page }
    }

    private func name(_ page: PageImage) -> String {
        if let n = page.printedPageNumber { return "Page \(n)" }
        let i = (chapter.sortedPages.firstIndex { $0.id == page.id } ?? 0) + 1
        return "Scan \(i)\(page.isAnswerKey ? " (answer page)" : "")"
    }

    // MARK: Applying a fix

    private func received(_ images: [UIImage], for fix: Fix) {
        guard !images.isEmpty else { return }
        Task {
            let scanned = await ScannedPage.process(images)
            guard !scanned.isEmpty else { return }
            if scanned.contains(where: { !$0.issues.isEmpty }) { stillBad = (fix, scanned) } else { apply(scanned, for: fix) }
        }
    }

    private func apply(_ pages: [ScannedPage], for fix: Fix) {
        switch fix {
        case let .replace(page):
            processor.replacePage(page, with: pages[0].jpeg, context: context)
            if pages.count > 1 { processor.insertPages(pages.dropFirst().map(\.jpeg), after: page, in: chapter, context: context) }
        case let .fillGap(after):
            processor.insertPages(pages.map(\.jpeg), after: after, in: chapter, context: context)
        }
    }
}
