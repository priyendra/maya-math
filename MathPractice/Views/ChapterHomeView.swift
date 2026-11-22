import SwiftUI
import SwiftData

/// Big Practice / Exam buttons plus links, for a chapter or a scope.
struct StudyActions: View {
    let set: StudySet
    @State private var practicing = false
    @State private var examining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                bigButton("Practice", subtitle: "30-minute session", icon: "pencil.and.scribble", color: .blue) { practicing = true }
                bigButton("Exam mode", subtitle: "\(set.examMinutes)-minute timed test", icon: "timer", color: .purple) { examining = true }
            }
            .disabled(set.questions.isEmpty)
            if set.questions.isEmpty {
                Text("There are no questions here yet.").foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $practicing) { PracticeSessionView(set: set) }
        .fullScreenCover(isPresented: $examining) { ExamView(set: set) }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-autoPractice") { practicing = true }
            if ProcessInfo.processInfo.arguments.contains("-autoExam") { examining = true }
        }
        #endif
    }

    private func bigButton(_ title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 36))
                VStack(alignment: .leading) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.subheadline).opacity(0.85)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct LinkTile: View {
    let title: String
    let subtitle: String
    let icon: String
    var highlight = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(highlight ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(highlight ? .orange : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ChapterHomeView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @ObservedObject private var processor = ChapterProcessor.shared
    @State private var showSettings = false
    @State private var confirmReread = false
    @State private var debugRead = false
    @State private var debugLessons = false

    var body: some View {
        let set = StudySet.chapter(chapter)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if chapter.needsRereading && chapter.status != .processing && chapter.status != .needsRescan {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("New: a clean digital version of this chapter", systemImage: "sparkles").font(.headline)
                        Text("Re-read this chapter from the pages you already scanned (no rescanning) to get the browsable chapter, sections and page numbers for study plans, and smarter question tags. It takes about 10–15 minutes; keep the app open.")
                            .font(.subheadline)
                        Button("Re-read chapter") { confirmReread = true }.buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                if chapter.status == .processing {
                    ProgressView(value: chapter.progressFraction) { Text(chapter.progressMessage).font(.caption) }
                }
                if chapter.status == .needsRescan {
                    ScanFixCard(chapter: chapter)
                } else if let warning = chapter.pageWarning {
                    Label("Check your scans: \(warning)", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                }

                if chapter.status == .ready && !chapter.needsRereading {
                    StudyActions(set: set)
                }

                HStack(spacing: 12) {
                    if chapter.status == .ready && !chapter.needsRereading && !chapter.blocks.isEmpty {
                        NavigationLink { LessonsView(chapter: chapter) } label: {
                            let done = chapter.lessons.filter { $0.status == .done }.count
                            LinkTile(title: "Lessons",
                                     subtitle: chapter.lessons.isEmpty ? "Learn it step by step with a tutor" : "\(done) of \(chapter.lessons.count) done",
                                     icon: "graduationcap")
                        }
                        .accessibilityIdentifier("lessonsTile")
                    }
                    if !chapter.needsRereading && !chapter.blocks.isEmpty {
                        NavigationLink { ReadChapterView(chapter: chapter) } label: {
                            LinkTile(title: "Read chapter", subtitle: "The book, section by section", icon: "book")
                        }
                    }
                    NavigationLink { MyAnswersView(set: set) } label: {
                        let toCheck = set.allAttempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
                        LinkTile(title: "My answers", subtitle: toCheck > 0 ? "\(toCheck) to check" : "Your work and how it was graded",
                                 icon: "list.bullet.rectangle", highlight: toCheck > 0)
                    }
                    NavigationLink { ProgressReportView(chapter: chapter) } label: {
                        LinkTile(title: "My progress", subtitle: "Mistake patterns, speed, practice days", icon: "chart.bar.xaxis")
                    }
                }
                .buttonStyle(.plain)

                if !chapter.needsRereading {
                    Text("Your skills").font(.title2.bold())
                    MasteryGrid(set: set)
                    let stats = SessionStats(attempts: set.allAttempts.filter(\.isGraded))
                    if stats.total > 0 {
                        HStack(spacing: 24) {
                            stat("\(stats.total)", "answered")
                            stat("\(Int(stats.accuracy * 100))%", "correct")
                            stat("\(stats.minutes)", "minutes practiced")
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(chapter.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("Chapter settings", systemImage: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showSettings) { ChapterSettingsView(chapter: chapter) }
        .navigationDestination(isPresented: $debugRead) { ReadChapterView(chapter: chapter) }
        .navigationDestination(isPresented: $debugLessons) { LessonsView(chapter: chapter) }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openRead") { debugRead = true }
            if ProcessInfo.processInfo.arguments.contains("-openLessons") { debugLessons = true }
        }
        #endif
        .alert("Re-read this chapter?", isPresented: $confirmReread) {
            Button("Cancel", role: .cancel) {}
            Button("Re-read", role: .destructive) { processor.reread(chapter, context: context) }
        } message: {
            Text("Questions are rebuilt from your scanned pages, so any practice history in this chapter is cleared.")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ChapterSettingsView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var processor = ChapterProcessor.shared
    @State private var confirmReread = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $chapter.title)
                    Stepper("Exam length: \(chapter.examMinutes) min", value: $chapter.examMinutes, in: 5...120, step: 5)
                }
                Section {
                    LabeledContent("Pages", value: "\(chapter.pages.count)")
                    let printed = chapter.sortedPages.compactMap(\.printedPageNumber)
                    if let first = printed.min(), let last = printed.max() {
                        LabeledContent("Book pages", value: "\(first)–\(last)")
                    }
                    if let warning = chapter.pageWarning { Text(warning).foregroundStyle(.orange) }
                }
                Section {
                    Button("Re-read chapter from scanned pages", role: .destructive) { confirmReread = true }
                        .disabled(processor.isRunning(chapter))
                } footer: {
                    Text("Rebuilds the digital chapter and its questions from the pages you scanned. Practice history for this chapter is cleared.")
                }
                Section {
                    Button("Clear practice history", role: .destructive) { confirmClear = true }
                        .disabled(processor.isRunning(chapter))
                } footer: {
                    Text("Start this chapter fresh: removes your answers, tutor talks, practice tests, skill progress and lesson progress. The scanned chapter, its questions and lessons stay.")
                }
                Section { ReportProblemButton(subject: .chapter(chapter)) }
            }
            .navigationTitle("Chapter settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { try? context.save(); dismiss() } } }
            .alert("Clear practice history?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { processor.clearPracticeHistory(chapter, context: context); dismiss() }
            } message: {
                let n = chapter.allAttempts.count
                Text("\(n) answer\(n == 1 ? "" : "s") and all progress in this chapter will be removed. This can't be undone.")
            }
            .alert("Re-read this chapter?", isPresented: $confirmReread) {
                Button("Cancel", role: .cancel) {}
                Button("Re-read", role: .destructive) { processor.reread(chapter, context: context); dismiss() }
            } message: {
                Text("Questions are rebuilt from your scanned pages, so any practice history in this chapter is cleared.")
            }
        }
    }
}

struct SessionStats {
    let total: Int
    let correct: Int
    let minutes: Int
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }

    /// Wrong answers on challenge questions don't count against her.
    init(attempts: [Attempt]) {
        let counted = attempts.filter {
            $0.effectiveVerdict != .needsReview && !($0.question?.isChallenge == true && $0.effectiveVerdict == .incorrect)
        }
        total = counted.count
        correct = counted.filter { $0.effectiveVerdict == .correct }.count
        minutes = Int(attempts.map(\.activeSeconds).reduce(0, +) / 60)
    }
}

/// Concept × difficulty grid colored by mastery, for a chapter or scope.
struct MasteryGrid: View {
    let set: StudySet

    init(set: StudySet) { self.set = set }
    init(chapter: Chapter) { self.set = .chapter(chapter) }

    private var concepts: [Concept] {
        var seen = Set<UUID>(); var out: [Concept] = []
        let chapterOrder = Dictionary(uniqueKeysWithValues: set.chapters.enumerated().map { ($1.id, $0) })
        for q in set.questions where !q.isChallenge {
            if let c = q.concept, seen.insert(c.id).inserted { out.append(c) }
        }
        return out.sorted { (chapterOrder[$0.chapter?.id ?? UUID()] ?? 0, $0.bookOrder) < (chapterOrder[$1.chapter?.id ?? UUID()] ?? 0, $1.bookOrder) }
    }

    var body: some View {
        let planner = LearningStore.planner(set)
        let present = Set(set.questions.filter { !$0.isChallenge }.compactMap { q in q.concept.map { "\($0.id)|\(q.difficulty)" } })
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("")
                ForEach(1...3, id: \.self) { d in
                    Text(["Basic", "Medium", "Hard"][d - 1]).font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(concepts) { concept in
                GridRow {
                    Text(concept.name).font(.subheadline).lineLimit(2).frame(maxWidth: 260, alignment: .leading)
                    ForEach(1...3, id: \.self) { d in
                        cell(concept: concept, difficulty: d, planner: planner, has: present.contains("\(concept.id)|\(d)"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(concept: Concept, difficulty: Int, planner: Planner, has: Bool) -> some View {
        let key = CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: difficulty)
        if !has {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)).frame(height: 44)
        } else {
            let p = planner.progress(key)
            let mastered = planner.isMastered(key)
            let open = planner.isOpen(key)
            RoundedRectangle(cornerRadius: 8)
                .fill(open ? Self.color(p.mastery, attempted: p.attemptCount > 0) : Color.secondary.opacity(0.15))
                .frame(height: 44)
                .overlay {
                    if !open { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    else if mastered { Image(systemName: "star.fill").foregroundStyle(.white) }
                    else if p.attemptCount > 0 { Text("\(Int(p.mastery * 100))%").font(.caption.bold()).foregroundStyle(.white) }
                }
        }
    }

    static func color(_ mastery: Double, attempted: Bool) -> Color {
        guard attempted else { return Color.blue.opacity(0.25) }
        switch mastery {
        case ..<0.3: return .red.opacity(0.75)
        case ..<0.6: return .orange
        case ..<0.8: return .yellow.opacity(0.9)
        default: return .green
        }
    }
}
