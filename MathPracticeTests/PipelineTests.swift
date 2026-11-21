import XCTest
@testable import MathPractice

@MainActor
final class PipelineTests: XCTestCase {
    func testGradeSchemaSolvesFirstAndRequiresAllFields() throws {
        let schema = GradeDTO.schema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let props = try XCTUnwrap(schema["properties"] as? OrderedObject)
        XCTAssertEqual(schema["required"] as? [String], props.pairs.map(\.0))
        // The grader must commit to its own answer before reading/judging hers.
        XCTAssertEqual(props.pairs.first?.0, "own_solution")
        let json = JSONWriter.string(schema)
        let own = try XCTUnwrap(json.range(of: "own_final_answer")), verdict = try XCTUnwrap(json.range(of: "\"verdict\""))
        XCTAssertLessThan(own.lowerBound, verdict.lowerBound)
    }

    func testJSONWriterEscapesAndRoundTrips() throws {
        let value: [String: Any] = ["a": "line\n\"quote\" \\ $x^2$", "b": [1, 2.5, true], "c": OrderedObject(pairs: [("z", 1), ("y", NSNull())])]
        let data = JSONWriter.data(value)
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(back["a"] as? String, "line\n\"quote\" \\ $x^2$")
        XCTAssertTrue(JSONWriter.string(value).contains("{\"z\":1,\"y\":null}"))
    }

    func testPageNumbersAreInferredAndGapsReported() {
        let filled = ChapterProcessor.inferPageNumbers([185, nil, 187, 188, nil, nil, 191])
        XCTAssertEqual(filled.compactMap { $0 }, [185, 186, 187, 188, 189, 190, 191])
        XCTAssertNil(ChapterProcessor.pageProblems(filled))
        XCTAssertEqual(ChapterProcessor.pageProblems([10, 11, 13, 13, 17]),
                       "Page 12 seems to be missing; page 13 was scanned twice; pages 14–16 seem to be missing.")
    }

    func testSectionContainment() {
        let nodes = [SectionNode(id: 0, title: "5-1", level: 1, parent: -1),
                     SectionNode(id: 1, title: "Exercises", level: 2, parent: 0),
                     SectionNode(id: 2, title: "5-2", level: 1, parent: -1)]
        XCTAssertTrue(StudySet.isWithin(1, 0, nodes))
        XCTAssertTrue(StudySet.isWithin(0, 0, nodes))
        XCTAssertFalse(StudySet.isWithin(2, 0, nodes))
        XCTAssertFalse(StudySet.isWithin(-1, 0, nodes))
    }

    func testReadDTODecodes() throws {
        let json = #"{"pages":[{"image_number":1,"printed_page_number":214,"is_answer_key":false,"blocks":[{"kind":"exercise","section_path":["Ch 5","5-7"],"markdown":"$x^2+5x+4$","question_markdown":"Factor $x^2+5x+4$.","printed_number":"1","has_figure":false,"figure_box":{"x":0,"y":0,"width":0,"height":0},"pencil_ok":true,"pencil_reason":"","is_challenge":false}]}]}"#
        let dto = try JSONDecoder().decode(ReadDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.pages.first?.printed_page_number, 214)
        XCTAssertEqual(dto.pages.first?.blocks.first?.question_markdown, "Factor $x^2+5x+4$.")
    }

    func testAnswerNormalization() {
        XCTAssertEqual(ClaudeServices.normalize("$x = 3$"), ClaudeServices.normalize("X=3"))
    }
}
