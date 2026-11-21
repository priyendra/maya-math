import XCTest

final class CanvasLabUITests: XCTestCase {
    func run(_ variant: Int) -> String {
        let app = XCUIApplication()
        app.launchArguments = ["-canvasLab", "\(variant)"]
        app.launch()
        let canvas = app.descendants(matching: .any)["writingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)),
                    withVelocity: 200, thenHoldForDuration: 0.2)
        sleep(1)
        let state = app.staticTexts["inkState"].label
        app.terminate(); return state
    }
    func testVariants() {
        for v in [0, 1, 2] { XCTAssertEqual(run(v), "INK", "variant \(v)") }
    }
}
