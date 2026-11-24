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
        let text = FeedbackSummary.text(answers, points: ["Factoring|2": 51])
        XCTAssertTrue(text.contains("RECENT WORK (her last 60 minutes of practice): 6 answers, 3 right."))
        XCTAssertTrue(text.contains("EARLIER WORK: 4 answers, 0 right."))
        XCTAssertTrue(text.contains("- Factoring — Medium: recent 3/6; earlier 0/4; 51 points"))
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

final class AnswerFilterTests: XCTestCase {
    func testOrderNewestOrOldestFirst() {
        let a = UUID(), b = UUID(), c = UUID()
        let dates = [a: Date(timeIntervalSince1970: 300), b: Date(timeIntervalSince1970: 100), c: Date(timeIntervalSince1970: 200)]
        XCTAssertEqual(AnswerFilter.order(dates, newestFirst: true), [a, c, b])
        XCTAssertEqual(AnswerFilter.order(dates, newestFirst: false), [b, c, a])
    }
}


final class MathPlainTextTests: XCTestCase {
    func testMarkdownAndMathBecomeNativeText() {
        let s = String(MathPlainText.attributed("In **minutes**, $x^2 - \\frac{3}{2}$").characters)
        XCTAssertEqual(s, "In minutes, 𝑥² − 3/2")
    }
}

extension MathPlainTextTests {
    func testOperatorsAreSpacedLikeTypesetMath() {
        XCTAssertEqual(MathPlain.render("Solve: $3x^2-41x=-60$"), "Solve: 3𝑥² − 41𝑥 = −60")
        XCTAssertEqual(MathPlain.render("$x=-13, x=8$"), "𝑥 = −13, 𝑥 = 8")
    }
}

final class PaceTests: XCTestCase {
    private func sample(_ seconds: Double, _ estimate: Double = 60, level: Int = 1, skill: String = "a|1", right: Bool = true) -> Pace.Sample {
        Pace.Sample(seconds: seconds, estimate: estimate, level: level, skill: skill, correct: right)
    }

    func testBreaksAreOutliersButSlowQuickQuestionsAreNot() {
        // Usual pace about 1×; one 429 s answer on a 60 s question is a break; 105 s on a 15 s question is under 3 min.
        var xs = [50.0, 55, 60, 65, 70, 58, 62, 66, 54].map { sample($0) }
        xs.append(sample(429))
        xs.append(sample(105, 15))
        let out = Pace.outliers(xs)
        XCTAssertEqual(out, [9])
    }

    func testCleanSecondsReplacesBreakWithTypicalTime() {
        let xs = [50.0, 55, 60, 65, 70, 58, 62, 66, 54, 900].map { sample($0) }
        let clean = Pace.cleanSeconds(xs)
        XCTAssertEqual(clean[0], 50)
        XCTAssertEqual(clean[9], 60, accuracy: 3)    // her typical ratio ≈ 1.0 × 60 s
    }

    func testBaselineUsesSkillThenLevelThenEstimate() {
        let xs = [sample(120, skill: "a|1"), sample(120, skill: "a|1"), sample(120, skill: "a|1"),
                  sample(60, skill: "b|1"), sample(60, skill: "b|1")]
        XCTAssertEqual(Pace.baseline(estimate: 60, level: 1, skill: "a|1", samples: xs), 120, accuracy: 0.01)
        XCTAssertEqual(Pace.baseline(estimate: 60, level: 1, skill: "b|1", samples: xs), 120, accuracy: 0.01) // level median 2×
        XCTAssertEqual(Pace.baseline(estimate: 60, level: 3, skill: "c|3", samples: xs), 60)                   // nothing yet
    }

    func testFeedbackPaceSection() {
        func a(_ m: Int, _ s: Double, right: Bool) -> FeedbackSummary.Answer {
            .init(date: Date(timeIntervalSince1970: Double(m) * 60), seconds: s, estimate: 60, rawSeconds: s, skill: "Factoring",
                  level: 1, verdict: right ? .correct : .incorrect, mistake: right ? nil : .careless, errorStep: "", helped: false)
        }
        let answers = (0..<6).map { a($0 * 2, 120, right: true) } + (6..<9).map { a($0 * 2, 30, right: false) }
        let text = FeedbackSummary.text(answers)
        XCTAssertTrue(text.contains("PACE IN PRACTICE"))
        XCTAssertTrue(text.contains("- Basic: recent"))
        XCTAssertTrue(text.contains("right answers 2.0×, wrong answers 0.5×"))
    }
}

final class ExamBuilderMixTests: XCTestCase {
    func testHardestIsMostlyHardAndFallsBackWhenAShortage() {
        var qs: [QuestionInfo] = []
        for c in 0..<4 { for d in 1...3 { for k in 0..<5 {
            qs.append(QuestionInfo(id: UUID(), cell: CellKey(conceptID: UUID(), conceptOrder: c, difficulty: d), isGenerated: false,
                                   estimatedSeconds: 60, timesSeen: k, lastSeen: nil, lastWasCorrect: nil))
        } } }
        let byID = Dictionary(uniqueKeysWithValues: qs.map { ($0.id, $0) })
        let ids = ExamBuilder.build(questions: qs, minutes: 20, difficulty: .hardest, random: { 0.3 })
        let levels = ids.map { byID[$0]!.cell.difficulty }
        XCTAssertEqual(levels.count, 20)
        XCTAssertEqual(levels.filter { $0 == 3 }.count, 15)
        XCTAssertEqual(levels.filter { $0 == 1 }.count, 0)
        // Only 2 Hard questions available → the rest comes from Medium, then Basic.
        let fewHard = qs.filter { $0.cell.difficulty != 3 } + qs.filter { $0.cell.difficulty == 3 }.prefix(2)
        let ids2 = ExamBuilder.build(questions: Array(fewHard), minutes: 10, difficulty: .hardest, random: { 0.3 })
        XCTAssertEqual(ids2.count, 10)
    }
}

final class DraftStoreTests: XCTestCase {
    func testDraftRoundTripAndClear() {
        let key = "test-\(UUID())"
        let q = UUID()
        DraftStore.save(Draft(questionIDs: [q], ink: [q: Data([1, 2, 3])], seconds: [q: 42], index: 0), key: key)
        let d = DraftStore.load(key)
        XCTAssertEqual(d?.ink[q], Data([1, 2, 3]))
        XCTAssertEqual(d?.seconds[q], 42)
        DraftStore.clear(key)
        XCTAssertNil(DraftStore.load(key))
    }
}

@MainActor
final class BookLookTests: XCTestCase {
    func testLookingAtTheBookCountsAsAHint() {
        let a = Attempt(mode: .practice)
        XCTAssertFalse(a.usedHint)
        a.lookedAtBook = true
        XCTAssertTrue(a.usedHint)
    }
}
