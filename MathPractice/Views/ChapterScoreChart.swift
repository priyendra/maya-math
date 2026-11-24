import SwiftUI
import Charts

/// mastery points over practice time, toward 100.
struct ChapterScoreChart: View {
    let set: StudySet
    @Environment(\.theme) private var theme

    var body: some View {
        let planner = LearningStore.planner(set)
        let cells = planner.allCells
        // Every answer's time counts as practice time (as in the line below the chart); only graded ones move the score.
        let answers: [ChapterScore.Answer] = zip(set.allAttempts, set.cleanSeconds).map { a, seconds in
            var cell: CellKey?
            if let q = a.question, !q.isChallenge, a.isGraded, a.effectiveVerdict != .needsReview,
               a.hintText.isEmpty || a.wasStuck { cell = LearningStore.cellKey(q) }
            return .init(date: a.startedAt, cell: cell, correct: a.effectiveVerdict == .correct, mistake: a.mistakeType, seconds: seconds)
        }
        let points = ChapterScore.history(answers, cells: cells)
        let now = ChapterScore.score(planner.skills, cells: cells)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let practisedToday = answers.contains { $0.date >= startOfToday && $0.cell != nil }
        let before: Double? = practisedToday
            ? ChapterScore.score(answers, cells: cells, before: startOfToday) : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(now.rounded()))").font(.system(size: 34, weight: .bold, design: theme.design).monospacedDigit())
                Text("of 100 mastery points").font(theme.font(.label)).foregroundStyle(.secondary)
                if practisedToday, let before {
                    let delta = Int(now.rounded()) - Int(before.rounded())
                    Text(delta >= 0 ? "+\(delta) today" : "\(delta) today")
                        .font(theme.font(.label).weight(.semibold))
                        .foregroundStyle(delta >= 0 ? theme.done : theme.notQuite)
                }
                Spacer()
            }
            if points.count > 1 {
                let maxHours = max(1, (points.last!.hours * 1.15).rounded(.up))
                Chart {
                    RuleMark(y: .value("Mastery", 100))
                        .foregroundStyle(theme.done)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .bottom, alignment: .leading) {
                            Text("100 = every skill mastered").font(theme.font(.caption)).foregroundStyle(theme.done)
                        }
                    ForEach(points) { p in
                        AreaMark(x: .value("Practice", p.hours), y: .value("Points", p.score))
                            .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.28), theme.accent.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Practice", p.hours), y: .value("Points", p.score))
                            .foregroundStyle(theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: 0...maxHours)
                .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0)") } } }
                .chartXAxis {
                    AxisMarks(values: .stride(by: maxHours > 8 ? 1 : 0.5)) { v in
                        AxisValueLabel { Text(Self.hoursLabel(v.as(Double.self) ?? 0)) }
                    }
                }
                .chartXAxisLabel("Practice time", alignment: .center)
                .frame(height: 200)
            }
        }
    }

    static func hoursLabel(_ h: Double) -> String {
        if h == 0 { return "0" }
        let m = Int((h * 60).rounded())
        return m % 60 == 0 ? "\(m / 60) h" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60)"
    }
}
