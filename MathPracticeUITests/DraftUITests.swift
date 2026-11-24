import XCTest

/// Work in progress survives the app closing.
final class DraftUITests: XCTestCase {
    private func draw(_ app: XCUIApplication) {
        let canvas = app.descendants(matching: .any)["writingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)),
                   withVelocity: 200, thenHoldForDuration: 0.2)
    }

    private func openFirstChapter(_ app: XCUIApplication, fresh: Bool, extra: [String] = []) {
        app.launchArguments = (fresh ? ["-freshStore", "-seedSample"] : []) + ["-openFirstChapter"] + extra
        app.launch()
    }

    func testPracticeInkComesBackAfterTheAppCloses() {
        let app = XCUIApplication()
        openFirstChapter(app, fresh: true)
        let practice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Practice'")).firstMatch
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        practice.tap()
        draw(app)
        let nextButton = app.buttons["Next"].firstMatch
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        XCTAssertTrue(nextButton.isEnabled)
        sleep(6)                       // a draft is saved every few seconds
        app.terminate()

        openFirstChapter(app, fresh: false)
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        practice.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10))
        XCTAssertTrue(nextButton.isEnabled, "her ink should be back, so Next is enabled")
    }

    func testExamAnswersAndClockSurviveTheAppClosing() {
        let app = XCUIApplication()
        openFirstChapter(app, fresh: true)
        let exam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam mode'")).firstMatch
        XCTAssertTrue(exam.waitForExistence(timeout: 15))
        exam.tap()
        app.buttons["Start exam"].firstMatch.tap()
        draw(app)
        app.buttons["Next"].firstMatch.tap()  // moving on saves the draft
        app.terminate()

        openFirstChapter(app, fresh: false)
        XCTAssertTrue(exam.waitForExistence(timeout: 15))
        exam.tap()
        // Straight back into the running exam (no start screen), with the first answer kept.
        XCTAssertTrue(app.descendants(matching: .any)["examClock"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start exam"].exists)
        app.buttons["Hand in"].firstMatch.tap()
        let blank = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'still blank'")).firstMatch
        XCTAssertTrue(blank.waitForExistence(timeout: 5))
        XCTAssertFalse(blank.label.hasPrefix("All"), blank.label)
        let n = app.buttons.matching(NSPredicate(format: "label MATCHES '^[0-9]+$'")).count
        XCTAssertTrue(blank.label.contains("\(n - 1) questions are still blank"), "\(blank.label) (of \(n))")
    }

    func testPracticeLinksToTheQuestionInTheChapter() {
        let app = XCUIApplication()
        openFirstChapter(app, fresh: true)
        let practice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Practice'")).firstMatch
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        practice.tap()
        let link = app.buttons["practiceSeeInChapter"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        // Looking at the book counts as a hint, and she is told so first.
        let open = app.buttons["Open the book"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'counts as a hint'")).firstMatch.exists)
        open.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "practice-chapter"; a.lifetime = .keepAlways; add(a)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["writingCanvas"].waitForExistence(timeout: 5))
        // Second look on the same question: no question asked again.
        link.tap()
        XCTAssertFalse(app.buttons["Open the book"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.firstMatch.tap()
    }
}
