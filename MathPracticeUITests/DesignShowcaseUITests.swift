import XCTest

/// Screenshots of the main screens in each design option (for comparing them side by side).
final class DesignShowcaseUITests: XCTestCase {
    func testShowcaseDesigns() {
        for d in 0..<4 {
            let app = XCUIApplication()
            app.launchArguments = ["-seedSample", "-seedLessons", "-fakeTutor", "-design", "\(d)"]
            app.launch()
            let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ch. 2'")).firstMatch
            XCTAssertTrue(chapter.waitForExistence(timeout: 15))
            sleep(1)
            snap(app, "design\(d)-1-library")
            chapter.tap()
            let tile = app.buttons["lessonsTile"]
            XCTAssertTrue(tile.waitForExistence(timeout: 10))
            sleep(1)
            snap(app, "design\(d)-2-chapter")
            tile.tap()
            let row = app.buttons.matching(identifier: "lessonRow").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            sleep(1)
            snap(app, "design\(d)-3-lessons")
            app.buttons["Start lesson"].tap()
            XCTAssertTrue(app.buttons["debugSay"].waitForExistence(timeout: 20))
            sleep(1)
            snap(app, "design\(d)-4-lesson")
            app.terminate()
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
