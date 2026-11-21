import XCTest

final class CheckInUITests: XCTestCase {
    /// A long worked solution must be scrollable all the way to the button below it.
    func testLongSolutionScrolls() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedGraded", "-checkInLab"]
        app.launch()
        let show = app.buttons["Show solution"]
        XCTAssertTrue(show.waitForExistence(timeout: 15))
        show.tap()
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        let keepGoing = app.buttons["Keep going"]
        for _ in 0..<8 where !keepGoing.isHittable { app.swipeUp() }
        let shot2 = XCTAttachment(screenshot: app.screenshot()); shot2.lifetime = .keepAlways; add(shot2)
        XCTAssertTrue(keepGoing.isHittable, "could not scroll to the end of the solution")
    }
}

final class AnswerDetailUITests: XCTestCase {
    /// "Disagree with the grade?" → answer detail → expand the solution → it must be readable to the end.
    func testLongSolutionInAnswerDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-seedGraded", "-checkInLab"]
        app.launch()
        let disagree = app.buttons["Disagree with the grade?"]
        XCTAssertTrue(disagree.waitForExistence(timeout: 15))
        disagree.tap()
        let solution = app.buttons["Solution"]
        XCTAssertTrue(solution.waitForExistence(timeout: 5))
        solution.tap()
        sleep(2)
        add({ let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; a.name = "expanded"; return a }())
        for _ in 0..<4 { app.swipeUp() }
        sleep(1)
        add({ let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; a.name = "scrolled"; return a }())
    }
}
