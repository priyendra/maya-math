import XCTest

/// Screenshots of the app's screens (for design review). Not a behaviour test: it only walks through.
final class ScreenTourUITests: XCTestCase {
    func testTour() throws {
        // Opt-in (about a minute): TEST_RUNNER_TOUR=1 xcodebuild test ...
        guard ProcessInfo.processInfo.environment["TOUR"] != nil else { throw XCTSkip("Set TOUR=1 to take the screen tour") }
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedGraded", "-seedLessons", "-fakeTutor"]
        app.launch()
        let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ch. 2'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 15))
        app.buttons["Settings"].tap(); sleep(1); snap(app, "tour-settings")
        app.buttons["Done"].firstMatch.tap(); sleep(1)
        chapter.tap(); sleep(1)
        for (label, name) in [("My answers", "tour-answers"), ("My progress", "tour-progress"), ("Read chapter", "tour-read")] {
            let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            guard tile.waitForExistence(timeout: 5) else { continue }
            tile.tap(); sleep(2); snap(app, name)
            if name == "tour-answers" {
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'phone plan' OR label CONTAINS 'Not quite' OR label CONTAINS 'Solve'")).firstMatch
                if row.waitForExistence(timeout: 3) { row.tap(); sleep(2); snap(app, "tour-attempt"); app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1) }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
        }
        let practice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Practice'")).firstMatch
        if practice.waitForExistence(timeout: 5) { practice.tap(); sleep(3); snap(app, "tour-practice") }
        app.terminate()

        let lab = XCUIApplication()
        lab.launchArguments = ["-freshStore", "-seedSample", "-seedGraded", "-checkInLab", "-fakeTutor"]
        lab.launch(); sleep(3); snap(lab, "tour-checkin")
        let show = lab.buttons["Show solution"]
        if show.waitForExistence(timeout: 10) { show.tap(); sleep(3); snap(lab, "tour-solution") }
        lab.terminate()

        let exam = XCUIApplication()
        exam.launchArguments = ["-freshStore", "-seedSample", "-openFirstChapter"]
        exam.launch()
        let e = exam.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam mode'")).firstMatch
        if e.waitForExistence(timeout: 10) { e.tap(); sleep(2); snap(exam, "tour-exam") }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
