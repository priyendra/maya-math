import XCTest

/// Screenshots of the skills views on whatever data is in the simulator (for design review only).
final class SkillsPanelUITests: XCTestCase {
    func testSkillsPanelShots() throws {
        // Design review only: runs when SHOTS_DIR is set (TEST_RUNNER_SHOTS_DIR=... xcodebuild test ...), on real data copied in.
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { throw XCTSkip("Set SHOTS_DIR to take screenshots") }
        let app = XCUIApplication()
        app.launchArguments = ["-openFirstChapter"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Progress summary"].waitForExistence(timeout: 15))
        save(app, dir, "1-chapter-top")
        app.swipeUp(); sleep(1); save(app, dir, "2-chapter-bottom")
        let seeAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My progress'")).firstMatch
        if seeAll.waitForExistence(timeout: 3) {
            seeAll.tap(); sleep(2); save(app, dir, "3-progress")
            app.swipeUp(); sleep(1); save(app, dir, "3b-progress-more")
            let help = app.buttons["How this works"]
            if help.waitForExistence(timeout: 3) { help.tap(); sleep(2); save(app, dir, "4-help") }
        }
    }

    private func save(_ app: XCUIApplication, _ dir: String, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
}
