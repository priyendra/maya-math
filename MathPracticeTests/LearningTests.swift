import XCTest
@testable import MathPractice

final class MasteryModelTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testCorrectRaisesMasteryAndGrowsInterval() {
        var p = SkillProgress()
        p = MasteryModel.apply(correct: true, mistake: nil, seconds: 60, to: p, now: now)
        XCTAssertEqual(p.mastery, 0.3, accuracy: 1e-9)
        XCTAssertEqual(p.intervalDays, 1)
        p = MasteryModel.apply(correct: true, mistake: nil, seconds: 60, to: p, now: now)
        XCTAssertEqual(p.mastery, 0.51, accuracy: 1e-9)
        XCTAssertEqual(p.intervalDays, 3)
        XCTAssertEqual(p.nextDue, now.addingTimeInterval(3 * 86_400))
    }

    func testCarelessMistakeCostsLessThanConceptual() {
        let base = SkillProgress(mastery: 0.8)
        let careless = MasteryModel.apply(correct: false, mistake: .careless, seconds: nil, to: base, now: now)
        let conceptual = MasteryModel.apply(correct: false, mistake: .conceptual, seconds: nil, to: base, now: now)
        XCTAssertGreaterThan(careless.mastery, conceptual.mastery)
        XCTAssertEqual(careless.careless, 1)
        XCTAssertEqual(conceptual.intervalDays, 0)
        XCTAssertEqual(conceptual.nextDue, now.addingTimeInterval(86_400))
    }

    func testMasteryIsAccuracyOnly() {
        var p = SkillProgress()
        for _ in 0..<4 { p = MasteryModel.apply(correct: true, mistake: nil, seconds: 900, to: p, now: now) }
        XCTAssertFalse(MasteryModel.isMastered(p))
        p = MasteryModel.apply(correct: true, mistake: nil, seconds: 900, to: p, now: now)
        XCTAssertTrue(MasteryModel.isMastered(p))          // 5 right in a row, however slow
        p = MasteryModel.apply(correct: false, mistake: .careless, seconds: nil, to: p, now: now)
        XCTAssertFalse(MasteryModel.isMastered(p))         // any wrong answer drops below 100
    }

    func testExamTarget() {
        var p = SkillProgress()
        for s in [200.0, 180, 160, 150] { p = MasteryModel.apply(correct: true, mistake: nil, seconds: s, to: p, now: now) }
        // Slower than estimate → target is the estimate.
        XCTAssertEqual(MasteryModel.targetSeconds(estimate: 120, progress: p), 120)
        // Faster than estimate → target tightens to 90% of her median.
        XCTAssertEqual(MasteryModel.targetSeconds(estimate: 300, progress: p), 0.9 * 170, accuracy: 1e-9)
        // Never tighter than half the estimate.
        XCTAssertEqual(MasteryModel.targetSeconds(estimate: 400, progress: p), 200, accuracy: 1e-9)
    }
}

final class PlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let c1 = UUID(), c2 = UUID()

    func q(_ cell: CellKey, seen: Int = 0, generated: Bool = false, lastCorrect: Bool? = nil, lastSeen: Date? = nil) -> QuestionInfo {
        QuestionInfo(id: UUID(), cell: cell, isGenerated: generated, estimatedSeconds: 120,
                     timesSeen: seen, lastSeen: lastSeen, lastWasCorrect: lastCorrect)
    }

    func testChallengeOnlyAfterHardestLevelMasteredAndNeverInExams() {
        let a1 = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        var challenge = q(a1); challenge.isChallenge = true
        let regular = q(a1)
        let fresh = Planner(questions: [regular, challenge], skills: [:], now: now)
        XCTAssertEqual(fresh.allCells, [a1])
        XCTAssertNil(fresh.pickChallenge(session: SessionState()))
        XCTAssertNotEqual(fresh.next(session: SessionState(), random: { 0.99 })?.questionID, challenge.id)

        var mastered = SkillProgress()
        for _ in 0..<5 { mastered = MasteryModel.apply(correct: true, mistake: nil, seconds: 60, to: mastered, now: now) }
        let ready = Planner(questions: [regular, challenge], skills: [a1: mastered], now: now)
        XCTAssertEqual(ready.next(session: SessionState(), random: { 0.99 })?.category, .challenge)
        XCTAssertFalse(ExamBuilder.build(questions: [regular, challenge], minutes: 30).contains(challenge.id))
    }

    func testHigherDifficultyLockedUntilLowerProgresses() {
        let a1 = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        let a2 = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 2)
        let planner = Planner(questions: [q(a1), q(a2)], skills: [:], now: now)
        XCTAssertTrue(planner.isOpen(a1))
        XCTAssertFalse(planner.isOpen(a2))
        let unlocked = Planner(questions: [q(a1), q(a2)], skills: [a1: SkillProgress(mastery: 0.7)], now: now)
        XCTAssertTrue(unlocked.isOpen(a2))
    }

    func testWeakCellsOrderedByMasteryThenBookOrder() {
        let a = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        let b = CellKey(conceptID: c2, conceptOrder: 1, difficulty: 1)
        let planner = Planner(questions: [q(a), q(b)], skills: [a: SkillProgress(mastery: 0.5), b: SkillProgress(mastery: 0.1)], now: now)
        XCTAssertEqual(planner.weakCells, [b, a])
    }

    func testPrefersUnseenBookThenGenerated() {
        let a = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        let seen = q(a, seen: 1, lastCorrect: true, lastSeen: now)
        let gen = q(a, generated: true)
        let book = q(a)
        let planner = Planner(questions: [seen, gen, book], skills: [:], now: now)
        XCTAssertEqual(planner.pickQuestion(in: a, session: SessionState())?.id, book.id)
        var s = SessionState(); s.askedQuestionIDs = [book.id]
        XCTAssertEqual(planner.pickQuestion(in: a, session: s)?.id, gen.id)
    }

    func testWrongAnswerIsReinforcedAfterGap() {
        let a = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        let b = CellKey(conceptID: c2, conceptOrder: 1, difficulty: 1)
        let qs = [q(a), q(a), q(b), q(b), q(b)]
        let planner = Planner(questions: qs, skills: [a: SkillProgress(mastery: 0.5)], now: now)
        var session = SessionState()
        Planner.record(questionID: qs[0].id, cell: a, correct: false, in: &session)
        // Immediately after: not yet reinforcement.
        XCTAssertNotEqual(planner.next(session: session, random: { 0 })?.category, .reinforcement)
        Planner.record(questionID: qs[2].id, cell: b, correct: true, in: &session)
        Planner.record(questionID: qs[3].id, cell: b, correct: true, in: &session)
        let pick = planner.next(session: session, random: { 0 })
        XCTAssertEqual(pick?.category, .reinforcement)
        XCTAssertEqual(pick?.questionID, qs[1].id)
    }

    func testNeverRepeatsWithinSessionWhenAlternativesExist() {
        let a = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        let qs = [q(a), q(a)]
        let planner = Planner(questions: qs, skills: [:], now: now)
        var session = SessionState()
        let first = planner.next(session: session, random: { 0 })!
        Planner.record(questionID: first.questionID, cell: a, correct: true, in: &session)
        XCTAssertNotEqual(planner.next(session: session, random: { 0 })?.questionID, first.questionID)
    }

    func testCellsNeedingVariants() {
        let a = CellKey(conceptID: c1, conceptOrder: 0, difficulty: 1)
        let planner = Planner(questions: [q(a, seen: 2, lastCorrect: false, lastSeen: now)], skills: [:], now: now)
        XCTAssertEqual(planner.cellsNeedingVariants(), [a])
    }

    func testExamCoversConceptsWithinBudget() {
        var qs: [QuestionInfo] = []
        for (order, c) in [c1, c2].enumerated() {
            for d in 1...3 { for _ in 0..<4 { qs.append(q(CellKey(conceptID: c, conceptOrder: order, difficulty: d))) } }
        }
        let ids = ExamBuilder.build(questions: qs, minutes: 20, random: { 0.3 })
        XCTAssertEqual(ids.count, 10) // 1200s / 120s
        let picked = qs.filter { ids.contains($0.id) }
        XCTAssertEqual(Set(picked.map(\.cell.conceptID)).count, 2)
    }
}
