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

    /// Accuracy is solid enough to start pushing on time: ≥4 of the last 5 correct.
    static func inSpeedStage(_ p: SkillProgress) -> Bool {
        p.recentResults.count >= 4 && p.recentResults.filter { $0 }.count >= 4
    }

    /// Target time for a question: start from Claude's estimate, then tighten toward her own pace.
    static func targetSeconds(estimate: Double, progress p: SkillProgress) -> Double {
        guard p.recentCorrectSeconds.count >= 3, let median = medianCorrectSeconds(p) else { return estimate }
        return max(0.5 * estimate, min(estimate, 0.9 * median))
    }

    /// Mastered = accurate, practiced enough, last one right, and not far slower than the estimate.
    static func isMastered(_ p: SkillProgress, estimate: Double) -> Bool {
        guard p.mastery >= masteredThreshold, p.attemptCount >= 3, p.recentResults.last == true else { return false }
        if p.recentCorrectSeconds.count >= 3, let median = medianCorrectSeconds(p) {
            return median <= 1.3 * estimate
        }
        return true
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
    /// Number of dots shown toward the star.
    static let steps = 5

    /// Score after `n` right answers in a row from a fresh start.
    static func scoreAfter(rightInARow n: Int) -> Double { 1 - pow(1 - gainRate, Double(n)) }

    /// The score shown as dots: how many right-in-a-row answers it is worth (0…5).
    static func dots(_ mastery: Double) -> Int {
        (1...steps).filter { scoreAfter(rightInARow: $0) <= mastery + 0.005 }.count
    }

    /// More right answers in a row needed for the star (ignoring speed). 0 when the score is already there.
    static func rightAnswersToStar(_ p: SkillProgress) -> Int {
        var p = p, n = 0
        while n < 20 {
            if p.mastery >= masteredThreshold, p.attemptCount >= 3, p.recentResults.last == true { return n }
            p = apply(correct: true, mistake: nil, seconds: nil, to: p)
            n += 1
        }
        return n
    }

    /// Accurate enough for the star but held back because she's slower than expected.
    static func heldBackBySpeed(_ p: SkillProgress, estimate: Double) -> Bool {
        rightAnswersToStar(p) == 0 && !isMastered(p, estimate: estimate)
    }
}
