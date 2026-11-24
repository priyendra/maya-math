import SwiftUI
import SwiftData

/// Big Practice / Exam buttons plus links, for a chapter or a scope.
struct StudyActions: View {
    let set: StudySet
    @Environment(\.theme) private var theme
    @State private var practicing = false
    @State private var examining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                bigButton("Practice", subtitle: "30-minute session", icon: "pencil.and.scribble", color: theme.accent) { practicing = true }
                bigButton("Exam mode", subtitle: "\(set.examMinutes)-minute timed test", icon: "timer", color: theme.accent2) { examining = true }
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
                    Text(title).font(theme.font(.section))
                    Text(subtitle).font(theme.font(.label)).opacity(0.9)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(theme.fill(color), in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .shadow(color: theme.shadow ? color.opacity(0.3) : .clear, radius: 10, y: 5)
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
    var color: Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let c = highlight ? theme.attention : (color ?? theme.accent)
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(c)
                .frame(width: 44, height: 44)
                .background(c.opacity(0.13), in: RoundedRectangle(cornerRadius: theme.radius * 0.55, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(theme.font(.cardTitle)).foregroundStyle(.primary)
                Text(subtitle).font(theme.font(.caption)).foregroundStyle(highlight ? theme.attention : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .card(theme)
    }
}

struct ChapterHomeView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
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

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    if chapter.status == .ready && !chapter.needsRereading && !chapter.blocks.isEmpty {
                        NavigationLink { LessonsView(chapter: chapter) } label: {
                            let done = chapter.lessons.filter { $0.status == .done }.count
                            LinkTile(title: "Lessons",
                                     subtitle: chapter.lessons.isEmpty ? "Learn it step by step with a tutor" : "\(done) of \(chapter.lessons.count) done",
                                     icon: "graduationcap.fill", color: theme.learn)
                        }
                        .accessibilityIdentifier("lessonsTile")
                    }
                    if !chapter.needsRereading && !chapter.blocks.isEmpty {
                        NavigationLink { ReadChapterView(chapter: chapter) } label: {
                            LinkTile(title: "Read chapter", subtitle: "The book, section by section", icon: "book.fill", color: theme.accent2)
                        }
                    }
                    NavigationLink { MyAnswersView(set: set) } label: {
                        let toCheck = set.allAttempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
                        LinkTile(title: "My answers", subtitle: toCheck > 0 ? "\(toCheck) to check" : "Your work and how it was graded",
                                 icon: "list.bullet.rectangle.fill", highlight: toCheck > 0, color: theme.board)
                    }
                    NavigationLink { ProgressReportView(chapter: chapter) } label: {
                        LinkTile(title: "My progress", subtitle: "Mistake patterns, speed, practice days", icon: "chart.bar.fill", color: theme.done)
                    }
                }
                .buttonStyle(.plain)

                if !chapter.needsRereading {
                    PathGlance(chapter: chapter)
                        .padding(20)
                        .card(theme)
                }
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .themedBackground(theme)
        .navigationTitle(MathPlain.render(chapter.title))
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
    @Environment(\.theme) private var theme

    init(set: StudySet) { self.set = set }
    init(chapter: Chapter) { self.set = .chapter(chapter) }

    private var concepts: [Concept] { Self.concepts(set) }

    static func concepts(_ set: StudySet) -> [Concept] {
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
                    Text(Self.levels[d - 1]).font(theme.font(.label)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(concepts) { concept in
                GridRow {
                    Text(MathPlain.render(concept.name)).font(theme.font(.body)).lineLimit(2).frame(maxWidth: 280, alignment: .leading)
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
        let r = min(theme.radius * 0.5, 10)
        if !has {
            RoundedRectangle(cornerRadius: r).strokeBorder(Color.secondary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 46)
                .accessibilityLabel("No \(Self.levels[difficulty - 1]) questions")
        } else {
            let open = planner.isOpen(key)
            let look = SkillCellLook(progress: planner.progress(key), mastered: planner.isMastered(key), estimate: planner.estimate(key))
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(open ? theme.skillColor(look.stage) : Color.secondary.opacity(0.13))
                .frame(height: 46)
                .overlay {
                    if !open {
                        // Locked again after the level below dipped: keep her earlier work visible.
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                            if planner.progress(key).attemptCount > 0 { SkillDots(filled: look.dots, color: .secondary) }
                        }
                        .foregroundStyle(.secondary)
                    }
                    else { SkillCellContent(look: look) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(MathPlain.render(concept.name)), \(Self.levels[difficulty - 1]): \(open ? look.spoken : look.stage == .new ? "Locked" : "Locked until the level below is Almost; \(look.dots) of 5 steps")")
        }
    }

    static let levels = ["Basic", "Medium", "Hard"]
}
