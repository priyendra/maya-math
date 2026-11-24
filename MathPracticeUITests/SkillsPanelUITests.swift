import XCTest

/// Screenshots of the skills views on whatever data is in the simulator (for design review only).
final class SkillsPanelUITests: XCTestCase {
    func testSkillsPanelShots() throws {
        // Design review only: runs when SHOTS_DIR is set (TEST_RUNNER_SHOTS_DIR=... xcodebuild test ...), on real data copied in.
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { throw XCTSkip("Set SHOTS_DIR to take screenshots") }
        let app = XCUIApplication()
        app.launchArguments = ["-openFirstChapter"] + (ProcessInfo.processInfo.environment["EXTRA_ARGS"].map { $0.split(separator: " ").map(String.init) } ?? [])
        for key in ["FEEDBACK_DUMP", "FEEDBACK_SEED"] {
            if let v = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = v }
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["Progress summary"].waitForExistence(timeout: 15))
        save(app, dir, "1-chapter-top")
        app.swipeUp(); sleep(1); save(app, dir, "2-chapter-bottom")
        app.swipeUp(); sleep(1); save(app, dir, "2c-feedback-more")
        app.swipeDown(); app.swipeDown(); sleep(1)
        let answers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My answers'")).firstMatch
        if answers.waitForExistence(timeout: 3) {
            answers.tap(); sleep(3); save(app, dir, "7-answers")
            // Scroll hard both ways: the page must settle (no jumping loop).
            for _ in 0..<8 { app.swipeUp(velocity: .fast) }
            sleep(2); save(app, dir, "7b-answers-down")
            for _ in 0..<8 { app.swipeDown(velocity: .fast) }
            sleep(2); save(app, dir, "7c-answers-up")
            sleep(3); save(app, dir, "7d-answers-settled")
            app.buttons["result-All mistakes"].firstMatch.tap(); sleep(2); save(app, dir, "7e-all-mistakes")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        let seeAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My progress'")).firstMatch
        if seeAll.waitForExistence(timeout: 3) {
            seeAll.tap(); sleep(2); save(app, dir, "3-progress")
            app.swipeUp(); sleep(1); save(app, dir, "3b-progress-more")
            let words = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'word problems'")).firstMatch
            if words.waitForExistence(timeout: 3) {
                words.tap(); sleep(3); save(app, dir, "5-skill")
                app.swipeUp(); sleep(1); save(app, dir, "5b-skill-more")
                app.navigationBars.buttons.firstMatch.tap(); sleep(1)
            }
            let incomplete = app.descendants(matching: .any)["mistake-incomplete"]
            if incomplete.waitForExistence(timeout: 3) || { app.swipeUp(); return incomplete.waitForExistence(timeout: 3) }() {
                incomplete.tap(); sleep(3); save(app, dir, "6-mistake")
                app.swipeUp(); sleep(1); save(app, dir, "6b-mistake-more")
            }
            let help = app.buttons["How this works"]
            if help.waitForExistence(timeout: 3) { help.tap(); sleep(2); save(app, dir, "4-help") }
        }
    }

    private func save(_ app: XCUIApplication, _ dir: String, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
}
