import Foundation

/// mastery points (0–100) for a chapter (or study plan) and their history.
/// Each skill level (concept × level) earns up to 100 as its score climbs to the star threshold (80%); points = the average,
/// so 100 means every level has reached star level. Untried or locked levels count 0.
/// History is rebuilt by replaying answers in order with the same rules as `LearningStore.apply`.
enum ChapterScore {
    struct Answer {
        let date: Date
        /// nil for answers that don't change a score (still waiting for a grade, to check, challenge, hint...):
        /// their time still counts as practice time.
        let cell: CellKey?
        let correct: Bool
        let mistake: MistakeType?
        let seconds: Double
    }

    struct Point: Identifiable, Equatable {
        var id: Double { hours }
        let date: Date
        /// Practice time so far (active seconds on answers), in hours.
        let hours: Double
        let score: Double
    }

    static let target = MasteryModel.masteredThreshold

    /// Mastery points, 0–100.
    static func score(_ skills: [CellKey: SkillProgress], cells: [CellKey]) -> Double {
        guard !cells.isEmpty else { return 0 }
        return 100 * cells.map { min((skills[$0]?.mastery ?? 0) / target, 1) }.reduce(0, +) / Double(cells.count)
    }

    /// The score from answers given before `date` only (e.g. the start of today).
    static func score(_ answers: [Answer], cells: [CellKey], before date: Date) -> Double {
        var skills: [CellKey: SkillProgress] = [:]
        for a in answers.sorted(by: { $0.date < $1.date }) where a.date < date {
            guard let cell = a.cell else { continue }
            skills[cell] = MasteryModel.apply(correct: a.correct, mistake: a.mistake, seconds: a.seconds,
                                              to: skills[cell] ?? SkillProgress(), now: a.date)
        }
        return score(skills, cells: cells)
    }

    /// The score after every `step` of practice time (default 30 minutes), plus a 0 at the start and the score now.
    /// A point is taken after the answer that crosses each step, plotted at the step itself.
    static func history(_ answers: [Answer], cells: [CellKey], step: TimeInterval = 30 * 60) -> [Point] {
        let sorted = answers.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        var skills: [CellKey: SkillProgress] = [:]
        var points = [Point(date: first.date.addingTimeInterval(-60), hours: 0, score: 0)]
        var seconds = 0.0
        var nextMark = step
        for a in sorted {
            seconds += a.seconds
            if let cell = a.cell {
                skills[cell] = MasteryModel.apply(correct: a.correct, mistake: a.mistake, seconds: a.seconds,
                                                  to: skills[cell] ?? SkillProgress(), now: a.date)
            }
            while seconds >= nextMark {
                points.append(Point(date: a.date, hours: nextMark / 3600, score: score(skills, cells: cells)))
                nextMark += step
            }
        }
        if seconds > (points.last?.hours ?? 0) * 3600 + 60 {
            points.append(Point(date: sorted.last!.date, hours: seconds / 3600, score: score(skills, cells: cells)))
        }
        return points
    }
}
