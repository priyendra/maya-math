import SwiftUI
import SwiftData

struct ChapterListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Chapter.createdAt, order: .reverse) private var chapters: [Chapter]
    @ObservedObject private var processor = ChapterProcessor.shared
    @State private var showNewChapter = false
    @State private var showSettings = false
    @State private var path: [Chapter] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView {
                        Label("No chapters yet", systemImage: "books.vertical")
                    } description: {
                        Text("Scan some textbook pages to create your first chapter.")
                    } actions: {
                        Button("New chapter") { showNewChapter = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(chapters) { chapter in
                            NavigationLink(value: chapter) { row(chapter) }
                                .disabled(chapter.status != .ready)
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        context.delete(chapter)
                                        try? context.save()
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationDestination(for: Chapter.self) { ChapterHomeView(chapter: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewChapter = true } label: { Label("New chapter", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showNewChapter) { NewChapterView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear(perform: resumeInterrupted)
        }
    }

    @ViewBuilder
    private func row(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chapter.title).font(.title3.weight(.semibold))
            switch chapter.status {
            case .processing:
                ProgressView(value: chapter.progressFraction) { Text(chapter.progressMessage).font(.caption) }
            case .failed:
                HStack {
                    Text(chapter.errorMessage ?? "Something went wrong.").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { processor.start(chapter, context: context) }.buttonStyle(.bordered)
                    ReportProblemButton(subject: .chapter(chapter)).buttonStyle(.bordered)
                }
            case .ready:
                let review = chapter.questions.filter { $0.status == .needsCheck }.count
                Text("\(chapter.activeQuestions.count) questions · \(chapter.concepts.count) concepts"
                     + (review > 0 ? " · \(review) to check" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// Chapters left "processing" when the app was closed resume where they stopped.
    private func resumeInterrupted() {
        #if DEBUG
        SampleData.seedIfRequested(context: context)
        if ProcessInfo.processInfo.arguments.contains("-openFirstChapter"), path.isEmpty,
           let first = chapters.first(where: { $0.status == .ready }) {
            path = [first]
        }
        #endif
        for chapter in chapters where chapter.status == .processing && !processor.isRunning(chapter) {
            processor.start(chapter, context: context)
        }
    }
}
