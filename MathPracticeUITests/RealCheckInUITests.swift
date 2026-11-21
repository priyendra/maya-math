import XCTest

/// Runs against whatever data is already in the simulator (e.g. a copy of the iPad's database).
final class RealCheckInUITests: XCTestCase {
    func testExpandSolutionsAndScroll() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-checkInLab"]
        app.launch()
        let show = app.buttons["Show solution"].firstMatch
        guard show.waitForExistence(timeout: 15) else { throw XCTSkip("no data") }
        show.tap()
        sleep(2)
        add({ let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; return a }())
        let keepGoing = app.buttons["Keep going"]
        for _ in 0..<25 where !keepGoing.isHittable { app.swipeUp() }
        add({ let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; return a }())
        XCTAssertTrue(keepGoing.isHittable)
    }
}
