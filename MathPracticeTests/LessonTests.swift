import XCTest
@testable import MathPractice

final class LessonTests: XCTestCase {
    private typealias P = LessonPlanDTO.Part
    private typealias L = LessonPlanDTO.Lesson

    private func covered(_ r: LessonPlanner.Result) -> Set<Int> {
        Set(r.lessons.flatMap { $0.parts.flatMap { $0.sectionIDs + $0.practiceSectionIDs } } + r.skipped.map(\.section_id))
    }

    /// A section that teaches but was left out of the plan joins the nearest earlier part.
    func testLeftOutTeachingSectionJoinsTheNearestEarlierPart() {
        let dto = LessonPlanDTO(lessons: [
            L(title: "Distance and Speed", summary: "", optional: false, parts: [
                P(title: "Reading speed", section_ids: [45], practice_section_ids: [46]),
                P(title: "Finding speed", section_ids: [47], practice_section_ids: [48]),
                P(title: "Finding distance", section_ids: [49], practice_section_ids: [50]),
                // "LEARN Find the time given the distance and speed" (51) is missing.
            ]),
        ], skipped: [])
        let r = LessonPlanner.validate(dto, sections: LessonFixtures.ratesAndSpeed)
        XCTAssertTrue(r.attached.contains(51))
        let distance = r.lessons.first { $0.title == "Distance and Speed" }!
        XCTAssertEqual(distance.parts[2].sectionIDs, [49, 51])
        // Whole units the plan forgot become lessons of their own, in book order.
        XCTAssertEqual(Array(r.lessons.map(\.title).prefix(3)), ["How much is the postage?", "Recall Prior Knowledge", "1 Rates and Unit Rates"])
        XCTAssertTrue(r.lessons.contains { $0.title == "4 Average Speed" })
    }

    /// Whatever Claude returns, every section with explanation or examples ends up in a lesson or deliberately skipped.
    func testEveryTeachingSectionIsCoveredOrSkipped() {
        for sections in [LessonFixtures.ratesAndSpeed, LessonFixtures.factoring] {
            let first = sections.first { $0.teaches }!.id
            let dto = LessonPlanDTO(lessons: [L(title: "Only one", summary: "", optional: false,
                                                parts: [P(title: "p", section_ids: [first], practice_section_ids: [])])],
                                    skipped: [])
            let r = LessonPlanner.validate(dto, sections: sections)
            let all = covered(r)
            for s in sections where s.teaches { XCTAssertTrue(all.contains(s.id), "\(s.title) left out") }
        }
    }

    func testRepeatedAndUnknownSectionsAreDropped() {
        let dto = LessonPlanDTO(lessons: [
            L(title: "A", summary: "", optional: false, parts: [
                P(title: "one", section_ids: [45, 999], practice_section_ids: [46]),
                P(title: "dup", section_ids: [45], practice_section_ids: [46]),   // all repeats: dropped
            ]),
            L(title: "Empty", summary: "", optional: false, parts: []),
        ], skipped: [.init(section_id: 45, reason: "already used"), .init(section_id: 82, reason: "rubric")])
        let r = LessonPlanner.validate(dto, sections: LessonFixtures.ratesAndSpeed)
        let a = r.lessons.first { $0.title == "A" }!
        XCTAssertEqual(a.parts.count, 1)
        XCTAssertEqual(a.parts[0].sectionIDs.first, 45)
        XCTAssertFalse(a.parts[0].sectionIDs.contains(999))
        XCTAssertFalse(r.lessons.contains { $0.title == "Empty" })
        XCTAssertEqual(r.skipped.map(\.section_id), [82])
    }

    func testOutlineDescriptionForClaude() {
        let text = LessonPlanner.describe("Rates and Speed", LessonFixtures.ratesAndSpeed)
        XCTAssertTrue(text.contains("[45] LEARN Read, interpret, and write speed — 1 worked example"), text)
        XCTAssertTrue(text.contains("[82] Rubric — 1 explanation paragraph"), text)
    }

    func testContinueTagAndGoOnPhrases() {
        XCTAssertEqual(TutorScriptParser.beat("CONTINUE"), .resume)
        XCTAssertEqual(TutorScriptParser.beat("continue."), .resume)
        XCTAssertEqual(TutorScriptParser.beat("SAY: Let's continue with the next step."), .say("Let's continue with the next step."))
        XCTAssertTrue(LessonSession.isGoOn("Go on."))
        XCTAssertTrue(LessonSession.isGoOn("no"))
        XCTAssertFalse(LessonSession.isGoOn("no wait why is it seven"))
    }

    @MainActor
    func testScriptIdsArePerPartAndLabelsBecomeIDs() {
        let fig = UUID(), q1 = UUID(), q2 = UUID()
        let input = LessonWriter.Input(figures: ["f1": fig], questions: ["q1": q1, "q2": q2])
        let dto = LessonScriptDTO(items: [
            .init(id: "e1", kind: "text", markdown: "Speed is distance per unit of time.", figure: ""),
            .init(id: "e2", kind: "figure", markdown: "Bar model", figure: "f1"),
            .init(id: "e3", kind: "figure", markdown: "A picture we don't have", figure: "f9"),
        ], narration: "POINT: e2\nSAY: Look at the bar model.\nPOINT: b1\nCONTINUE", your_turn: ["q2", "q7", "Q1"])
        let s = LessonWriter.convert(dto, part: 2, input: input)
        XCTAssertEqual(s.items.map(\.id), ["p3e1", "p3e2"])
        XCTAssertEqual(s.items[1].blockID, fig)
        XCTAssertEqual(s.narration.components(separatedBy: "\n")[0], "POINT: p3e2")
        XCTAssertEqual(s.narration.components(separatedBy: "\n")[2], "POINT: b1")
        XCTAssertEqual(s.questionIDs, [q2, q1])
    }
}
