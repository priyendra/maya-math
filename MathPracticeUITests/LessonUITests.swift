import XCTest

final class LessonUITests: XCTestCase {
    /// Chapter → Lessons → start a lesson (canned scripts): the part is narrated, she asks a question and it carries on,
    /// her first answer is wrong (the tutor goes over it, then a second problem), then right, then part 2 … lesson done.
    func testTakeALesson() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedLessons", "-openFirstChapter", "-fakeTutor", "-fingerInk", "-fakeWrongOnce"]
        app.launch()
        let tile = app.buttons["lessonsTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let row = app.buttons.matching(identifier: "lessonRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not in lessons (1)"].exists)
        row.tap()
        shot(self, app, "lesson-0-list")
        app.buttons["Start lesson"].tap()

        // Part 1 narrated, then "any questions?" (listening). Ask one; the reply ends with CONTINUE → your turn.
        let say = app.buttons["debugSay"]
        XCTAssertTrue(say.waitForExistence(timeout: 15), "never reached the questions pause")
        shot(self, app, "lesson-1-questions")
        say.tap()
        let check = app.buttons["lessonCheck"]
        XCTAssertTrue(check.waitForExistence(timeout: 15), "no your-turn problem after the question")
        sleep(2)
        write(app)
        shot(self, app, "lesson-2-your-turn")
        check.tap()
        // Wrong first time: the tutor goes over it (canned reply ends with CONTINUE) → second problem.
        let second = app.buttons["lessonCheck"]
        sleep(4)
        XCTAssertTrue(second.waitForExistence(timeout: 15), "no second try")
        shot(self, app, "lesson-3-review")
        write(app)
        second.tap()

        // Part 2: questions pause again → Go on → your turn → right → lesson done.
        let goOn = app.buttons["lessonGoOn"]
        XCTAssertTrue(goOn.waitForExistence(timeout: 20), "part 2 never got to the questions pause")
        goOn.tap()
        XCTAssertTrue(app.buttons["lessonCheck"].waitForExistence(timeout: 15))
        sleep(2)
        write(app)
        app.buttons["lessonCheck"].tap()
        XCTAssertTrue(app.buttons["Practice this lesson"].waitForExistence(timeout: 20), "lesson never finished")
        XCTAssertTrue(app.buttons["Next lesson"].exists)
        sleep(1)
        shot(self, app, "lesson-4-done")
        app.buttons["Done"].tap()
        // Progress shows on the list.
        XCTAssertTrue(app.staticTexts["1 of 2 lessons done"].waitForExistence(timeout: 5))
        shot(self, app, "lesson-5-list-after")
        // Clearing practice history also clears lesson progress.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Chapter settings"].tap()
        app.buttons["Clear practice history"].tap()
        app.alerts.buttons["Clear"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(tile.label.contains("0 of 2"), tile.label)
        tile.tap()
        XCTAssertTrue(app.staticTexts["0 of 2 lessons done"].waitForExistence(timeout: 5))
        shot(self, app, "lesson-6-cleared")
    }

    /// Scribble an answer low on the page (below the problem the page just scrolled to).
    private func write(_ app: XCUIApplication) {
        let page = app.descendants(matching: .any)["solutionPage"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
            .press(forDuration: 0.1, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.84)),
                   withVelocity: 300, thenHoldForDuration: 0.1)
    }
}

private func shot(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    test.add(a)
}
