import Foundation

/// The same kind of mistake twice on one skill in a session: a habit worth pointing out right away
/// (other than concept mistakes, mistakes otherwise wait for the next check-in). Pure logic (tested).
enum RepeatedMistake {
    struct Answer {
        let index: Int
        let skill: UUID?
        let mistake: MistakeType?
        let wrong: Bool
        let revealed: Bool
    }

    /// The newest not-yet-shown wrong answer that repeats an earlier wrong answer's mistake kind on the same skill,
    /// with that earlier answer: (earlier, latest) indices in session order.
    static func find(_ answers: [Answer]) -> (earlier: Int, latest: Int)? {
        let wrong = answers.filter { $0.wrong && $0.skill != nil && $0.mistake != nil }
        for latest in wrong.reversed() where !latest.revealed {
            if let earlier = wrong.last(where: { $0.index < latest.index && $0.skill == latest.skill && $0.mistake == latest.mistake }) {
                return (earlier.index, latest.index)
            }
        }
        return nil
    }

    /// One line naming the habit and the check to do next time.
    static func habit(_ m: MistakeType) -> String {
        switch m {
        case .incomplete:
            return "Twice now you stopped before the final answer. Before you move on, reread the question and check you've written exactly what it asks for."
        case .careless:
            return "Two slips on this skill. Slow down on the last steps and check each line against the one before it."
        case .misread:
            return "Twice now the question said something different from what you solved. Underline what it gives and what it asks before you start."
        case .procedural:
            return "The same step went wrong twice. Look at where it went wrong below, then do that step slowly next time."
        case .conceptual:
            return "The same idea tripped you up twice. Read the worked example for this skill before the next one."
        }
    }
}
