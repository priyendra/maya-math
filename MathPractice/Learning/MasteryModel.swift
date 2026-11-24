import Foundation

/// Plain-value snapshot of one skill cell (concept × difficulty). Pure logic, unit-tested.
struct SkillProgress: Equatable {
    var mastery: Double = 0
    var attemptCount: Int = 0
    var recentResults: [Bool] = []
    var recentCorrectSeconds: [Double] = []
    var lastPracticed: Date?
    var nextDue: Date?
    var intervalDays: Double = 0
    var careless: Int = 0
}

enum MasteryModel {
    static let gainRate = 0.3
    static let lossRate = 0.4
    static let carelessLossRate = 0.2
    static let masteredThreshold = 0.8
    static let unlockThreshold = 0.6
    static let recentWindow = 5
    static let timeWindow = 7
    static let intervals: [Double] = [1, 3, 7, 14]

    /// Applies one graded attempt.
    static func apply(
        correct: Bool,
        mistake: MistakeType?,
        seconds: Double?,
        to p: SkillProgress,
        now: Date = Date()
    ) -> SkillProgress {
        var p = p
        p.attemptCount += 1
        p.lastPracticed = now
        p.recentResults = Array((p.recentResults + [correct]).suffix(recentWindow))

        if correct {
            p.mastery += gainRate * (1 - p.mastery)
            if let seconds, seconds > 0 {
                p.recentCorrectSeconds = Array((p.recentCorrectSeconds + [seconds]).suffix(timeWindow))
            }
            let nextStep = intervals.first { $0 > p.intervalDays } ?? intervals.last!
            p.intervalDays = nextStep
            p.nextDue = now.addingTimeInterval(nextStep * 86_400)
        } else {
            let rate = mistake == .careless ? carelessLossRate : lossRate
            p.mastery -= rate * p.mastery
            if mistake == .careless { p.careless += 1 }
            p.intervalDays = 0
            p.nextDue = now.addingTimeInterval(86_400)
        }
        p.mastery = min(max(p.mastery, 0), 1)
        return p
    }

    static func medianCorrectSeconds(_ p: SkillProgress) -> Double? {
        guard !p.recentCorrectSeconds.isEmpty else { return nil }
        let s = p.recentCorrectSeconds.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Target time for an exam question: start from Claude's estimate, then tighten toward her own pace.
    /// Time is only an exam concept; it never affects mastery.
    static func targetSeconds(estimate: Double, progress p: SkillProgress) -> Double {
        guard p.recentCorrectSeconds.count >= 3, let median = medianCorrectSeconds(p) else { return estimate }
        return max(0.5 * estimate, min(estimate, 0.9 * median))
    }

    /// Mastered = 100 mastery points (score at the mastery threshold). Accuracy only: time plays no part.
    /// A wrong answer always drops the score below the threshold, and reaching it takes at least 5 right answers.
    static func isMastered(_ p: SkillProgress) -> Bool {
        p.mastery >= masteredThreshold
    }
}

extension SkillState {
    var progress: SkillProgress {
        get {
            SkillProgress(mastery: mastery, attemptCount: attemptCount, recentResults: recentResults,
                          recentCorrectSeconds: recentCorrectSeconds, lastPracticed: lastPracticed,
                          nextDue: nextDue, intervalDays: intervalDays, careless: careless)
        }
        set {
            mastery = newValue.mastery
            attemptCount = newValue.attemptCount
            recentResults = newValue.recentResults
            recentCorrectSeconds = newValue.recentCorrectSeconds
            lastPracticed = newValue.lastPracticed
            nextDue = newValue.nextDue
            intervalDays = newValue.intervalDays
            careless = newValue.careless
        }
    }
}

extension MasteryModel {
    /// Score after `n` right answers in a row from a fresh start.
    static func scoreAfter(rightInARow n: Int) -> Double { 1 - pow(1 - gainRate, Double(n)) }

    /// More right answers in a row needed to reach 100 points (mastered). 0 when already there.
    static func rightAnswersToMaster(_ p: SkillProgress) -> Int {
        var p = p, n = 0
        while n < 20 && !isMastered(p) {
            p = apply(correct: true, mistake: nil, seconds: nil, to: p)
            n += 1
        }
        return n
    }
}
