import SwiftUI
import Charts

/// Your progress: mastery grid, mistake patterns, speed, and daily activity.
struct ProgressReportView: View {
    let chapter: Chapter

    private var graded: [Attempt] {
        chapter.allAttempts.filter { $0.isGraded && $0.effectiveVerdict != .needsReview }.sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        let graded = self.graded
        let mistakes = graded.compactMap { $0.effectiveVerdict == .incorrect ? $0.mistakeType : nil }
        let exams = chapter.exams.filter { $0.finishedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        return List {
            Section("Your skills") {
                MasteryGrid(chapter: chapter).padding(.vertical)
            }
            if !mistakes.isEmpty {
                Section("Mistake types") { MistakeChart(mistakes: mistakes) }
            }
            Section("Per concept") {
                ForEach(chapter.sortedConcepts) { concept in
                    ConceptStatsRow(concept: concept, attempts: graded.filter { $0.question?.concept?.id == concept.id })
                }
            }
            if !graded.isEmpty {
                Section("Daily practice") { DailyChart(attempts: graded) }
            }
            if !exams.isEmpty {
                Section("Exams") {
                    ForEach(exams) { exam in ExamRow(exam: exam, attempts: chapter.allAttempts.filter { $0.examSessionID == exam.id }) }
                }
            }
        }
        .navigationTitle("My progress")
    }
}

private struct MistakeChart: View {
    let mistakes: [MistakeType]

    var body: some View {
        let counts = MistakeType.allCases.map { m in (m.displayName, mistakes.filter { $0 == m }.count) }.filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let top = max(1, counts.map(\.1).max() ?? 1)
        let carelessShare = Double(mistakes.filter { $0 == .careless }.count) / Double(max(mistakes.count, 1))
        VStack(alignment: .leading, spacing: 10) {
            ForEach(counts, id: \.0) { name, n in
                HStack(spacing: 12) {
                    Text(name).font(.subheadline).frame(width: 130, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Theme.classic.notQuite.opacity(0.75))
                            .frame(width: max(10, g.size.width * CGFloat(n) / CGFloat(top)), height: 12)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 20)
                    Text("\(n)").font(.subheadline.monospacedDigit().weight(.semibold)).frame(width: 28, alignment: .trailing)
                }
            }
            if carelessShare >= 0.4 {
                Text("Most mistakes are careless slips — you probably understand the material. Focus on checking your work and not rushing.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ConceptStatsRow: View {
    let concept: Concept
    let attempts: [Attempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MathPlain.render(concept.name)).font(.headline)
            if attempts.isEmpty {
                Text("Not practiced yet").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(summary).font(.caption)
                if let top = topMistake { Text("Most common mistake: \(top.displayName)").font(.caption).foregroundStyle(Theme.classic.attention) }
            }
        }
    }

    private var summary: String {
        let correct = attempts.filter { $0.effectiveVerdict == .correct }
        let avg = correct.isEmpty ? 0 : correct.map(\.activeSeconds).reduce(0, +) / Double(correct.count)
        let estimates = concept.questions.map { Double($0.estimatedSeconds) }
        let est = estimates.isEmpty ? 0 : estimates.reduce(0, +) / Double(estimates.count)
        return "\(correct.count)/\(attempts.count) correct · avg \(formatClock(avg)) when correct (expected ~\(formatClock(est)))"
    }

    private var topMistake: MistakeType? {
        let grouped = Dictionary(grouping: attempts.compactMap(\.mistakeType), by: { $0 })
        return grouped.max { $0.value.count < $1.value.count }?.key
    }
}

private struct DailyChart: View {
    struct Bar: Identifiable {
        let id = UUID()
        let day: Date
        let result: String
        let count: Int
    }
    let attempts: [Attempt]

    var bars: [Bar] {
        let days = Dictionary(grouping: attempts, by: { Calendar.current.startOfDay(for: $0.startedAt) })
        return days.keys.sorted().flatMap { day -> [Bar] in
            let items = days[day] ?? []
            let correct = items.filter { $0.effectiveVerdict == .correct }.count
            return [Bar(day: day, result: "Correct", count: correct),
                    Bar(day: day, result: "Incorrect", count: items.count - correct)]
        }
    }

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let first = min(bars.map(\.day).min() ?? today, Calendar.current.date(byAdding: .day, value: -13, to: today) ?? today)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        Chart(bars) { bar in
            BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Questions", bar.count), width: .ratio(0.6))
                .foregroundStyle(by: .value("Result", bar.result))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .chartForegroundStyleScale(["Correct": Theme.classic.done, "Incorrect": Theme.classic.notQuite.opacity(0.8)])
        .chartXScale(domain: first...end)
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 200)
        .padding(.vertical, 6)
    }
}

private struct ExamRow: View {
    let exam: ExamSession
    let attempts: [Attempt]

    var body: some View {
        let s = SessionStats(attempts: attempts)
        let used = (exam.finishedAt ?? exam.startedAt).timeIntervalSince(exam.startedAt)
        LabeledContent(exam.startedAt.formatted(date: .abbreviated, time: .shortened),
                       value: "\(s.correct)/\(s.total) · \(formatClock(used)) of \(formatClock(Double(exam.timeLimitSeconds)))")
    }
}
