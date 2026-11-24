import Foundation

/// one progress path per concept (Basic → Medium → Hard → ★), built on the per-level cells.
/// Mastered = the concept's top level (that has questions) is mastered. Display only; the planner is unchanged.
struct ConceptPath {
    struct Level {
        let difficulty: Int
        /// Steps filled on this level (0…5).
        let filled: Int
        let open: Bool
    }

    let levels: [Level]
    let current: Int          // difficulty she is working on
    let mastered: Bool
    let slow: Bool
    /// Right answers in a row to open the next level, or to earn the star on the top level.
    let toNext: Int
    let attempted: Bool

    var totalSteps: Int { levels.count * MasteryModel.steps }
    var filledSteps: Int { levels.map(\.filled).reduce(0, +) }
    var fraction: Double { totalSteps == 0 ? 0 : Double(filledSteps) / Double(totalSteps) }
    var isOnTopLevel: Bool { current == levels.last?.difficulty }

    static let levelNames = ["Basic", "Medium", "Hard"]

    var levelName: String { Self.levelNames[current - 1] }

    var nextName: String? {
        guard let i = levels.firstIndex(where: { $0.difficulty == current }), i + 1 < levels.count else { return nil }
        return Self.levelNames[levels[i + 1].difficulty - 1]
    }

    var status: String {
        if mastered { return "Mastered" }
        if !attempted { return "Not started" }
        if slow { return "\(levelName) · right enough for the ★, now a bit faster" }
        if let next = nextName { return "\(levelName) · \(toNext) more right to open \(next)" }
        return "\(levelName) · \(toNext) more right in a row for the ★"
    }

    init(conceptID: UUID, conceptOrder: Int, planner: Planner) {
        let cells = planner.allCells.filter { $0.conceptID == conceptID }.sorted { $0.difficulty < $1.difficulty }
        let currentCell = cells.last(where: planner.isOpen) ?? cells.first
        let top = cells.last
        let isMastered = top.map(planner.isMastered) ?? false
        mastered = isMastered
        attempted = cells.contains { planner.progress($0).attemptCount > 0 }
        current = currentCell?.difficulty ?? 1
        levels = cells.map { cell in
            let full = isMastered || cell.difficulty < (currentCell?.difficulty ?? 1)
            let dots = full ? MasteryModel.steps
                : cell.difficulty == currentCell?.difficulty ? MasteryModel.dots(planner.progress(cell).mastery) : 0
            return Level(difficulty: cell.difficulty, filled: dots, open: planner.isOpen(cell))
        }
        if let c = currentCell, !isMastered {
            let p = planner.progress(c)
            if c == top {
                toNext = MasteryModel.rightAnswersToStar(p)
                slow = p.attemptCount > 0 && MasteryModel.heldBackBySpeed(p, estimate: planner.estimate(c))
            } else {
                var q = p, n = 0
                while q.mastery < MasteryModel.unlockThreshold && n < 20 {
                    q = MasteryModel.apply(correct: true, mistake: nil, seconds: nil, to: q); n += 1
                }
                toNext = max(n, 1)
                slow = false
            }
        } else {
            toNext = 0
            slow = false
        }
    }
}
