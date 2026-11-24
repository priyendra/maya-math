import XCTest

final class ExamHistoryUITests: XCTestCase {
    /// My exams lists a past exam with its settings and score; tapping it shows its results.
    func testExamHistoryListsSettingsAndOpensResults() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedExam", "-openFirstChapter"]
        app.launch()
        let tile = app.buttons["examsTile"].firstMatch
        for _ in 0..<3 where !tile.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(tile.exists)
        tile.tap()
        let row = app.buttons["exam-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Hard · Fast · 20 min"), row.label)
        XCTAssertTrue(row.label.contains("1/2 right"), row.label)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "my-exams"; a.lifetime = .keepAlways; add(a)
        row.tap()
        XCTAssertTrue(app.staticTexts["Question by question"].waitForExistence(timeout: 5))
    }
}
