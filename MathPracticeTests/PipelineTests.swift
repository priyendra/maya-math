import XCTest
@testable import MathPractice

@MainActor
final class PipelineTests: XCTestCase {
    func testAnswerKeyRefMatching() {
        XCTAssertEqual(ChapterProcessor.refKey("3.2 #14b"), "14b")
        XCTAssertEqual(ChapterProcessor.refKey("14b"), "14b")
        XCTAssertEqual(ChapterProcessor.refKey("#7"), "7")
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
