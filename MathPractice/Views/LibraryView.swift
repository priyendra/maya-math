import SwiftUI
import SwiftData

/// Home: a free-form library of folders, study scopes, and chapters.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var chapters: [Chapter]
    @State private var showSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            FolderView(folder: nil)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    }
                }
                .navigationDestination(for: Chapter.self) { ChapterHomeView(chapter: $0) }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear(perform: resume)
        .onChange(of: scenePhase) { _, p in if p == .active { resume() } }
    }

    private func resume() {
        #if DEBUG
        SampleData.seedIfRequested(context: context)
        if ProcessInfo.processInfo.arguments.contains("-openFirstChapter"), path.isEmpty,
           let first = chapters.first(where: { $0.status == .ready }) {
            path.append(first)
        }
        #endif
        ChapterProcessor.shared.resumeInterrupted(chapters, context: context)
        GradingQueue.shared.resumePending(context: context)
    }
}

/// Contents of one folder (nil = top level).
struct FolderView: View {
    let folder: Folder?
    @Environment(\.modelContext) private var context
    @Query(sort: \Chapter.createdAt, order: .reverse) private var allChapters: [Chapter]
    @Query(sort: \StudyScope.createdAt, order: .reverse) private var allScopes: [StudyScope]
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @ObservedObject private var processor = ChapterProcessor.shared

    @State private var showNewChapter = false
    @State private var newScope = false
    @State private var naming: NameTarget?
    @State private var nameText = ""
    @State private var moving: MoveTarget?

    enum NameTarget: Identifiable {
        case newFolder, folder(Folder), chapter(Chapter), scope(StudyScope)
        var id: String {
            switch self {
            case .newFolder: return "new"
            case let .folder(f): return f.id.uuidString
            case let .chapter(c): return c.id.uuidString
            case let .scope(s): return s.id.uuidString
            }
        }
    }

    enum MoveTarget: Identifiable {
        case folder(Folder), chapter(Chapter), scope(StudyScope)
        var id: String {
            switch self {
            case let .folder(f): return f.id.uuidString
            case let .chapter(c): return c.id.uuidString
            case let .scope(s): return s.id.uuidString
            }
        }
    }

    private var folders: [Folder] { allFolders.filter { $0.parent?.id == folder?.id } }
    private var scopes: [StudyScope] { allScopes.filter { $0.folder?.id == folder?.id } }
    private var chapters: [Chapter] { allChapters.filter { $0.folder?.id == folder?.id } }

    var body: some View {
        Group {
            if folders.isEmpty && scopes.isEmpty && chapters.isEmpty {
                ContentUnavailableView {
                    Label(folder == nil ? "Nothing here yet" : "Empty folder", systemImage: "books.vertical")
                } description: {
                    Text("Scan a chapter of your textbook to get started.")
                } actions: {
                    Button("New chapter") { showNewChapter = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if !folders.isEmpty {
                        Section("Folders") {
                            ForEach(folders) { f in
                                NavigationLink { FolderView(folder: f) } label: {
                                    Label(f.name, systemImage: "folder")
                                }
                                .contextMenu { menu(.folder(f), rename: .folder(f), name: f.name) { delete(folder: f) } }
                            }
                        }
                    }
                    if !scopes.isEmpty {
                        Section("Study plans") {
                            ForEach(scopes) { s in
                                NavigationLink { ScopeHomeView(scope: s) } label: { scopeRow(s) }
                                    .contextMenu { menu(.scope(s), rename: .scope(s), name: s.name) { context.delete(s); try? context.save() } }
                            }
                        }
                    }
                    if !chapters.isEmpty {
                        Section("Chapters") {
                            ForEach(chapters) { c in
                                NavigationLink(value: c) { chapterRow(c) }
                                    .disabled(c.activeQuestions.isEmpty && c.status != .ready && !c.needsRereading)
                                    .contextMenu { menu(.chapter(c), rename: .chapter(c), name: c.title) { context.delete(c); try? context.save() } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder?.name ?? "Maya Math")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showNewChapter = true } label: { Label("New chapter", systemImage: "doc.viewfinder") }
                    Button { newScope = true } label: { Label("New study plan", systemImage: "target") }
                    Button { nameText = ""; naming = .newFolder } label: { Label("New folder", systemImage: "folder.badge.plus") }
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNewChapter) {
            NewChapterView { chapter in chapter.folder = folder; try? context.save() }
        }
        .sheet(isPresented: $newScope) { ScopeEditorView(scope: nil, folder: folder) }
        .sheet(item: $moving) { target in MoveSheet(target: target) }
        .alert(alertTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Save") { saveName() }
            Button("Cancel", role: .cancel) { naming = nil }
        }
    }

    private var alertTitle: String {
        if case .newFolder = naming { return "New folder" }
        return "Rename"
    }

    @ViewBuilder
    private func menu(_ move: MoveTarget, rename: NameTarget, name: String, delete: @escaping () -> Void) -> some View {
        Button { nameText = name; naming = rename } label: { Label("Rename", systemImage: "pencil") }
        Button { moving = move } label: { Label("Move to…", systemImage: "folder") }
        Button(role: .destructive, action: delete) { Label("Delete", systemImage: "trash") }
    }

    private func saveName() {
        let name = nameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let target = naming else { naming = nil; return }
        switch target {
        case .newFolder: context.insert(Folder(name: name, parent: folder))
        case let .folder(f): f.name = name
        case let .chapter(c): c.title = name
        case let .scope(s): s.name = name
        }
        try? context.save()
        naming = nil
    }

    /// Deleting a folder keeps its contents: they move up one level.
    private func delete(folder f: Folder) {
        for c in f.chapters { c.folder = f.parent }
        for s in f.scopes { s.folder = f.parent }
        for child in f.children { child.parent = f.parent }
        context.delete(f)
        try? context.save()
    }

    private func scopeRow(_ s: StudyScope) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(s.name, systemImage: "target").font(.title3.weight(.semibold))
            if let date = s.testDate { Text(ScopeHomeView.countdown(to: date)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func chapterRow(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chapter.title).font(.title3.weight(.semibold))
            switch chapter.status {
            case .processing:
                ProgressView(value: chapter.progressFraction) { Text(chapter.progressMessage).font(.caption) }
                if !processor.isRunning(chapter) {
                    Text("Paused — keep the app open to continue.").font(.caption2).foregroundStyle(.secondary)
                }
            case .failed:
                HStack {
                    Text(chapter.errorMessage ?? "Something went wrong.").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { processor.start(chapter, context: context) }.buttonStyle(.bordered)
                    ReportProblemButton(subject: .chapter(chapter)).buttonStyle(.bordered)
                }
            case .ready:
                if chapter.needsRereading {
                    Text("Ready to re-read with the new reader").font(.caption).foregroundStyle(.orange)
                } else {
                    let excluded = chapter.questions.filter { !$0.isIncluded }.count
                    Text("\(chapter.activeQuestions.count) questions · \(chapter.concepts.count) concepts"
                         + (excluded > 0 ? " · \(excluded) not doable with a pencil" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Pick a destination folder.
struct MoveSheet: View {
    let target: FolderView.MoveTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]

    var body: some View {
        NavigationStack {
            List {
                Button { move(to: nil) } label: { Label("Top level", systemImage: "house") }
                ForEach(folders.filter(allowed)) { f in
                    Button { move(to: f) } label: { Label(pathName(f), systemImage: "folder") }
                }
            }
            .navigationTitle("Move to")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func pathName(_ f: Folder) -> String {
        var names = [f.name]; var cur = f.parent
        while let c = cur { names.insert(c.name, at: 0); cur = c.parent }
        return names.joined(separator: " / ")
    }

    /// A folder can't move into itself or its own subfolders.
    private func allowed(_ f: Folder) -> Bool {
        guard case let .folder(moving) = target else { return true }
        var cur: Folder? = f
        while let c = cur { if c.id == moving.id { return false }; cur = c.parent }
        return true
    }

    private func move(to folder: Folder?) {
        switch target {
        case let .folder(f): f.parent = folder
        case let .chapter(c): c.folder = folder
        case let .scope(s): s.folder = folder
        }
        try? context.save()
        dismiss()
    }
}
