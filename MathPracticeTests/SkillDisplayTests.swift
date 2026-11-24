import XCTest
@testable import MathPractice

final class SkillDisplayTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    private func rightInARow(_ n: Int, seconds: Double = 30) -> SkillProgress {
        var p = SkillProgress()
        for _ in 0..<n { p = MasteryModel.apply(correct: true, mistake: nil, seconds: seconds, to: p, now: now) }
        return p
    }

    func testRightAnswersToMaster() {
        XCTAssertEqual(MasteryModel.rightAnswersToMaster(SkillProgress()), 5)
        XCTAssertEqual(MasteryModel.rightAnswersToMaster(rightInARow(3)), 2)
        XCTAssertEqual(MasteryModel.rightAnswersToMaster(rightInARow(5)), 0)
        var p = rightInARow(8)
        p = MasteryModel.apply(correct: false, mistake: .careless, seconds: nil, to: p, now: now)
        XCTAssertGreaterThan(MasteryModel.rightAnswersToMaster(p), 0)
    }

    func testBarShowsOneHundredOnlyWhenMastered() {
        XCTAssertEqual(Int(SkillBarsGrid.points(rightInARow(4))), 94)
        XCTAssertEqual(Int(SkillBarsGrid.points(rightInARow(5))), 100)
        var almost = SkillProgress(); almost.mastery = 0.7999
        XCTAssertLessThan(Int(SkillBarsGrid.points(almost)), 100)
    }
}

final class ChapterScoreTests: XCTestCase {
    func testHistoryHasAPointEveryThirtyMinutes() {
        let cell = CellKey(conceptID: UUID(), conceptOrder: 0, difficulty: 1)
        let other = CellKey(conceptID: UUID(), conceptOrder: 1, difficulty: 1)
        let start = Date(timeIntervalSince1970: 1_000_000)
        // 10 right answers of 10 minutes each = 100 minutes.
        let answers = (0..<10).map { i in
            ChapterScore.Answer(date: start.addingTimeInterval(Double(i) * 600), cell: cell, correct: true, mistake: nil, seconds: 600)
        }
        let points = ChapterScore.history(answers, cells: [cell, other])
        XCTAssertEqual(points.map(\.hours), [0, 0.5, 1, 1.5, 100.0 / 60])
        XCTAssertEqual(points[1].score, 100 * MasteryModel.scoreAfter(rightInARow: 3) / 0.8 / 2, accuracy: 1e-9)
        XCTAssertEqual(points.last!.score, 50, accuracy: 1e-9)   // one level at star level (capped), the other untried
    }
}

extension ChapterScoreTests {
    func testScoreBeforeADateIgnoresLaterAnswers() {
        let cell = CellKey(conceptID: UUID(), conceptOrder: 0, difficulty: 1)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let answers = (0..<4).map { i in
            ChapterScore.Answer(date: start.addingTimeInterval(Double(i) * 600), cell: cell, correct: true, mistake: nil, seconds: 60)
        }
        XCTAssertEqual(ChapterScore.score(answers, cells: [cell], before: start.addingTimeInterval(1_000)),
                       100 * MasteryModel.scoreAfter(rightInARow: 2) / 0.8, accuracy: 1e-9)
    }
}

extension ChapterScoreTests {
    func testTimeOfUngradedAnswersCountsAsPracticeTime() {
        let cell = CellKey(conceptID: UUID(), conceptOrder: 0, difficulty: 1)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let answers = [
            ChapterScore.Answer(date: start, cell: cell, correct: true, mistake: nil, seconds: 1200),
            ChapterScore.Answer(date: start.addingTimeInterval(1300), cell: nil, correct: false, mistake: nil, seconds: 1200),
        ]
        let points = ChapterScore.history(answers, cells: [cell])
        XCTAssertEqual(points.last!.hours, 2400.0 / 3600, accuracy: 1e-9)
        XCTAssertEqual(points.last!.score, 100 * MasteryModel.scoreAfter(rightInARow: 1) / 0.8, accuracy: 1e-9)
    }
}

