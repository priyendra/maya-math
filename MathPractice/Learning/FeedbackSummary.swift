import Foundation

/// Builds the plain-text summary of a student's answers that Claude turns into "Teacher's feedback".
/// Pure logic (tested). Recent work is given in full; earlier work in brief, so feedback leans on what she does now
/// without ignoring older patterns. All counts are computed here, so Claude never has to count.
enum FeedbackSummary {
    struct Answer {
        let date: Date
        /// Time used for totals (a break counts as her typical time).
        let seconds: Double
        /// The question's estimated time, and the time actually measured.
        var estimate: Double = 0
        var rawSeconds: Double = 0
        /// Answered in exam mode (under time pressure): left out of her practice pace.
        var timed = false
        let skill: String
        let level: Int
        let verdict: Verdict
        let mistake: MistakeType?
        let errorStep: String
        /// Tapped "I'm stuck" (shown the solution) or used a hint.
        let helped: Bool
    }

    /// Practice time that counts as "recent": the last hour.
    static let recentWindow: TimeInterval = 60 * 60
    /// Feedback is rewritten after this much more practice.
    static let refreshEvery: TimeInterval = 30 * 60
    /// First feedback once she has answered this many.
    static let minimumAnswers = 10

    static let levelNames = ["Basic", "Medium", "Hard"]

    static func isDue(practiceSeconds: Double, answered: Int, lastFeedbackAt lastSeconds: Double?) -> Bool {
        guard let lastSeconds else { return answered >= minimumAnswers }
        return practiceSeconds - lastSeconds >= refreshEvery
    }

    /// Splits answers (in time order) into earlier and recent by practice time.
    static func split(_ answers: [Answer]) -> (earlier: [Answer], recent: [Answer]) {
        let sorted = answers.sorted { $0.date < $1.date }
        var acc = 0.0
        var cut = sorted.count
        for (i, a) in sorted.enumerated().reversed() {
            acc += a.seconds
            cut = i
            if acc >= recentWindow { break }
        }
        return (Array(sorted[..<cut]), Array(sorted[cut...]))
    }

    /// Her practice pace per level, recent vs earlier, right vs wrong, and the slowest / quickest skill levels lately.
    static func pace(recent: [Answer], earlier: [Answer]) -> String {
        let all = (earlier + recent).filter { !$0.timed && $0.estimate > 0 && $0.rawSeconds > 0 }
        let samples = all.map { Pace.Sample(seconds: $0.rawSeconds, estimate: $0.estimate, level: $0.level,
                                            skill: "\($0.skill)|\($0.level)", correct: $0.verdict == .correct) }
        let drop = Pace.outliers(samples)
        let kept = all.indices.filter { !drop.contains($0) }.map { all[$0] }
        let recentDates = Set(recent.map(\.date))
        func ratio(_ xs: [Answer]) -> Double { Pace.median(xs.map { $0.rawSeconds / $0.estimate }) }
        func x(_ r: Double) -> String { String(format: "%.1f×", r) }
        func secs(_ xs: [Answer]) -> String { "\(Int(Pace.median(xs.map(\.rawSeconds)).rounded())) s" }

        var out = ["\nPACE IN PRACTICE (her time ÷ the question's estimated time: 1.0× = on estimate, 2.0× = twice as long; "
                   + "exam answers not included; \(drop.count) very long time\(drop.count == 1 ? "" : "s") (over 3 min and far "
                   + "beyond her usual pace) left out as breaks):"]
        for level in 1...3 {
            let lv = kept.filter { $0.level == level }
            guard !lv.isEmpty else { continue }
            let r = lv.filter { recentDates.contains($0.date) }, e = lv.filter { !recentDates.contains($0.date) }
            var line = "- \(levelNames[level - 1]):"
            if !r.isEmpty { line += " recent \(x(ratio(r))) (typical \(secs(r)), \(r.count) answers);" }
            if !e.isEmpty { line += " earlier \(x(ratio(e))) (\(e.count) answers);" }
            let right = lv.filter { $0.verdict == .correct }, wrong = lv.filter { $0.verdict == .incorrect }
            if right.count >= 3 && wrong.count >= 3 { line += " right answers \(x(ratio(right))), wrong answers \(x(ratio(wrong)))." }
            out.append(line)
        }
        // Skill levels with at least 2 recent answers, slowest and quickest relative to estimate.
        let recentKept = kept.filter { recentDates.contains($0.date) }
        let groups = Dictionary(grouping: recentKept, by: { "\($0.skill) — \(levelNames[max(0, min(2, $0.level - 1))])" })
            .filter { $0.value.count >= 2 }
            .map { (name: $0.key, r: ratio($0.value), n: $0.value.count, s: secs($0.value)) }
            .sorted { $0.r > $1.r }
        if !groups.isEmpty {
            out.append("Slowest recently: " + groups.prefix(3).map { "\($0.name) \(x($0.r)) (typical \($0.s), \($0.n) answers)" }.joined(separator: "; "))
            if groups.count > 3 {
                out.append("Quickest recently: " + groups.suffix(2).map { "\($0.name) \(x($0.r)) (\($0.n) answers)" }.joined(separator: "; "))
            }
        }
        return out.joined(separator: "\n")
    }

    /// `points`: mastery points per skill level ("skill|level" → 0…100; 100 = mastered).
    static func text(_ answers: [Answer], points: [String: Int] = [:]) -> String {
        let graded = answers.filter { $0.verdict != .needsReview }
        let (earlier, recent) = split(graded)
        var out: [String] = []

        func right(_ xs: [Answer]) -> Int { xs.filter { $0.verdict == .correct }.count }
        func minutes(_ xs: [Answer]) -> Int { Int(xs.map(\.seconds).reduce(0, +) / 60) }

        out.append("OVERALL: \(graded.count) answers, \(right(graded)) right, \(minutes(graded)) minutes of practice.")
        out.append("RECENT WORK (her last \(minutes(recent)) minutes of practice): \(recent.count) answers, \(right(recent)) right.")
        out.append("EARLIER WORK: \(earlier.count) answers, \(right(earlier)) right.")

        // Per skill level, in the order she first met them.
        var order: [String] = []
        var bySkill: [String: (skill: String, level: Int)] = [:]
        for a in graded.sorted(by: { $0.date < $1.date }) {
            let key = "\(a.skill)|\(a.level)"
            if bySkill[key] == nil { order.append(key); bySkill[key] = (a.skill, a.level) }
        }
        out.append("\nSKILLS (skill — level: recent right/answered; earlier right/answered; mastery points, 100 = mastered):")
        for key in order {
            guard let s = bySkill[key] else { continue }
            let r = recent.filter { $0.skill == s.skill && $0.level == s.level }
            let e = earlier.filter { $0.skill == s.skill && $0.level == s.level }
            let pts = points[key] ?? 0
            let progress = pts >= 100 ? "mastered (100 points)" : "\(pts) points"
            out.append("- \(s.skill) — \(levelNames[max(0, min(2, s.level - 1))]): recent \(right(r))/\(r.count); earlier \(right(e))/\(e.count); \(progress)")
        }

        out.append(pace(recent: recent, earlier: earlier))

        func mistakeCounts(_ xs: [Answer]) -> String {
            let wrong = xs.filter { $0.verdict == .incorrect && !$0.helped }
            let counts = MistakeType.allCases.map { m in (m, wrong.filter { $0.mistake == m }.count) }.filter { $0.1 > 0 }
            return counts.isEmpty ? "none" : counts.map { "\($0.0.displayName) \($0.1)" }.joined(separator: ", ")
        }
        out.append("\nMISTAKE TYPES: recent — \(mistakeCounts(recent)); earlier — \(mistakeCounts(earlier)).")

        func lines(_ xs: [Answer]) -> [String] {
            xs.filter { $0.verdict == .incorrect && !$0.errorStep.isEmpty }.map { a in
                let lvl = levelNames[max(0, min(2, a.level - 1))]
                let kind = a.helped ? "asked for help" : (a.mistake?.displayName ?? "mistake")
                return "- [\(a.skill) — \(lvl); \(kind)] \(a.errorStep)"
            }
        }
        let recentLines = lines(recent)
        out.append("\nRECENT MISTAKES (where each went wrong, oldest first):")
        out.append(recentLines.isEmpty ? "- none" : recentLines.suffix(30).joined(separator: "\n"))
        let earlierLines = lines(earlier)
        out.append("\nEARLIER MISTAKES (the latest \(min(12, earlierLines.count)) of \(earlierLines.count)):")
        out.append(earlierLines.isEmpty ? "- none" : earlierLines.suffix(12).joined(separator: "\n"))
        return out.joined(separator: "\n")
    }
}
