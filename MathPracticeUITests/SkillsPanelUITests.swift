import XCTest

/// Screenshots of the skills panel on whatever data is in the simulator (for design review only).
final class SkillsPanelUITests: XCTestCase {
    func testSkillsPanelShots() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        let app = XCUIApplication()
        app.launchArguments = ["-openFirstChapter"]
        app.launch()
        let help = app.buttons["How this works"]
        XCTAssertTrue(help.waitForExistence(timeout: 15))
        save(app, dir, "1-top")
        app.swipeUp(); sleep(1); save(app, dir, "2-mid")
        app.swipeUp(); app.swipeUp(); sleep(1); save(app, dir, "3-bottom")
        app.swipeDown(); app.swipeDown(); app.swipeDown(); sleep(1)
        help.tap(); sleep(2); save(app, dir, "4-help")
    }

    private func save(_ app: XCUIApplication, _ dir: String, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
}
