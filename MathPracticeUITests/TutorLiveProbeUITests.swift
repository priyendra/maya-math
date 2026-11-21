import XCTest

/// The real (non-fake) tutor path with no API key in the simulator: it must end on a clear message and a Talk
/// button, never sit on "Thinking…" (regression: a permission prompt used to strand it there).
final class TutorNeverStuckUITests: XCTestCase {
    func testWithoutKeyShowsMessageNotEndlessThinking() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedGraded", "-checkInLab"]
        addUIInterruptionMonitor(withDescription: "permissions") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        app.launch()
        let show = app.buttons["Show solution"]
        XCTAssertTrue(show.waitForExistence(timeout: 15))
        show.tap()
        XCTAssertTrue(app.buttons["talkToTutor"].waitForExistence(timeout: 5))
        app.buttons["talkToTutor"].tap()
        let talk = app.buttons["Talk"]
        for _ in 0..<8 where !talk.exists {
            sleep(2)
            app.navigationBars.firstMatch.tap() // lets the interruption monitor answer permission alerts
        }
        XCTAssertTrue(talk.exists, "tutor never left Getting ready / Thinking")
        XCTAssertTrue(app.staticTexts["The tutor needs a Claude API key. Add one in Settings."].exists)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "tutor-no-key"; a.lifetime = .keepAlways; add(a)
    }
}
