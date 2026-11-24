import XCTest

final class LibraryUITests: XCTestCase {
    /// A chapter two folders deep must open (it used to bounce back to the folder).
    func testChapterInNestedFolderOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-seedInFolder"]
        app.launch()
        func button(_ name: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch }
        XCTAssertTrue(button("Student").waitForExistence(timeout: 15))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "library-folders"; a.lifetime = .keepAlways; add(a)
        button("Student").tap()
        XCTAssertTrue(button("School algebra").waitForExistence(timeout: 5))
        button("School algebra").tap()
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
