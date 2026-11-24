import XCTest

final class SkillsGridUITests: XCTestCase {
    /// Skill names with math show as math characters, not raw LaTeX.
    func testSkillNamesRenderMath() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-openFirstChapter"]
        app.launch()
        // Skill names are listed on My progress (the chapter page shows the mastery points chart).
        let progress = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My progress'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        progress.tap()
        // Each skill row is one button (it opens the skill's page).
        let name = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Literal equations like 𝐴 = 𝑙𝑤'")).firstMatch
        for _ in 0..<4 where !name.waitForExistence(timeout: 4) { app.swipeUp() }
        XCTAssertTrue(name.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$'")).firstMatch.exists)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "skills-grid"; a.lifetime = .keepAlways; add(a)
        name.tap()
        XCTAssertTrue(app.staticTexts["of 100 mastery points for this skill"].waitForExistence(timeout: 5))
    }
}
