import XCTest
@testable import MathPractice

final class SkillDisplayTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    private func rightInARow(_ n: Int, seconds: Double = 30) -> SkillProgress {
        var p = SkillProgress()
        for _ in 0..<n { p = MasteryModel.apply(correct: true, mistake: nil, seconds: seconds, to: p, now: now) }
        return p
    }

    func testDotsCountRightAnswersInARow() {
        for n in 0...5 { XCTAssertEqual(MasteryModel.dots(rightInARow(n).mastery), n) }
        XCTAssertEqual(MasteryModel.dots(0.66), 3)   // stored values are rounded on the device
        XCTAssertEqual(MasteryModel.dots(0.6), 2)
    }

    func testRightAnswersToStar() {
        XCTAssertEqual(MasteryModel.rightAnswersToStar(SkillProgress()), 5)
        XCTAssertEqual(MasteryModel.rightAnswersToStar(rightInARow(3)), 2)
        XCTAssertEqual(MasteryModel.rightAnswersToStar(rightInARow(5)), 0)
        // Last answer wrong: never 0, even with a high score.
        var p = rightInARow(8)
        p = MasteryModel.apply(correct: false, mistake: .careless, seconds: nil, to: p, now: now)
        XCTAssertGreaterThan(MasteryModel.rightAnswersToStar(p), 0)
    }

    func testStages() {
        XCTAssertEqual(SkillStage.of(SkillProgress(), mastered: false), .new)
        XCTAssertEqual(SkillStage.of(rightInARow(1), mastered: false), .gettingThere)   // 30%
        XCTAssertEqual(SkillStage.of(rightInARow(3), mastered: false), .almost)
        var low = rightInARow(1)
        low = MasteryModel.apply(correct: false, mistake: .conceptual, seconds: nil, to: low, now: now)
        XCTAssertEqual(SkillStage.of(low, mastered: false), .learning)
        XCTAssertEqual(SkillStage.of(rightInARow(5), mastered: true), .mastered)
    }

    func testSlowIsHeldBackBySpeed() {
        let p = rightInARow(5, seconds: 200)
        XCTAssertTrue(MasteryModel.heldBackBySpeed(p, estimate: 60))
        XCTAssertFalse(MasteryModel.heldBackBySpeed(p, estimate: 200))
        XCTAssertFalse(MasteryModel.heldBackBySpeed(rightInARow(3, seconds: 200), estimate: 60))
    }

    func testSummaryCountsAnswersCellsAndReviews() {
        let a = UUID(), b = UUID()
        let cells = [CellKey(conceptID: a, conceptOrder: 0, difficulty: 1), CellKey(conceptID: a, conceptOrder: 0, difficulty: 2),
                     CellKey(conceptID: b, conceptOrder: 1, difficulty: 1)]
        let questions = cells.enumerated().map { i, c in
            QuestionInfo(id: UUID(), cell: c, isGenerated: false, estimatedSeconds: 60, timesSeen: 0, lastSeen: nil, lastWasCorrect: nil)
        }
        var mastered = rightInARow(5)
        mastered.nextDue = now.addingTimeInterval(3_600)
        let planner = Planner(questions: questions, skills: [cells[0]: mastered, cells[1]: rightInARow(3)], now: now)
        let yesterday = now.addingTimeInterval(-86_400)
        let answers = [
            ProgressSummary.Answer(date: yesterday, counted: true, correct: true, seconds: 60),
            ProgressSummary.Answer(date: yesterday, counted: true, correct: false, seconds: 120),
            ProgressSummary.Answer(date: now, counted: true, correct: true, seconds: 60),
            ProgressSummary.Answer(date: now, counted: false, correct: false, seconds: 60),
        ]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = ProgressSummary(answers: answers, planner: planner, now: now, calendar: cal)
        XCTAssertEqual(s.answered, 3)
        XCTAssertEqual(s.right, 2)
        XCTAssertEqual(s.answeredToday, 1)
        XCTAssertEqual(s.accuracyToday, 1)
        XCTAssertEqual(s.seconds, 300)
        XCTAssertEqual(s.days, 2)
        XCTAssertEqual(s.totalCells, 3)
        XCTAssertEqual(s.triedCells, 2)
        XCTAssertEqual(s.masteredCells, 1)
        XCTAssertEqual(s.almostCells, 1)
        XCTAssertEqual(s.reviewDueToday, 1)
    }
}
