import SwiftUI
import SwiftData

struct ChapterHomeView: View {
    let chapter: Chapter
    @State private var practicing = false
    @State private var examining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    bigButton("Practice", subtitle: "30-minute session", icon: "pencil.and.scribble", color: .blue) { practicing = true }
                    bigButton("Exam mode", subtitle: "\(chapter.examMinutes)-minute timed test", icon: "timer", color: .purple) { examining = true }
                }
                .disabled(chapter.activeQuestions.isEmpty)

                if chapter.activeQuestions.isEmpty {
                    Text("No questions are ready yet. Open \"Questions & answers\" below and check the ones Claude wasn't sure about.")
                        .foregroundStyle(.secondary)
                }

                if chapter.status == .processing {
                    ProgressView(value: chapter.progressFraction) {
                        Text("\(chapter.progressMessage). New questions join your practice as they're ready.").font(.caption)
                    }
                }

                reviewLinks

                Text("Your skills").font(.title2.bold())
                MasteryGrid(chapter: chapter)

                let stats = SessionStats(attempts: chapter.allAttempts.filter(\.isGraded))
                if stats.total > 0 {
                    HStack(spacing: 24) {
                        stat("\(stats.total)", "answered")
                        stat("\(Int(stats.accuracy * 100))%", "correct")
                        stat("\(stats.minutes)", "minutes practiced")
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(chapter.title)
        .fullScreenCover(isPresented: $practicing) { PracticeSessionView(chapter: chapter) }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-autoPractice") { practicing = true }
            if ProcessInfo.processInfo.arguments.contains("-autoExam") { examining = true }
        }
        #endif
        .fullScreenCover(isPresented: $examining) { ExamView(chapter: chapter) }
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

    private var reviewLinks: some View {
        let questionsToCheck = chapter.questions.filter { $0.status == .needsCheck }.count
        let gradingsToCheck = chapter.allAttempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
        let toCheck = questionsToCheck + gradingsToCheck
        return HStack(spacing: 12) {
            NavigationLink { ChapterReviewView(chapter: chapter) } label: {
                linkTile("Questions & answers",
                         subtitle: toCheck > 0 ? "\(toCheck) to check" : "Review your answers and the questions",
                         icon: "list.bullet.rectangle", highlight: toCheck > 0)
            }
            NavigationLink { ProgressReportView(chapter: chapter) } label: {
                linkTile("My progress", subtitle: "Mistake patterns, speed, practice days", icon: "chart.bar.xaxis", highlight: false)
            }
        }
        .buttonStyle(.plain)
    }

    private func linkTile(_ title: String, subtitle: String, icon: String, highlight: Bool) -> some View {
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SessionStats {
    let total: Int
    let correct: Int
    let minutes: Int
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }

    init(attempts: [Attempt]) {
        let counted = attempts.filter { $0.effectiveVerdict != .needsReview }
        total = counted.count
        correct = counted.filter { $0.effectiveVerdict == .correct }.count
        minutes = Int(attempts.map(\.activeSeconds).reduce(0, +) / 60)
    }
}

/// Concept × difficulty grid colored by mastery.
struct MasteryGrid: View {
    let chapter: Chapter

    var body: some View {
        let planner = LearningStore.planner(chapter)
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("")
                ForEach(1...3, id: \.self) { d in
                    Text(["Basic", "Medium", "Hard"][d - 1]).font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(chapter.sortedConcepts) { concept in
                GridRow {
                    Text(concept.name).font(.subheadline).lineLimit(2).frame(maxWidth: 260, alignment: .leading)
                    ForEach(1...3, id: \.self) { d in
                        cell(concept: concept, difficulty: d, planner: planner)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(concept: Concept, difficulty: Int, planner: Planner) -> some View {
        let key = CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: difficulty)
        let hasQuestions = concept.questions.contains { $0.difficulty == difficulty && $0.status == .ok }
        if !hasQuestions {
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
