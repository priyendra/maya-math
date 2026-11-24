import Foundation

/// Numbers for the summary bar above the skills grid. Pure logic (tested); built from plain values.
struct ProgressSummary: Equatable {
    struct Answer {
        let date: Date
        /// Graded, not "to check", and not a wrong answer on a challenge question (those don't count against her).
        let counted: Bool
        let correct: Bool
        let seconds: Double
    }

    var answered = 0
    var answeredToday = 0
    var right = 0
    var rightToday = 0
    var seconds = 0.0
    var days = 0

    var totalCells = 0
    var triedCells = 0
    var masteredCells = 0
    var almostCells = 0
    var reviewDueToday = 0
    var reviewDueTomorrow = 0

    var accuracy: Double? { answered == 0 ? nil : Double(right) / Double(answered) }
    var accuracyToday: Double? { answeredToday == 0 ? nil : Double(rightToday) / Double(answeredToday) }

    init() {}

    init(answers: [Answer], planner: Planner, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let counted = answers.filter(\.counted)
        answered = counted.count
        right = counted.filter(\.correct).count
        let todays = counted.filter { calendar.startOfDay(for: $0.date) == today }
        answeredToday = todays.count
        rightToday = todays.filter(\.correct).count
        seconds = answers.map(\.seconds).reduce(0, +)
        days = Set(answers.map { calendar.startOfDay(for: $0.date) }).count

        let cells = planner.allCells
        totalCells = cells.count
        triedCells = cells.filter { planner.progress($0).attemptCount > 0 }.count
        let mastered = cells.filter(planner.isMastered)
        masteredCells = mastered.count
        almostCells = cells.filter { SkillStage.of(planner.progress($0), mastered: planner.isMastered($0)) == .almost }.count
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: today) ?? now
        for cell in mastered {
            let due = planner.progress(cell).nextDue ?? .distantPast
            if due < endOfToday { reviewDueToday += 1 } else if due < endOfTomorrow { reviewDueTomorrow += 1 }
        }
    }
}
