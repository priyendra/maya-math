import SwiftUI

/// The progress summary on chapter and study plan pages: mastery points over practice time, and one line of numbers.
/// Chapter page: mastery points chart and one line of practice numbers.
struct PathGlance: View {
    let set: StudySet
    @Environment(\.theme) private var theme

    var body: some View {
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
                stat(Fmt.percent(Double(right) / Double(counted.count)),
                     today.isEmpty ? "right" : "right (\(Fmt.percent(Double(rightToday) / Double(today.count))) today)")
                stat(Fmt.duration(seconds), "practice")
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
