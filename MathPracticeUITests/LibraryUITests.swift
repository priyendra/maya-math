import XCTest

final class LibraryUITests: XCTestCase {
    /// A chapter two folders deep must open (it used to bounce back to the folder).
    func testChapterInNestedFolderOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedInFolder"]
        app.launch()
        XCTAssertTrue(app.buttons["Student"].waitForExistence(timeout: 15))
        app.buttons["Student"].tap()
        XCTAssertTrue(app.buttons["School algebra"].waitForExistence(timeout: 5))
        app.buttons["School algebra"].tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Solving Linear Equations'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        let practice = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Practice'")).firstMatch
        XCTAssertTrue(practice.waitForExistence(timeout: 5), "chapter did not open")
        // Back goes to the folder, and the chapter opens again.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        XCTAssertTrue(practice.waitForExistence(timeout: 5), "chapter did not open the second time")
    }
}
