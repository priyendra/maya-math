import XCTest

final class CanvasUITests: XCTestCase {
    /// Opens a practice session on the sample chapter and draws on the canvas; Next must become enabled.
    func testDrawingOnCanvasRegisters() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-freshStore", "-seedSample", "-openFirstChapter"]
        app.launch()
        let practice = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Practice'")).firstMatch
        if !practice.waitForExistence(timeout: 15) { print(app.debugDescription); XCTFail("no Practice button"); return }
        practice.tap()
        let canvas = app.descendants(matching: .any)["writingCanvas"]
        if !canvas.waitForExistence(timeout: 10) { print(app.debugDescription); XCTFail("canvas not found"); return }
        let next = app.buttons["Next"]
        XCTAssertFalse(next.isEnabled)
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 0.2)
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        if !next.isEnabled { print(app.debugDescription) }
        XCTAssertTrue(next.isEnabled, "stroke did not register")

        // Next question: a fresh, empty canvas that still takes ink.
        next.tap()
        sleep(2)
        let fresh = XCTAttachment(screenshot: app.screenshot()); fresh.name = "after-next"; fresh.lifetime = .keepAlways; add(fresh)
        let canvas2 = app.descendants(matching: .any)["writingCanvas"]
        XCTAssertTrue(canvas2.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next"].isEnabled, "new question should start with no ink")
        canvas2.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas2.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)),
                   withVelocity: 200, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertTrue(app.buttons["Next"].isEnabled, "second canvas did not take ink")
    }
}
