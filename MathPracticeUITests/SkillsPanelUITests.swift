import XCTest

/// Screenshots of the skills views on whatever data is in the simulator (for design review only).
final class SkillsPanelUITests: XCTestCase {
    func testSkillsPanelShots() throws {
        // Design review only: runs when SHOTS_DIR is set (TEST_RUNNER_SHOTS_DIR=... xcodebuild test ...), on real data copied in.
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { throw XCTSkip("Set SHOTS_DIR to take screenshots") }
        let app = XCUIApplication()
        app.launchArguments = ["-openFirstChapter"] + (ProcessInfo.processInfo.environment["EXTRA_ARGS"].map { $0.split(separator: " ").map(String.init) } ?? [])
        for key in ["FEEDBACK_DUMP", "FEEDBACK_SEED"] {
            if let v = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = v }
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["Progress summary"].waitForExistence(timeout: 15))
        save(app, dir, "1-chapter-top")
        app.swipeUp(); sleep(1); save(app, dir, "2-chapter-bottom")
        app.swipeUp(); sleep(1); save(app, dir, "2c-feedback-more")
        app.swipeDown(); app.swipeDown(); sleep(1)
        let answers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My answers'")).firstMatch
        if answers.waitForExistence(timeout: 3) {
            answers.tap(); sleep(3); save(app, dir, "7-answers")
            // Scroll hard both ways: the page must settle (no jumping loop).
            for _ in 0..<8 { app.swipeUp(velocity: .fast) }
            sleep(2); save(app, dir, "7b-answers-down")
            for _ in 0..<8 { app.swipeDown(velocity: .fast) }
            sleep(2); save(app, dir, "7c-answers-up")
            sleep(3); save(app, dir, "7d-answers-settled")
            app.buttons["resultFilter"].firstMatch.tap(); sleep(1); save(app, dir, "7e-result-menu")
            app.buttons["Wrong answers"].firstMatch.tap(); sleep(2); save(app, dir, "7f-wrong")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        let seeAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My progress'")).firstMatch
        if seeAll.waitForExistence(timeout: 3) {
            seeAll.tap(); sleep(2); save(app, dir, "3-progress")
            app.swipeUp(); sleep(1); save(app, dir, "3b-progress-more")
            let words = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'word problems'")).firstMatch
            if words.waitForExistence(timeout: 3) {
                words.tap(); sleep(3); save(app, dir, "5-skill")
                app.swipeUp(); sleep(1); save(app, dir, "5b-skill-more")
                app.navigationBars.buttons.firstMatch.tap(); sleep(1)
            }
            let incomplete = app.descendants(matching: .any)["mistake-incomplete"]
            if incomplete.waitForExistence(timeout: 3) || { app.swipeUp(); return incomplete.waitForExistence(timeout: 3) }() {
                incomplete.tap(); sleep(3); save(app, dir, "6-mistake")
                app.swipeUp(); sleep(1); save(app, dir, "6b-mistake-more")
            }
            let help = app.buttons["How this works"]
            if help.waitForExistence(timeout: 3) { help.tap(); sleep(2); save(app, dir, "4-help") }
        }
    }

    /// My answers filtered to AI-generated questions, and one of their answer pages (design review only, real data).
    func testAIGeneratedShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { throw XCTSkip("Set SHOTS_DIR") }
        let app = XCUIApplication()
        app.launchArguments = ["-openFirstChapter"]
        app.launch()
        let answers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'My answers'")).firstMatch
        XCTAssertTrue(answers.waitForExistence(timeout: 15))
        answers.tap(); sleep(3); save(app, dir, "g1-answers")
        // Scroll slowly in small steps: a To check card must not vanish when its twin in All answers comes into view.
        for i in 1...4 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
            sleep(1); save(app, dir, "g0-scroll-\(i)")
        }
        for _ in 0..<3 { app.swipeDown() }; sleep(1)
        app.buttons["sourceFilter"].firstMatch.tap(); sleep(1); save(app, dir, "g2-source-menu")
        app.buttons["AI Generated"].firstMatch.tap(); sleep(2); save(app, dir, "g3-generated")
        app.swipeUp(); sleep(1); save(app, dir, "g3b-generated-more")
        app.swipeDown(); sleep(1)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Correct' OR label BEGINSWITH 'Not quite'")).firstMatch
        if row.waitForExistence(timeout: 3) { row.tap(); sleep(2); save(app, dir, "g4-answer-page") }
    }

    /// The study plan editor's foldable section tree (design review only, real data with a plan named in PLAN_NAME).
    func testStudyPlanEditorShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"],
              let plan = ProcessInfo.processInfo.environment["PLAN_NAME"] else { throw XCTSkip("Set SHOTS_DIR and PLAN_NAME") }
        let app = XCUIApplication()
        app.launch()
        // Folders to open first, "A/B" (from the environment: real folder names stay out of the repo).
        for folder in (ProcessInfo.processInfo.environment["FOLDERS"] ?? "").split(separator: "/") {
            let f = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", String(folder))).firstMatch
            if f.waitForExistence(timeout: 10) { f.tap(); sleep(2) }
        }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", plan)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap(); sleep(2)
        save(app, dir, "e0-plan-page")
        app.buttons["planContents"].firstMatch.tap(); sleep(2)
        save(app, dir, "e1-folded")
        func open(_ prefix: String) {
            let r = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scopeRow-" + prefix)).firstMatch
            if r.waitForExistence(timeout: 3) { r.tap(); sleep(1) }
        }
        open("Factoring Polynomials"); save(app, dir, "e2-chapter-open")
        open("Factoring Patterns"); save(app, dir, "e3-unit-open")
        open("5-8"); save(app, dir, "e4-lesson-open")
        // Untick one lesson of the ticked chapter: its siblings stay in.
        let check = app.buttons.matching(NSPredicate(format: "label == 'Included'")).element(boundBy: 2)
        if check.exists { check.tap(); sleep(1); save(app, dir, "e5-one-unticked") }
        open("Factoring Patterns"); open("Factoring Polynomials"); save(app, dir, "e6-folded-summary")
    }

    private func save(_ app: XCUIApplication, _ dir: String, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// A study plan page and its My progress (design review only, on real data with a plan named in PLAN_NAME).
    func testStudyPlanShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"],
              let plan = ProcessInfo.processInfo.environment["PLAN_NAME"] else { throw XCTSkip("Set SHOTS_DIR and PLAN_NAME") }
        let app = XCUIApplication()
        app.launch()
        sleep(2); save(app, dir, "p0-home")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", plan)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap(); sleep(3); save(app, dir, "p1-plan-top")
        app.swipeUp(); sleep(1); save(app, dir, "p2-plan-bottom")
        app.swipeDown(); app.swipeDown(); sleep(1)
        app.buttons["scopeProgress"].firstMatch.tap(); sleep(2); save(app, dir, "p3-plan-progress")
    }


    /// The exam start screen with its two sliders (design review only).
    func testExamShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { throw XCTSkip("Set SHOTS_DIR") }
        let app = XCUIApplication()
        app.launchArguments = ["-openFirstChapter"]
        if let v = ProcessInfo.processInfo.environment["FEEDBACK_DUMP"] { app.launchEnvironment["FEEDBACK_DUMP"] = v }
        app.launch()
        let exam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam mode'")).firstMatch
        XCTAssertTrue(exam.waitForExistence(timeout: 15))
        sleep(2)
        exam.tap(); sleep(2); save(app, dir, "e1-exam-intro")
        app.buttons["Hardest"].firstMatch.tap(); app.buttons["Fast"].firstMatch.tap(); sleep(1); save(app, dir, "e2-hardest-fast")
        app.buttons["Fastest"].firstMatch.tap(); app.buttons["20 min"].firstMatch.tap(); sleep(1); save(app, dir, "e3-hardest-fastest-20")

    }


    /// A running exam: normal clock, then the red clock of the last 5 minutes (design review only).
    func testExamRunningShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { throw XCTSkip("Set SHOTS_DIR") }
        for (args, name) in [([String](), "r1-exam-running"), (["-examSeconds", "272"], "r2-exam-last-minutes")] {
            let app = XCUIApplication()
            app.launchArguments = ["-openFirstChapter"] + args
            app.launch()
            let exam = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Exam mode'")).firstMatch
            XCTAssertTrue(exam.waitForExistence(timeout: 15))
            sleep(1); exam.tap(); sleep(1)
            app.buttons["Normal"].firstMatch.tap()
            app.buttons["Start exam"].firstMatch.tap(); sleep(3)
            if name == "r2-exam-last-minutes" { app.buttons["Next"].firstMatch.tap(); app.buttons["Next"].firstMatch.tap(); sleep(1) }
            save(app, dir, name)
            app.terminate()
        }
    }

}
