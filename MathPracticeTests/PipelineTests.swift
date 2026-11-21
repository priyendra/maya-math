import XCTest
@testable import MathPractice

@MainActor
final class PipelineTests: XCTestCase {
    func testAnswerKeyMatchingUsesSection() {
        let keys = [ExtractionDTO.Key(book_ref: "3.1 #14", answer: "x = 2"),
                    ExtractionDTO.Key(book_ref: "3.2 #14", answer: "x = 5"),
                    ExtractionDTO.Key(book_ref: "3.2 #15b", answer: "y = 1")]
        let m = AnswerKeyMatcher(keys: keys, questionRefs: ["3.1 #14", "3.2 #14", "3.2 #15b", "3.3 #9"])
        XCTAssertEqual(m.answer(for: "3.1 #14"), "x = 2")
        XCTAssertEqual(m.answer(for: "3.2 #14"), "x = 5")
        XCTAssertEqual(m.answer(for: "Section 3.2, #15(b)"), "y = 1")
        XCTAssertNil(m.answer(for: "3.3 #9"))
        // Label-only fallback only when unambiguous.
        let loose = AnswerKeyMatcher(keys: [ExtractionDTO.Key(book_ref: "#7", answer: "12")], questionRefs: ["4.1 #7"])
        XCTAssertEqual(loose.answer(for: "4.1 #7"), "12")
    }

    func testGradeSchemaRequiresAllFields() throws {
        let schema = GradeDTO.schema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set((schema["properties"] as? [String: Any])?.keys.map { $0 } ?? []))
        let json = #"{"transcribed_work":"2x=6","transcribed_final_answer":"x=3","verdict":"correct","agrees_with_reference":true,"mistake_type":"none","error_step":"","feedback":"Nice!","confidence":0.95}"#
        let dto = try JSONDecoder().decode(GradeDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.verdict, "correct")
    }

    func testAnswerNormalization() {
        XCTAssertEqual(ClaudeServices.normalize("$x = 3$"), ClaudeServices.normalize("X=3"))
    }
}

