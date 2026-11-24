import SwiftUI

/// Every finished exam on a chapter or study plan, newest first: settings, score, time. Tap one for its results.
struct ExamHistoryView: View {
    let set: StudySet
    @State private var open: ExamSession?

    static func exams(_ set: StudySet) -> [ExamSession] {
        let ids = Set(set.questions.map(\.id))
        // A study plan shows the exams taken on (mostly) its own questions.
        return set.chapters.flatMap(\.exams).filter { e in
            e.finishedAt != nil && e.questionIDs.filter(ids.contains).count * 2 >= max(e.questionIDs.count, 1)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    static func attempts(_ exam: ExamSession, in set: StudySet) -> [Attempt] {
        let order = Dictionary(exam.questionIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return set.allAttempts.filter { $0.examSessionID == exam.id }
            .sorted { (order[$0.question?.id ?? UUID()] ?? 0) < (order[$1.question?.id ?? UUID()] ?? 0) }
    }

    var body: some View {
        let exams = Self.exams(set)
        List {
            if exams.isEmpty {
                Text("No exams yet. Each exam you take shows up here with its settings and score.")
                    .foregroundStyle(.secondary)
            }
            ForEach(exams) { exam in
                let attempts = Self.attempts(exam, in: set)
                let s = SessionStats(attempts: attempts)
                let used = attempts.map(\.activeSeconds).reduce(0, +)
                Button { open = exam } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exam.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text(exam.settingsLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(s.correct)/\(s.total) right").font(.headline.monospacedDigit())
                            Text("\(formatClock(used)) of \(formatClock(Double(exam.timeLimitSeconds)))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(used > Double(exam.timeLimitSeconds) ? .orange : .secondary)
                        }
                        GoChevron()
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(TapRowStyle())
                .accessibilityIdentifier("exam-row")
            }
        }
        .navigationTitle("My exams")
        .navigationDestination(item: $open) { exam in
            let attempts = Self.attempts(exam, in: set)
            ExamResultsView(attempts: attempts, timeLimit: Double(exam.timeLimitSeconds),
                            timeUsed: attempts.map(\.activeSeconds).reduce(0, +),
                            targets: Dictionary(zip(exam.questionIDs, exam.allowedSeconds), uniquingKeysWith: { a, _ in a }),
                            pace: exam.pace, showDone: false) { open = nil }
                .navigationTitle(exam.startedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }
}
