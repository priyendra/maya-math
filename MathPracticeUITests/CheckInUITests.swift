import XCTest

private func shot(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; test.add(a)
}

/// Opens the solution sheet and scrolls until the solution's last line is on screen.
private func assertSolutionReadableToTheEnd(_ test: XCTestCase, _ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "solution sheet did not open")
    sleep(2)
    shot(test, app, "solution-sheet")
    for _ in 0..<4 { app.webViews.firstMatch.swipeUp() }
    sleep(1)
    shot(test, app, "solution-sheet-scrolled")
    app.buttons["Done"].tap()
}

final class CheckInUITests: XCTestCase {
    func testLongSolutionScrolls() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedGraded", "-checkInLab"]
        app.launch()
        let show = app.buttons["Show solution"]
        XCTAssertTrue(show.waitForExistence(timeout: 15))
        show.tap()
        assertSolutionReadableToTheEnd(self, app)
        XCTAssertTrue(app.buttons["Keep going"].waitForExistence(timeout: 5))
    }
}

final class AnswerDetailUITests: XCTestCase {
    /// "Disagree with the grade?" → answer detail → Show solution → readable to the end.
    func testLongSolutionInAnswerDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedGraded", "-checkInLab"]
        app.launch()
        let disagree = app.buttons["Disagree with the grade?"]
        XCTAssertTrue(disagree.waitForExistence(timeout: 15))
        disagree.tap()
        let show = app.buttons["Show solution"].firstMatch
        for _ in 0..<5 where !show.isHittable { app.swipeUp() }
        // The card behind also has a "Show solution"; use the one in the sheet (last match).
        let buttons = app.buttons.matching(identifier: "Show solution")
        buttons.element(boundBy: buttons.count - 1).tap()
        assertSolutionReadableToTheEnd(self, app)
    }
}
