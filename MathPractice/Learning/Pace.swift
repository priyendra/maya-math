import Foundation

/// Her pace: how long answers take compared with each question's estimated time. Pure logic (tested).
///
/// Times are compared as a ratio to the question's estimate, so a long word problem and a quick Basic question can be
/// judged together. A time is an outlier (she was probably doing something else) when it is both
/// - far beyond her usual pace on that level: log(time ÷ estimate) more than 2 standard deviations above the mean, and
/// - longer than 3 minutes, so a slow answer on a quick question is not dropped (that's real pace).
/// Outliers are left out of pace statistics, and count as her typical time in practice-time totals.
enum Pace {
    struct Sample {
        let seconds: Double
        let estimate: Double
        let level: Int
        /// Skill level key, e.g. "<concept>|<level>".
        let skill: String
        let correct: Bool
    }

    static let outlierSD = 2.0
    static let outlierMinSeconds: Double = 180
    /// Fewer answers than this on a level: no outlier test (too few to know her spread).
    static let minForStats = 5

    /// Indices of samples whose time is an outlier.
    static func outliers(_ samples: [Sample]) -> Set<Int> {
        var out = Set<Int>()
        let byLevel = Dictionary(grouping: samples.indices.filter { valid(samples[$0]) }, by: { samples[$0].level })
        for (_, idx) in byLevel where idx.count >= minForStats {
            let logs = idx.map { log(samples[$0].seconds / samples[$0].estimate) }
            let mean = logs.reduce(0, +) / Double(logs.count)
            let sd = (logs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(logs.count)).squareRoot()
            for (i, l) in zip(idx, logs) where l > mean + outlierSD * sd && samples[i].seconds > outlierMinSeconds {
                out.insert(i)
            }
        }
        return out
    }

    /// Her typical time ÷ estimate per level (median over non-outlier answers; 1 when she has fewer than 3).
    static func levelRatios(_ samples: [Sample]) -> [Int: Double] {
        let drop = outliers(samples)
        let kept = samples.indices.filter { !drop.contains($0) && valid(samples[$0]) }.map { samples[$0] }
        var out: [Int: Double] = [:]
        for (level, xs) in Dictionary(grouping: kept, by: \.level) where xs.count >= 3 {
            out[level] = median(xs.map { $0.seconds / $0.estimate })
        }
        return out
    }

    /// Her own time for a question: its estimate × her typical ratio on that skill level (right answers, at least 3),
    /// else on that level, else the estimate.
    static func baseline(estimate: Double, level: Int, skill: String, samples: [Sample]) -> Double {
        let drop = outliers(samples)
        let kept = samples.indices.filter { !drop.contains($0) && valid(samples[$0]) }.map { samples[$0] }
        let skillRight = kept.filter { $0.skill == skill && $0.correct }
        if skillRight.count >= 3 { return estimate * median(skillRight.map { $0.seconds / $0.estimate }) }
        return estimate * (levelRatios(samples)[level] ?? 1)
    }

    /// Each sample's time with outliers replaced by her typical time for that question.
    static func cleanSeconds(_ samples: [Sample]) -> [Double] {
        let drop = outliers(samples)
        let ratios = levelRatios(samples)
        return samples.indices.map { i in
            let s = samples[i]
            return drop.contains(i) ? s.estimate * (ratios[s.level] ?? 1) : s.seconds
        }
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 0 ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    private static func valid(_ s: Sample) -> Bool { s.seconds > 0 && s.estimate > 0 }
}

/// Exam settings: how hard and how fast. Independent of each other.
enum ExamDifficulty: Int, CaseIterable {
    case mixed, harder, hardest

    var name: String {
        switch self {
        case .mixed: return "Normal"
        case .harder: return "Hard"
        case .hardest: return "Hardest"
        }
    }

    var detail: String {
        switch self {
        case .mixed: return "Basic, Medium and Hard in even parts"
        case .harder: return "Medium and Hard"
        case .hardest: return "Mostly Hard"
        }
    }

    /// Share of questions per level (Basic, Medium, Hard).
    var shares: [Int: Double] {
        switch self {
        case .mixed: return [1: 1.0 / 3, 2: 1.0 / 3, 3: 1.0 / 3]
        case .harder: return [2: 0.5, 3: 0.5]
        case .hardest: return [2: 0.25, 3: 0.75]
        }
    }
}

enum ExamPace: Int, CaseIterable {
    case own, fast, veryFast

    var name: String {
        switch self {
        case .own: return "Normal"
        case .fast: return "Fast"
        case .veryFast: return "Fastest"
        }
    }

    /// How much faster than her own practice pace.
    var factor: Double {
        switch self {
        case .own: return 1
        case .fast: return 1.25
        case .veryFast: return 1.5
        }
    }

    var detail: String {
        switch self {
        case .own: return "Your usual time from practice"
        case .fast: return "1.25× faster: your usual time ÷ 1.25"
        case .veryFast: return "1.5× faster: your usual time ÷ 1.5"
        }
    }
}

/// Exam length: the time limit. The exam holds about as many questions as fit at the chosen pace.
enum ExamLength: Int, CaseIterable {
    case twenty = 20, thirty = 30, fortyFive = 45
    var name: String { "\(rawValue) min" }
}

extension ExamSession {
    var difficulty: ExamDifficulty { ExamDifficulty(rawValue: difficultyRaw) ?? .mixed }
    var pace: ExamPace { ExamPace(rawValue: paceRaw) ?? .own }
    /// "Hard · Fast · 30 min" (older exams, taken before the settings existed, show only their length).
    var settingsLine: String {
        let length = "\(timeLimitSeconds / 60) min"
        return allowedSeconds.isEmpty ? length : "\(difficulty.name) · \(pace.name) · \(length)"
    }
}
