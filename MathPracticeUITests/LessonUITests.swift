import XCTest

final class LessonUITests: XCTestCase {
    /// Chapter → Read & learn → Teach me (canned scripts): the book is on top, the teacher's board below. Part 1:
    /// a fill-in-the-blank (✓ with nothing written asks her to write; written → checked → carries on), a question at
    /// the questions pause, a wrong then right your-turn. Part 2: "?" on the blank shows the answer … lesson done.
    func testTakeALesson() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedLessons", "-openFirstChapter", "-fakeTutor", "-fingerInk", "-fakeWrongOnce"]
        app.launch()
        let tile = app.buttons["learnTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let teach = app.buttons["teachSection"]
        XCTAssertTrue(teach.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practiseSection"].exists)
        shot(self, app, "lesson-0-reader")
        teach.tap()

        // Part 1: the book is shown; a blank on the board.
        XCTAssertTrue(app.webViews["lessonBook"].waitForExistence(timeout: 15) || app.descendants(matching: .any)["lessonBook"].exists)
        let check = app.buttons["blankCheck"]
        XCTAssertTrue(check.waitForExistence(timeout: 20), "no fill-in-the-blank")
        sleep(1)
        // The teacher's cursor is on the blank.
        let cursor = app.descendants(matching: .any).matching(identifier: "tutorCursor").firstMatch
        XCTAssertTrue(cursor.exists, "no cursor at the blank")
        XCTAssertLessThan(abs(cursor.frame.midY - check.frame.midY), 80, "cursor isn't by the blank")
        shot(self, app, "lesson-1-blank")
        check.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Write your answer in the blank first'")).firstMatch.waitForExistence(timeout: 3))
        writeInBlank(app, beside: check)
        sleep(1)
        shot(self, app, "lesson-2-blank-written")
        check.tap()

        // Then "any questions?" (listening). Ask one; the reply ends with CONTINUE → your turn.
        let say = app.buttons["debugSay"]
        XCTAssertTrue(say.waitForExistence(timeout: 20), "never reached the questions pause")
        shot(self, app, "lesson-3-checked")
        say.tap()
        let lessonCheck = app.buttons["lessonCheck"]
        XCTAssertTrue(lessonCheck.waitForExistence(timeout: 15), "no your-turn problem after the question")
        sleep(2)
        write(app)
        lessonCheck.tap()
        // Wrong first time: the tutor goes over it → second problem.
        sleep(4)
        XCTAssertTrue(app.buttons["lessonCheck"].waitForExistence(timeout: 15), "no second try")
        write(app)
        app.buttons["lessonCheck"].tap()

        // Part 2: not sure on the blank → the answer is shown, carries on → Go on → your turn → right → done.
        let notSure = app.buttons["blankNotSure"]
        XCTAssertTrue(notSure.waitForExistence(timeout: 25), "part 2 has no blank")
        notSure.tap()
        let goOn = app.buttons["lessonGoOn"]
        XCTAssertTrue(goOn.waitForExistence(timeout: 20), "part 2 never got to the questions pause")
        shot(self, app, "lesson-4-shown")
        goOn.tap()
        XCTAssertTrue(app.buttons["lessonCheck"].waitForExistence(timeout: 15))
        sleep(2)
        write(app)
        app.buttons["lessonCheck"].tap()
        XCTAssertTrue(app.buttons["Practice this lesson"].waitForExistence(timeout: 20), "lesson never finished")
        // She asked to be taught this one section: no next lesson beyond it.
        XCTAssertFalse(app.buttons["Next lesson"].exists)
        app.buttons["Done"].tap()
        // Back in the chapter: the section shows as taught.
        XCTAssertTrue(app.staticTexts["Taught"].waitForExistence(timeout: 5))
        shot(self, app, "lesson-5-reader-after")
        // Clearing practice history also clears lesson progress.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Chapter settings"].tap()
        app.buttons["Clear practice history"].tap()
        app.alerts.buttons["Clear"].tap()
        // The tile updates just after the alert closes.
        let cleared = app.buttons.matching(NSPredicate(format: "identifier == 'learnTile' AND label CONTAINS '0 of 2 lessons taught'")).firstMatch
        XCTAssertTrue(cleared.waitForExistence(timeout: 5), tile.label)
    }

    /// Writes a short stroke in the blank, just left of its ✓ button.
    private func writeInBlank(_ app: XCUIApplication, beside check: XCUIElement) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let f = check.frame
        origin.withOffset(CGVector(dx: f.minX - 110, dy: f.midY - 10))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: f.minX - 70, dy: f.midY + 12)),
                   withVelocity: 200, thenHoldForDuration: 0.1)
    }

    private func write(_ app: XCUIApplication) {
        let page = app.descendants(matching: .any)["solutionPage"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
            .press(forDuration: 0.1, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.84)),
                   withVelocity: 300, thenHoldForDuration: 0.1)
    }
}

private func shot(_ test: XCTestCase, _ app: XCUIApplication, _ name: String) {
    if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    test.add(a)
}
