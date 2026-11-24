import XCTest
@testable import MathPractice

final class FeedbackSummaryTests: XCTestCase {
    private func answer(_ minute: Int, seconds: Double = 600, skill: String = "Factoring", level: Int = 2,
                        right: Bool, mistake: MistakeType? = nil, step: String = "") -> FeedbackSummary.Answer {
        .init(date: Date(timeIntervalSince1970: Double(minute) * 60), seconds: seconds, skill: skill, level: level,
              verdict: right ? .correct : .incorrect, mistake: right ? nil : mistake, errorStep: step, helped: false)
    }

    func testRecentIsTheLastHourOfPractice() {
        // 10 answers of 10 minutes: the last 6 are the recent hour.
        let answers = (0..<10).map { answer($0 * 10, right: true) }
        let (earlier, recent) = FeedbackSummary.split(answers)
        XCTAssertEqual(earlier.count, 4)
        XCTAssertEqual(recent.count, 6)
    }

    func testTextCountsRecentAndEarlierSeparately() {
        var answers = (0..<4).map { answer($0 * 10, right: false, mistake: .careless, step: "old slip \($0)") }
        answers += (4..<10).map { answer($0 * 10, right: $0 % 2 == 0, mistake: .incomplete, step: "stopped early \($0)") }
        let text = FeedbackSummary.text(answers, steps: ["Factoring|2": 2])
        XCTAssertTrue(text.contains("RECENT WORK (her last 60 minutes of practice): 6 answers, 3 right."))
        XCTAssertTrue(text.contains("EARLIER WORK: 4 answers, 0 right."))
        XCTAssertTrue(text.contains("- Factoring — Medium: recent 3/6; earlier 0/4; 2 of 5 steps"))
        XCTAssertTrue(text.contains("[Factoring — Medium; Incomplete] stopped early 5"))
        XCTAssertTrue(text.contains("[Factoring — Medium; Careless slip] old slip 0"))
    }

    func testDue() {
        XCTAssertFalse(FeedbackSummary.isDue(practiceSeconds: 600, answered: 9, lastFeedbackAt: nil))
        XCTAssertTrue(FeedbackSummary.isDue(practiceSeconds: 600, answered: 10, lastFeedbackAt: nil))
        XCTAssertFalse(FeedbackSummary.isDue(practiceSeconds: 3000, answered: 50, lastFeedbackAt: 1500))
        XCTAssertTrue(FeedbackSummary.isDue(practiceSeconds: 3300, answered: 50, lastFeedbackAt: 1500))
    }
}
