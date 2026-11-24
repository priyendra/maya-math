import Foundation

/// Identifies one skill cell: a concept at a difficulty level.
struct CellKey: Hashable {
    let conceptID: UUID
    let conceptOrder: Int
    let difficulty: Int
}

/// Lightweight view of a question for planning (built from SwiftData models).
struct QuestionInfo: Equatable {
    let id: UUID
    let cell: CellKey
    let isGenerated: Bool
    let estimatedSeconds: Double
    let timesSeen: Int
    let lastSeen: Date?
    let lastWasCorrect: Bool?
    /// Book-marked challenge questions: never in normal pools; offered as stretch once the concept's hardest level is mastered.
    var isChallenge: Bool = false
}

/// State of the current 30-minute session.
struct SessionState {
    var askedQuestionIDs: [UUID] = []
    /// Cells answered wrong this session → index (in askedQuestionIDs) after which to re-practice.
    var pendingReinforcement: [CellKey: Int] = [:]
    var lastCategory: PickCategory?
}

enum PickCategory: String, Equatable {
    case reinforcement, weak, review, stretch, challenge
}

struct Pick: Equatable {
    let questionID: UUID
    let cell: CellKey
    let category: PickCategory
}

/// Chooses the next practice question. Pure logic; randomness injected for tests.
struct Planner {
    static let weakShare = 0.65
    static let reviewShare = 0.20
    static let reinforcementGap = 2

    let questions: [QuestionInfo]
    let skills: [CellKey: SkillProgress]
    let now: Date

    var regular: [QuestionInfo] { questions.filter { !$0.isChallenge } }

    var allCells: [CellKey] {
        Array(Set(regular.map(\.cell))).sorted {
            ($0.conceptOrder, $0.difficulty) < ($1.conceptOrder, $1.difficulty)
        }
    }

    func progress(_ cell: CellKey) -> SkillProgress { skills[cell] ?? SkillProgress() }

    func estimate(_ cell: CellKey) -> Double {
        let qs = regular.filter { $0.cell == cell }
        guard !qs.isEmpty else { return 120 }
        return qs.map(\.estimatedSeconds).reduce(0, +) / Double(qs.count)
    }

    func isMastered(_ cell: CellKey) -> Bool {
        MasteryModel.isMastered(progress(cell))
    }

    /// Difficulty 1 of every concept is open (the book already taught them);
    /// difficulty d+1 opens once difficulty d (or the nearest lower level that exists) reaches the unlock threshold.
    func isOpen(_ cell: CellKey) -> Bool {
        let lower = allCells.filter { $0.conceptID == cell.conceptID && $0.difficulty < cell.difficulty }
        guard let prev = lower.max(by: { $0.difficulty < $1.difficulty }) else { return true }
        return progress(prev).mastery >= MasteryModel.unlockThreshold
    }

    var weakCells: [CellKey] {
        allCells.filter { isOpen($0) && !isMastered($0) }
            .sorted { a, b in
                // Lower mastery first, then book order, then easier first.
                let ma = progress(a).mastery, mb = progress(b).mastery
                if abs(ma - mb) > 0.05 { return ma < mb }
                return (a.conceptOrder, a.difficulty) < (b.conceptOrder, b.difficulty)
            }
    }

    var reviewCells: [CellKey] {
        allCells.filter { isOpen($0) && isMastered($0) && (progress($0).nextDue ?? .distantPast) <= now }
            .sorted { (progress($0).nextDue ?? .distantPast) < (progress($1).nextDue ?? .distantPast) }
    }

    /// The next locked level of a concept whose level below is making progress.
    var stretchCells: [CellKey] {
        allCells.filter { cell in
            guard !isOpen(cell) else { return false }
            let lower = allCells.filter { $0.conceptID == cell.conceptID && $0.difficulty < cell.difficulty }
            guard let prev = lower.max(by: { $0.difficulty < $1.difficulty }) else { return false }
            return progress(prev).mastery >= 0.4
        }
    }

    /// Cells with no unseen question left; the app generates variants for these.
    func cellsNeedingVariants(minUnseen: Int = 1) -> [CellKey] {
        let targets = Set(weakCells + reviewCells + stretchCells)
        return allCells.filter { cell in
            targets.contains(cell) && regular.filter { $0.cell == cell && $0.timesSeen == 0 }.count < minUnseen
        }
    }

    func next(session: SessionState, random: () -> Double = { Double.random(in: 0..<1) }) -> Pick? {
        let index = session.askedQuestionIDs.count

        // 1. Re-practice a cell she just got wrong, after a couple of other questions.
        let dueReinforcements = session.pendingReinforcement
            .filter { $0.value <= index }
            .sorted { $0.value < $1.value }
        for (cell, _) in dueReinforcements {
            if let q = pickQuestion(in: cell, session: session) {
                return Pick(questionID: q.id, cell: cell, category: .reinforcement)
            }
        }

        // 2. Weighted choice between weak / review / stretch, falling back when a pool is empty.
        let r = random()
        var order: [PickCategory]
        if r < Self.weakShare { order = [.weak, .review, .stretch] }
        else if r < Self.weakShare + Self.reviewShare { order = [.review, .weak, .stretch] }
        else { order = [.challenge, .stretch, .weak, .review] }

        for category in order {
            let pool: [CellKey]
            switch category {
            case .weak: pool = weakCells
            case .review: pool = reviewCells
            case .stretch: pool = stretchCells
            case .reinforcement: pool = []
            case .challenge:
                if let q = pickChallenge(session: session) {
                    return Pick(questionID: q.id, cell: q.cell, category: .challenge)
                }
                continue
            }
            // Take from the top few, varying the cell so she doesn't get the same type back-to-back.
            let lastCell = session.askedQuestionIDs.last.flatMap { id in questions.first { $0.id == id }?.cell }
            let top = Array(pool.prefix(3))
            let candidates = top.filter { $0 != lastCell } + top.filter { $0 == lastCell } + pool.dropFirst(3)
            for cell in candidates {
                if let q = pickQuestion(in: cell, session: session) {
                    return Pick(questionID: q.id, cell: cell, category: category)
                }
            }
        }

        // 3. Everything mastered and nothing due: least-recently practiced open cell.
        let fallback = allCells.filter(isOpen).sorted {
            (progress($0).lastPracticed ?? .distantPast) < (progress($1).lastPracticed ?? .distantPast)
        }
        for cell in fallback {
            if let q = pickQuestion(in: cell, session: session) {
                return Pick(questionID: q.id, cell: cell, category: .review)
            }
        }
        return nil
    }

    /// An unseen challenge question from a concept whose hardest regular level is mastered.
    func pickChallenge(session: SessionState) -> QuestionInfo? {
        let asked = Set(session.askedQuestionIDs)
        return questions.first { q in
            guard q.isChallenge, q.timesSeen == 0, !asked.contains(q.id) else { return false }
            let levels = allCells.filter { $0.conceptID == q.cell.conceptID }
            guard let top = levels.max(by: { $0.difficulty < $1.difficulty }) else { return false }
            return isMastered(top)
        }
    }

    /// Within a cell: unseen book → unseen generated → previously wrong (≥1 day ago) → least recently seen.
    /// Never repeats a question already asked this session.
    func pickQuestion(in cell: CellKey, session: SessionState) -> QuestionInfo? {
        let asked = Set(session.askedQuestionIDs)
        let qs = regular.filter { $0.cell == cell && !asked.contains($0.id) }
        if let q = qs.first(where: { $0.timesSeen == 0 && !$0.isGenerated }) { return q }
        if let q = qs.first(where: { $0.timesSeen == 0 && $0.isGenerated }) { return q }
        let dayAgo = now.addingTimeInterval(-86_400)
        if let q = qs.filter({ $0.lastWasCorrect == false && ($0.lastSeen ?? .distantPast) <= dayAgo })
            .min(by: { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }) { return q }
        return qs.min { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }
    }

    /// Records that a question was asked (grading happens in the background).
    static func asked(_ questionID: UUID, in session: inout SessionState) {
        session.askedQuestionIDs.append(questionID)
    }

    /// Applies a grade that arrived for a question asked earlier this session.
    static func graded(cell: CellKey, correct: Bool, in session: inout SessionState) {
        if correct {
            session.pendingReinforcement[cell] = nil
        } else {
            session.pendingReinforcement[cell] = session.askedQuestionIDs.count + reinforcementGap
        }
    }

    /// Records an answer graded immediately (asked + graded).
    static func record(questionID: UUID, cell: CellKey, correct: Bool, in session: inout SessionState) {
        asked(questionID, in: &session)
        graded(cell: cell, correct: correct, in: &session)
    }
}

/// Builds a timed mixed exam across all concepts.
enum ExamBuilder {
    /// Picks an exam: about `minutes` of work at her own pace (`baseline` = her time for a question), with levels in the
    /// shares `difficulty` asks for (falling back to other levels when one runs out), spread across skills.
    static func build(questions all: [QuestionInfo], minutes: Int, difficulty: ExamDifficulty = .mixed,
                      baseline: (QuestionInfo) -> Double = { $0.estimatedSeconds },
                      random: () -> Double = { Double.random(in: 0..<1) }) -> [UUID] {
        let questions = all.filter { !$0.isChallenge }
        guard !questions.isEmpty else { return [] }
        let budget = Double(minutes * 60)
        let avg = questions.map(baseline).reduce(0, +) / Double(questions.count)
        let count = min(questions.count, max(5, min(25, Int(budget / max(avg, 30)))))

        // Questions per level: the asked-for shares, rounded, adding any remainder to the biggest share.
        let shares = difficulty.shares
        var quota = shares.mapValues { Int(($0 * Double(count)).rounded(.down)) }
        let biggest = shares.max { $0.value < $1.value }!.key
        quota[biggest, default: 0] += count - quota.values.reduce(0, +)

        // Per level: round-robin across skills (book order), least-seen first.
        func queues(_ level: Int) -> [[QuestionInfo]] {
            let qs = questions.filter { $0.cell.difficulty == level }
            let byConcept = Dictionary(grouping: qs, by: { $0.cell.conceptOrder })
            return byConcept.keys.sorted().map { key in
                byConcept[key]!.sorted { a, b in
                    if a.timesSeen != b.timesSeen { return a.timesSeen < b.timesSeen }
                    return random() < 0.5
                }
            }
        }
        var byLevel: [Int: [[QuestionInfo]]] = [:]
        for level in Set(questions.map(\.cell.difficulty)) { byLevel[level] = queues(level) }

        var picked: [QuestionInfo] = []
        var spent = 0.0
        func take(from level: Int, upTo n: Int) {
            var taken = 0
            while taken < n, picked.count < count, byLevel[level]?.contains(where: { !$0.isEmpty }) == true {
                for i in byLevel[level]!.indices where !byLevel[level]![i].isEmpty && taken < n && picked.count < count {
                    let q = byLevel[level]![i].removeFirst()
                    if spent + baseline(q) > budget * 1.1 && !picked.isEmpty { continue }
                    picked.append(q); spent += baseline(q); taken += 1
                }
            }
        }
        // Wanted levels first, then (if a level ran out) the nearest other levels, harder first.
        let wanted = shares.keys.sorted { shares[$0]! > shares[$1]! }
        for level in wanted { take(from: level, upTo: quota[level] ?? 0) }
        let fallback = wanted + [3, 2, 1].filter { !wanted.contains($0) }
        for level in fallback where picked.count < count { take(from: level, upTo: count - picked.count) }
        // Present easier questions first, as on a real test.
        return picked.sorted { $0.cell.difficulty < $1.cell.difficulty }.map(\.id)
    }
}
