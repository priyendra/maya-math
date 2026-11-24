import XCTest

final class ExamHistoryUITests: XCTestCase {
    /// My exams lists a past exam with its settings and score; tapping it shows its results.
    func testExamHistoryListsSettingsAndOpensResults() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedExam", "-openFirstChapter"]
        app.launch()
        let exam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam mode'")).firstMatch
        XCTAssertTrue(exam.waitForExistence(timeout: 15))
        exam.tap()
        let link = app.buttons["myExams"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let row = app.buttons["exam-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Hard · Fast · 20 min"), row.label)
        XCTAssertTrue(row.label.contains("1/2 right"), row.label)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "my-exams"; a.lifetime = .keepAlways; add(a)
        row.tap()
        XCTAssertTrue(app.staticTexts["Question by question"].waitForExistence(timeout: 5))
    }

    /// The exam hands itself in at the time limit, with no grace period.
    func testExamClosesAtTimeLimit() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-openFirstChapter", "-examSeconds", "8"]
        app.launch()
        let exam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam mode'")).firstMatch
        XCTAssertTrue(exam.waitForExistence(timeout: 15))
        exam.tap()
        app.buttons["Start exam"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["examClock"].waitForExistence(timeout: 5))
        let up = app.descendants(matching: .any)["timesUp"].waitForExistence(timeout: 15)
        if !up { let a = XCTAttachment(screenshot: app.screenshot()); a.name = "after-limit"; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(up)
    }
}
