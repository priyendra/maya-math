import XCTest
import SwiftData
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

    /// A section that teaches several ideas through several worked examples can be split across parts by example.
    func testLongSectionSplitByExamples() {
        let dto = LessonPlanDTO(lessons: [
            L(title: "5-1 Factoring Integers", summary: "", optional: false, parts: [
                P(title: "Factors and primes", section_ids: [1], practice_section_ids: [2, 3], examples: [1, 2]),
                P(title: "Greatest common factor", section_ids: [1], practice_section_ids: [2, 3], examples: [3]),
            ]),
        ], skipped: [])
        let r = LessonPlanner.validate(dto, sections: LessonFixtures.factoring)
        let l = r.lessons.first { $0.title == "5-1 Factoring Integers" }!
        XCTAssertEqual(l.parts.count, 2)
        XCTAssertEqual(l.parts[0].sectionIDs, [1])
        XCTAssertEqual(l.parts[1].sectionIDs.first, 1, "later teaching sections the plan left out join the last part")
        XCTAssertEqual(l.parts.map(\.fromExample), [1, 3])
        XCTAssertEqual(l.parts.map(\.toExample), [2, 3])
        XCTAssertEqual(l.parts[1].practiceSectionIDs, [2, 3], "exercise sections serve both parts")
        XCTAssertFalse(r.lessons.contains { $0.title != l.title && $0.parts.contains { $0.sectionIDs.contains(1) } })
    }

    /// Gaps and overlaps in example ranges are repaired; a lone slice means the whole section.
    func testExampleRangesAreRepaired() {
        let gap = LessonPlanDTO(lessons: [L(title: "A", summary: "", optional: false, parts: [
            P(title: "one", section_ids: [1], practice_section_ids: [], examples: [1]),
            P(title: "three", section_ids: [1], practice_section_ids: [], examples: [3]),
        ])], skipped: [])
        let a = LessonPlanner.validate(gap, sections: LessonFixtures.factoring).lessons.first { $0.title == "A" }!
        XCTAssertEqual(a.parts.map(\.fromExample), [1, 3])
        XCTAssertEqual(a.parts.map(\.toExample), [2, 3], "example 2 joins the part before it")

        let lone = LessonPlanDTO(lessons: [L(title: "B", summary: "", optional: false, parts: [
            P(title: "two", section_ids: [1], practice_section_ids: [], examples: [2]),
        ])], skipped: [])
        let b = LessonPlanner.validate(lone, sections: LessonFixtures.factoring).lessons.first { $0.title == "B" }!
        XCTAssertNil(b.parts[0].fromExample)

        // Example numbers on a section with a single example (or several sections) are ignored.
        let ignored = LessonPlanDTO(lessons: [L(title: "C", summary: "", optional: false, parts: [
            P(title: "speed", section_ids: [45], practice_section_ids: [46], examples: [1]),
        ])], skipped: [])
        let c = LessonPlanner.validate(ignored, sections: LessonFixtures.ratesAndSpeed).lessons.first { $0.title == "C" }!
        XCTAssertNil(c.parts[0].fromExample)
    }

    func testOutlineListsExamplesOfLongSections() {
        var s = LessonFixtures.factoring
        let i = s.firstIndex { $0.id == 1 }!
        s[i].exampleTitles = ["**Example 1** Give all the positive factors of 56.", "**Example 2** Find the prime factorization of 504.",
                              "**Example 3** Find the GCF of 882 and 945."]
        let text = LessonPlanner.describe("Factoring", s)
        XCTAssertTrue(text.contains("example 3: **Example 3** Find the GCF of 882 and 945."), text)
    }

    @MainActor
    func testSlicingASectionBetweenParts() throws {
        let container = try ModelContainer(for: Chapter.self, ContentBlock.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let kinds = ["heading", "text", "example", "text", "example", "text", "example", "text"]
        let blocks = kinds.enumerated().map { i, k in ContentBlock(order: i, kind: k, markdown: "\(k)\(i)", pageIndex: 0, sectionID: 1) }
        blocks.forEach { ctx.insert($0) }
        func names(_ f: Int, _ t: Int) -> [String] {
            LessonWriter.slice(blocks, part: LessonPart(title: "", sectionIDs: [1], practiceSectionIDs: [], fromExample: f, toExample: t)).map(\.markdown)
        }
        XCTAssertEqual(names(1, 2), ["heading0", "text1", "example2", "text3", "example4"])
        XCTAssertEqual(names(3, 3), ["text5", "example6", "text7"])
    }

    /// "Your turn" problems come from the part's practice sections (books keep exercises apart from the teaching),
    /// then from exercises inside what it teaches.
    @MainActor
    func testYourTurnUsesPracticeSectionExercises() throws {
        let container = try ModelContainer(for: Chapter.self, ContentBlock.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let specs: [(String, Int)] = [("text", 1), ("example", 1), ("exercise", 1), ("exercise", 2), ("exercise", 3), ("exercise", 2)]
        let all = specs.enumerated().map { i, sp in ContentBlock(order: i, kind: sp.0, markdown: "\(sp.0)\(i)", pageIndex: 0, sectionID: sp.1) }
        all.forEach { ctx.insert($0) }
        let part = LessonPart(title: "", sectionIDs: [1], practiceSectionIDs: [2])
        let taught = all.filter { $0.sectionID == 1 }
        XCTAssertEqual(LessonWriter.exerciseBlocks(all, part: part, taught: taught).map(\.markdown), ["exercise3", "exercise5", "exercise2"])
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

    func testMathInShortLabels() {
        XCTAssertEqual(MathPlain.render("Factoring $x^2 + bx + c$ with $c$ positive"), "Factoring 𝑥² + 𝑏𝑥 + 𝑐 with 𝑐 positive")
        XCTAssertEqual(MathPlain.render("Products $(a+b)(a-b)$"), "Products (𝑎+𝑏)(𝑎−𝑏)")
        XCTAssertEqual(MathPlain.render("$\\frac{3}{4}$ of \\$20"), "3/4 of $20")
        XCTAssertEqual(MathPlain.render("$\\left(x^{n+1}\\right) \\le \\sqrt{2x}$"), "(𝑥ⁿ⁺¹) ≤ √(2𝑥)")
        XCTAssertEqual(MathPlain.render("$5\\text{ km}$ per $\\frac{a+b}{2}$"), "5 km per (𝑎+𝑏)/2")
        XCTAssertEqual(MathPlain.render("no math here"), "no math here")
    }

    func testSpokenMath() {
        XCTAssertEqual(TutorScriptParser.spoken("So $\\frac{3}{4}$ of it."), "So 3 over 4 of it.")
        XCTAssertEqual(TutorScriptParser.spoken("$x \\neq 2$"), "x is not equal to 2")
        XCTAssertEqual(TutorScriptParser.spoken("$x^{2} + y^n$"), "x squared + y to the power of n")
        XCTAssertEqual(TutorScriptParser.spoken("$t \\le 5$"), "t is less than or equal to 5")
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
    func testScriptWithoutNarrationIsNotUsable() {
        XCTAssertFalse(LessonWriter.isUsable(LessonPartScript(items: [], narration: "", questionIDs: [])))
        XCTAssertFalse(LessonWriter.isUsable(LessonPartScript(items: [], narration: "POINT: k1\nSAY: Hi.", questionIDs: [])))
        XCTAssertTrue(LessonWriter.isUsable(LessonPartScript(items: [], narration: "SAY: One.\nPOINT: k1\nSAY: Two.\nSAY: Three.", questionIDs: [])))
    }

    /// Book labels (k2) point at the book's own blocks; unknown labels point nowhere; exercise labels become ids.
    @MainActor
    func testScriptPointsAtTheBook() {
        let b1 = UUID(), b2 = UUID(), q1 = UUID(), q2 = UUID()
        let input = LessonWriter.Input(blocks: [b1, b2], questions: ["q1": q1, "q2": q2])
        let dto = LessonScriptDTO(narration: "POINT: k2\nSAY: Look at the example.\nPOINT: k9\nWRITE: $x$\nCONTINUE",
                                  your_turn: ["q2", "q7", "Q1"])
        let s = LessonWriter.convert(dto, part: 2, input: input)
        let lines = s.narration.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "POINT: book:\(b2.uuidString)")
        XCTAssertEqual(lines[2], "POINT: none")
        XCTAssertEqual(s.bookBlocks, [b1, b2])
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertEqual(s.questionIDs, [q2, q1])
        XCTAssertEqual(LessonWriter.bookBlock("k1", [b1, b2]), b1)
        XCTAssertNil(LessonWriter.bookBlock("b1", [b1, b2]))
    }

    /// A blank: the board line (with ___), the answer, and the spoken why.
    func testBlankLine() {
        XCTAssertEqual(TutorScriptParser.beat("BLANK: $= x^2 -$ ___ || 9 || Three squared is nine."),
                       .blank("$= x^2 -$ ___", answer: "9", why: "Three squared is nine."))
        XCTAssertEqual(TutorScriptParser.beat("BLANK: $(x$ ___ $5)$ || + || The signs are opposite."),
                       .blank("$(x$ ___ $5)$", answer: "+", why: "The signs are opposite."))
        // No marked blank: it goes at the end. No answer: not a blank.
        XCTAssertEqual(TutorScriptParser.beat("BLANK: $3x =$ || 9"), .blank("$3x =$ ___", answer: "9", why: ""))
        XCTAssertNil(TutorScriptParser.beat("BLANK: $3x =$ ___"))
        // Old saved scripts (a copy of the book, no book blocks) are written again.
        let old = try! JSONDecoder().decode(LessonPartScript.self, from: Data(#"{"items":[],"narration":"SAY: Hi.","questionIDs":[]}"#.utf8))
        XCTAssertNil(old.bookBlocks)
    }
}
