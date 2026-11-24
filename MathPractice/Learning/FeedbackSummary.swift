import Foundation

/// Builds the plain-text summary of a student's answers that Claude turns into "Teacher's feedback".
/// Pure logic (tested). Recent work is given in full; earlier work in brief, so feedback leans on what she does now
/// without ignoring older patterns. All counts are computed here, so Claude never has to count.
enum FeedbackSummary {
    struct Answer {
        let date: Date
        let seconds: Double
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

    /// `steps`: dots toward the star per skill level ("skill|level" → 0…5), `mastered`: those with a star.
    static func text(_ answers: [Answer], steps: [String: Int] = [:], mastered: Set<String> = []) -> String {
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
        out.append("\nSKILLS (skill — level: recent right/answered; earlier right/answered; progress toward the star):")
        for key in order {
            guard let s = bySkill[key] else { continue }
            let r = recent.filter { $0.skill == s.skill && $0.level == s.level }
            let e = earlier.filter { $0.skill == s.skill && $0.level == s.level }
            let progress = mastered.contains(key) ? "★ mastered" : "\(steps[key] ?? 0) of 5 steps"
            out.append("- \(s.skill) — \(levelNames[max(0, min(2, s.level - 1))]): recent \(right(r))/\(r.count); earlier \(right(e))/\(e.count); \(progress)")
        }

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
