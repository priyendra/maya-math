import XCTest

final class SkillsGridUITests: XCTestCase {
    /// Skill names with math show as math characters, not raw LaTeX.
    func testSkillNamesRenderMath() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-openFirstChapter"]
        app.launch()
        let name = app.staticTexts["Literal equations like 𝐴 = 𝑙𝑤"]
        for _ in 0..<4 where !name.waitForExistence(timeout: 4) { app.swipeUp() }
        XCTAssertTrue(name.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$'")).firstMatch.exists)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "skills-grid"; a.lifetime = .keepAlways; add(a)
    }
}
