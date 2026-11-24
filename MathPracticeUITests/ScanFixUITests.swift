import XCTest

final class ScanFixUITests: XCTestCase {
    /// A chapter whose scan needs fixing shows a clear list; removing the duplicate updates it.
    func testRescanListShowsWhatToFix() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedRescan"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Rescan test'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Some pages need another scan"].exists)
        let lib = XCTAttachment(screenshot: app.screenshot()); lib.name = "scan-0-library"; lib.lifetime = .keepAlways; add(lib)
        row.tap()
        XCTAssertTrue(app.staticTexts["Page 213"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["the bottom is cut off (exercises 31–40 are missing)"].exists)
        XCTAssertTrue(app.staticTexts["Pages 214–215 are missing"].exists)
        XCTAssertFalse(app.buttons["Re-read chapter"].exists, "old re-read banner must not show for a new chapter")
        XCTAssertTrue(app.staticTexts["Page 216 was scanned twice"].exists)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "scan-1-list"; a.lifetime = .keepAlways; add(a)
        // Retake names the book page and takes one photo.
        app.buttons["Scan again"].tap()
        XCTAssertTrue(app.staticTexts["Turn to page 213 in your book"].waitForExistence(timeout: 5))
        let r = XCTAttachment(screenshot: app.screenshot()); r.name = "scan-2-retake"; r.lifetime = .keepAlways; add(r)
        app.buttons["Cancel"].tap()
        app.buttons["Remove extra copy"].tap()
        XCTAssertFalse(app.staticTexts["Page 216 was scanned twice"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Check again"].isEnabled, "nothing new to check yet")
    }
}
