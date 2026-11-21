import XCTest

final class HelpAndPauseUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-openFirstChapter", "-fakeHelp"] + extra
        app.launch()
        let practice = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Practice'")).firstMatch
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        practice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["writingCanvas"].waitForExistence(timeout: 10))
        return app
    }

    private func draw(_ app: XCUIApplication) {
        let canvas = app.descendants(matching: .any)["writingCanvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)),
                   withVelocity: 200, thenHoldForDuration: 0.2)
        sleep(1)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testStuckGivesHintThenSolutionOnSameQuestion() {
        let app = launch()
        app.buttons["I'm stuck"].tap()
        XCTAssertTrue(app.staticTexts["Hint"].waitForExistence(timeout: 5), "hint not shown")
        sleep(1)
        shot(app, "hint")
        // Still on the same question, can keep writing; Next needs ink.
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        draw(app)
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        app.buttons["Show solution"].tap()
        XCTAssertTrue(app.staticTexts["Solution"].waitForExistence(timeout: 5), "solution not shown")
        sleep(2)
        shot(app, "solution")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["I'm stuck"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Hint"].exists)
    }

    func testPauseKeepsInkAndPreviousShowsEarlierQuestions() {
        let app = launch()
        draw(app)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Taking a break"].waitForExistence(timeout: 3))
        shot(app, "paused")
        app.buttons.matching(identifier: "Resume").firstMatch.tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next"].isEnabled, "ink lost after pause")
        app.buttons["Next"].tap()
        sleep(1)
        app.buttons["Previous"].tap()
        XCTAssertTrue(app.staticTexts["Earlier questions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Question 1"].exists)
        shot(app, "previous")
        app.buttons.matching(identifier: "Resume").firstMatch.tap()
        XCTAssertTrue(app.buttons["I'm stuck"].waitForExistence(timeout: 5))
    }

    func testLongSolutionScrollsInsideItsBox() {
        let app = launch(["-longHelp"])
        app.buttons["I'm stuck"].tap()
        XCTAssertTrue(app.buttons["Show solution"].waitForExistence(timeout: 5))
        app.buttons["Show solution"].tap()
        XCTAssertTrue(app.staticTexts["Solution"].waitForExistence(timeout: 5))
        sleep(2)
        shot(app, "long-solution")
        let box = app.staticTexts["Solution"]
        box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 300))
            .press(forDuration: 0.05, thenDragTo: box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        sleep(1)
        shot(app, "long-solution-scrolled")
    }
}

final class EndSessionUITests: XCTestCase {
    func testEndAsksWithCenteredAlertAndKeepPracticingIsSafe() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-openFirstChapter"]
        app.launch()
        let practice = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Practice'")).firstMatch
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        practice.tap()
        let canvas = app.descendants(matching: .any)["writingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)),
                   withVelocity: 200, thenHoldForDuration: 0.2)
        app.buttons["Next"].tap()
        app.buttons["End"].tap()
        let alert = app.alerts["End this session?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "end-alert"; a.lifetime = .keepAlways; add(a)
        alert.buttons["Keep practicing"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 3), "Keep practicing should return to the question")
        app.buttons["End"].tap()
        app.alerts["End this session?"].buttons["End session"].tap()
        XCTAssertTrue(app.staticTexts["Checking your last answers…"].waitForExistence(timeout: 5)
                      || app.staticTexts["How you did"].waitForExistence(timeout: 5))
    }
}
