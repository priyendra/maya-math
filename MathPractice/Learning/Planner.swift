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
}

/// State of the current 30-minute session.
struct SessionState {
    var askedQuestionIDs: [UUID] = []
    /// Cells answered wrong this session → index (in askedQuestionIDs) after which to re-practice.
    var pendingReinforcement: [CellKey: Int] = [:]
    var lastCategory: PickCategory?
}

enum PickCategory: String, Equatable {
    case reinforcement, weak, review, stretch
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

    var allCells: [CellKey] {
        Array(Set(questions.map(\.cell))).sorted {
            ($0.conceptOrder, $0.difficulty) < ($1.conceptOrder, $1.difficulty)
        }
    }

    func progress(_ cell: CellKey) -> SkillProgress { skills[cell] ?? SkillProgress() }

    func estimate(_ cell: CellKey) -> Double {
        let qs = questions.filter { $0.cell == cell }
        guard !qs.isEmpty else { return 120 }
        return qs.map(\.estimatedSeconds).reduce(0, +) / Double(qs.count)
    }

    func isMastered(_ cell: CellKey) -> Bool {
        MasteryModel.isMastered(progress(cell), estimate: estimate(cell))
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
            targets.contains(cell) && questions.filter { $0.cell == cell && $0.timesSeen == 0 }.count < minUnseen
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
        else { order = [.stretch, .weak, .review] }

        for category in order {
            let pool: [CellKey]
            switch category {
            case .weak: pool = weakCells
            case .review: pool = reviewCells
            case .stretch: pool = stretchCells
            case .reinforcement: pool = []
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

    /// Within a cell: unseen book → unseen generated → previously wrong (≥1 day ago) → least recently seen.
    /// Never repeats a question already asked this session.
    func pickQuestion(in cell: CellKey, session: SessionState) -> QuestionInfo? {
        let asked = Set(session.askedQuestionIDs)
        let qs = questions.filter { $0.cell == cell && !asked.contains($0.id) }
        if let q = qs.first(where: { $0.timesSeen == 0 && !$0.isGenerated }) { return q }
        if let q = qs.first(where: { $0.timesSeen == 0 && $0.isGenerated }) { return q }
        let dayAgo = now.addingTimeInterval(-86_400)
        if let q = qs.filter({ $0.lastWasCorrect == false && ($0.lastSeen ?? .distantPast) <= dayAgo })
            .min(by: { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }) { return q }
        return qs.min { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }
    }

    /// Records an answer in the session (schedules in-session re-practice after a miss).
    static func record(questionID: UUID, cell: CellKey, correct: Bool, in session: inout SessionState) {
        session.askedQuestionIDs.append(questionID)
        if correct {
            session.pendingReinforcement[cell] = nil
        } else {
            session.pendingReinforcement[cell] = session.askedQuestionIDs.count + reinforcementGap
        }
    }
}

/// Builds a timed mixed exam across all concepts.
enum ExamBuilder {
    static func build(questions: [QuestionInfo], minutes: Int, random: () -> Double = { Double.random(in: 0..<1) }) -> [UUID] {
        guard !questions.isEmpty else { return [] }
        let budget = Double(minutes * 60)
        let avg = questions.map(\.estimatedSeconds).reduce(0, +) / Double(questions.count)
        let count = min(questions.count, max(5, min(25, Int(budget / max(avg, 30)))))

        // Round-robin across concepts (book order), preferring questions seen least, mixing difficulties.
        let byConcept = Dictionary(grouping: questions, by: { $0.cell.conceptOrder })
        var queues: [[QuestionInfo]] = byConcept.keys.sorted().map { key in
            byConcept[key]!.sorted { a, b in
                if a.timesSeen != b.timesSeen { return a.timesSeen < b.timesSeen }
                return random() < 0.5
            }
        }
        var picked: [QuestionInfo] = []
        var spent = 0.0
        while picked.count < count, queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where !queues[i].isEmpty && picked.count < count {
                let q = queues[i].removeFirst()
                if spent + q.estimatedSeconds > budget * 1.1 && !picked.isEmpty { continue }
                picked.append(q)
                spent += q.estimatedSeconds
            }
        }
        // Present easier questions first, as on a real test.
        return picked.sorted { $0.cell.difficulty < $1.cell.difficulty }.map(\.id)
    }
}
