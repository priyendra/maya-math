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
            Section("Mastery (concept × difficulty)") {
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
        let counts = MistakeType.allCases.map { m in (m.displayName, mistakes.filter { $0 == m }.count) }
        let carelessShare = Double(mistakes.filter { $0 == .careless }.count) / Double(max(mistakes.count, 1))
        VStack(alignment: .leading) {
            Chart(counts, id: \.0) { item in
                BarMark(x: .value("Count", item.1), y: .value("Type", item.0))
            }
            .frame(height: 180)
            if carelessShare >= 0.4 {
                Text("Most mistakes are careless slips — you probably understand the material. Focus on checking your work and not rushing.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConceptStatsRow: View {
    let concept: Concept
    let attempts: [Attempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(concept.name).font(.headline)
            if attempts.isEmpty {
                Text("Not practiced yet").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(summary).font(.caption)
                if let top = topMistake { Text("Most common mistake: \(top.displayName)").font(.caption).foregroundStyle(.orange) }
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
        Chart(bars) { bar in
            BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Questions", bar.count))
                .foregroundStyle(by: .value("Result", bar.result))
        }
        .chartForegroundStyleScale(["Correct": Color.green, "Incorrect": Color.red])
        .frame(height: 200)
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
