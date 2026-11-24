import XCTest

final class RegradeUITests: XCTestCase {
    /// An answer to check shows Claude's answers as math, and "Grade it again" sends it back for grading.
    func testAnswerToCheckRendersMathAndRegrades() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedToCheck", "-openFirstChapter"]
        app.launch()
        let answers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My answers'")).firstMatch
        XCTAssertTrue(answers.waitForExistence(timeout: 15))
        answers.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '75s'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let regrade = app.buttons["regrade"]
        XCTAssertTrue(regrade.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'frac'")).firstMatch.exists)
        snap(app, "answer-to-check")
        regrade.tap()
        XCTAssertTrue(app.staticTexts["Checking your answer again…"].waitForExistence(timeout: 5))
        snap(app, "answer-regrading")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}
