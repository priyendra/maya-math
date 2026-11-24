import SwiftUI

/// "One path per skill" views (My progress) and the chapter page's progress summary.

/// Blocks for one concept: a stretch of 5 per level, small gap between levels, ★ at the end.
struct ConceptPathBar: View {
    let path: ConceptPath
    var blockHeight: CGFloat = 16
    @Environment(\.theme) private var theme

    var body: some View {
        let fill = path.mastered ? theme.done : theme.accent
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(path.levels, id: \.difficulty) { level in
                    HStack(spacing: 2) {
                        ForEach(0..<MasteryModel.steps, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(i < level.filled ? fill : Color.secondary.opacity(level.open ? 0.18 : 0.09))
                                .frame(height: blockHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Image(systemName: path.mastered ? "star.fill" : "star")
                .font(.system(size: blockHeight, weight: .semibold))
                .foregroundStyle(path.mastered ? theme.done : Color.secondary.opacity(0.35))
                .overlay(alignment: .bottomTrailing) {
                    if path.slow { Image(systemName: "timer").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.attention).offset(x: 6, y: 4) }
                }
        }
    }
}

/// My progress: one row per concept.
struct ConceptPathList: View {
    let set: StudySet
    @Environment(\.theme) private var theme

    var body: some View {
        let planner = LearningStore.planner(set)
        VStack(spacing: 14) {
            ForEach(MasteryGrid.concepts(set)) { c in
                let path = ConceptPath(conceptID: c.id, conceptOrder: c.bookOrder, planner: planner)
                HStack(alignment: .center, spacing: 16) {
                    Text(MathPlain.render(c.name)).font(theme.font(.body)).lineLimit(2)
                        .frame(width: 250, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ConceptPathBar(path: path)
                        Text(path.status).font(theme.font(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(MathPlain.render(c.name)): \(path.status)")
            }
        }
    }
}

/// Chapter page: mastery points chart and one line of practice numbers.
struct PathGlance: View {
    let chapter: Chapter
    @Environment(\.theme) private var theme

    var body: some View {
        let set = StudySet.chapter(chapter)
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress summary").font(theme.font(.section))
            ChapterScoreChart(set: set)
            PracticeLine(set: set)
        }
    }
}

/// One quiet line under the chart: answered · right · practice time, plus "answers to check".
struct PracticeLine: View {
    let set: StudySet
    @Environment(\.theme) private var theme

    var body: some View {
        let attempts = set.allAttempts
        let counted = attempts.filter { $0.isGraded && $0.effectiveVerdict != .needsReview && !($0.question?.isChallenge == true && $0.effectiveVerdict == .incorrect) }
        let today = counted.filter { Calendar.current.isDateInToday($0.startedAt) }
        let right = counted.filter { $0.effectiveVerdict == .correct }.count
        let rightToday = today.filter { $0.effectiveVerdict == .correct }.count
        let toCheck = attempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
        let seconds = attempts.map(\.activeSeconds).reduce(0, +)
        HStack(spacing: 18) {
            if !counted.isEmpty {
                stat("\(counted.count)", today.isEmpty ? "answered" : "answered (\(today.count) today)")
                stat(ProgressSummaryBar.percent(Double(right) / Double(counted.count)),
                     today.isEmpty ? "right" : "right (\(ProgressSummaryBar.percent(Double(rightToday) / Double(today.count))) today)")
                stat(ProgressSummaryBar.duration(seconds), "practice")
            }
            Spacer()
            if toCheck > 0 {
                NavigationLink { MyAnswersView(set: set) } label: {
                    Label(toCheck == 1 ? "1 answer to check" : "\(toCheck) answers to check", systemImage: "questionmark.circle.fill")
                        .font(theme.font(.label)).foregroundStyle(theme.attention)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        (Text(value).font(theme.font(.label).weight(.semibold)) + Text(" " + label).font(theme.font(.label)).foregroundColor(.secondary))
    }
}


/// Answered · right · skills mastered (+ how many are on their last level), and answers to check.
struct PathSummaryBar: View {
    let set: StudySet
    let paths: [ConceptPath]
    var full = false
    @Environment(\.theme) private var theme

    var body: some View {
        let attempts = set.allAttempts
        let counted = attempts.filter { $0.isGraded && $0.effectiveVerdict != .needsReview && !($0.question?.isChallenge == true && $0.effectiveVerdict == .incorrect) }
        let today = counted.filter { Calendar.current.isDateInToday($0.startedAt) }
        let right = counted.filter { $0.effectiveVerdict == .correct }.count
        let rightToday = today.filter { $0.effectiveVerdict == .correct }.count
        let toCheck = attempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
        let mastered = paths.filter(\.mastered).count
        let onTop = paths.filter { !$0.mastered && $0.isOnTopLevel && $0.attempted }.count
        let seconds = attempts.map(\.activeSeconds).reduce(0, +)
        let days = Set(attempts.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                tile("\(counted.count)", today.isEmpty ? "answered" : "answered · \(today.count) today")
                if !counted.isEmpty {
                    tile(ProgressSummaryBar.percent(Double(right) / Double(counted.count)),
                         today.isEmpty ? "right" : "right · \(ProgressSummaryBar.percent(Double(rightToday) / Double(today.count))) today")
                }
                if full { tile(ProgressSummaryBar.duration(seconds), days == 1 ? "practice · 1 day" : "practice · \(days) days") }
                tile("\(mastered) of \(paths.count)", "skills mastered · \(onTop) on the last level", icon: "star.fill")
            }
            if toCheck > 0 {
                NavigationLink { MyAnswersView(set: set) } label: {
                    Label(toCheck == 1 ? "1 answer to check" : "\(toCheck) answers to check", systemImage: "questionmark.circle.fill")
                        .font(theme.font(.label)).foregroundStyle(theme.attention)
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary) }
                Text(value).font(.system(size: 24, weight: .bold, design: theme.design).monospacedDigit())
            }
            Text(label).font(theme.font(.caption)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: min(theme.radius * 0.6, 10), style: .continuous))
    }
}

/// My progress: numbers, one path per skill, short key.
struct PathPanel: View {
    let set: StudySet
    @Environment(\.theme) private var theme

    var body: some View {
        let planner = LearningStore.planner(set)
        let paths = MasteryGrid.concepts(set).map { ConceptPath(conceptID: $0.id, conceptOrder: $0.bookOrder, planner: planner) }
        VStack(alignment: .leading, spacing: 18) {
            Text("Your skills").font(theme.font(.section))
            PathSummaryBar(set: set, paths: paths, full: true)
            ConceptPathList(set: set)
            Text("Each skill is a path: Basic, then Medium, then Hard. Each right answer fills a step; reach three steps on a level to open the next. Master the last level for the ★.")
                .font(theme.font(.caption)).foregroundStyle(.secondary)
        }
    }
}
