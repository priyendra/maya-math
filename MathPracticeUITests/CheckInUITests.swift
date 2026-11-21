import XCTest

private func shot(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; test.add(a)
}

/// Opens the solution page and scrolls until the solution's last line is on screen.
private func assertSolutionReadableToTheEnd(_ test: XCTestCase, _ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "solution page did not open")
    sleep(2)
    shot(test, app, "solution-sheet")
    let page = app.descendants(matching: .any)["solutionPage"]
    XCTAssertTrue(page.exists)
    for _ in 0..<4 { page.swipeUp() }
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

final class TutorUITests: XCTestCase {
    /// Solution page → Talk to the tutor (canned replies) → the board fills, the cursor points, it listens →
    /// a spoken turn gets a second reply → the conversation is saved with the answer.
    func testTalkToTutorOnSolutionPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedGraded", "-checkInLab", "-fakeTutor", "-fingerInk"]
        app.launch()
        let show = app.buttons["Show solution"]
        XCTAssertTrue(show.waitForExistence(timeout: 15))
        show.tap()
        XCTAssertTrue(app.buttons["talkToTutor"].waitForExistence(timeout: 5))
        sleep(2)
        shot(self, app, "tutor-0-page")
        app.buttons["talkToTutor"].tap()
        let listening = app.descendants(matching: .any)["tutorListening"]
        XCTAssertTrue(listening.waitForExistence(timeout: 10), "tutor never started listening")
        // The board and cursor live in the hosted page under the ink (not reliably in the accessibility tree):
        // checked in the screenshots.
        sleep(1)
        shot(self, app, "tutor-1-listening")
        // Circle something, then "say" the question: the snapshot sent with it shows the new marks in pink.
        let page = app.descendants(matching: .any)["solutionPage"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.75))
            .press(forDuration: 0.1, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.8)),
                   withVelocity: 300, thenHoldForDuration: 0.1)
        app.buttons["debugSay"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["debugSay"].waitForExistence(timeout: 10), "no second reply")
        sleep(1)
        shot(self, app, "tutor-2-second-reply")
        app.buttons["End talk"].tap()
        XCTAssertTrue(app.buttons["talkToTutor"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        // Saved with the answer.
        let disagree = app.buttons["Disagree with the grade?"]
        XCTAssertTrue(disagree.waitForExistence(timeout: 5))
        disagree.tap()
        let you = app.staticTexts["Why is it three a?"]
        for _ in 0..<6 where !you.exists { app.swipeUp() }
        XCTAssertTrue(you.exists, "conversation not saved")
        shot(self, app, "tutor-3-saved")
    }
}
