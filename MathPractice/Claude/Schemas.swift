import Foundation

// JSON schemas for structured outputs + matching Decodable DTOs.
// Every object needs additionalProperties:false and a full `required` list.
// Numeric bounds aren't supported by the API, so ranges are validated in code.

enum Schema {
    static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": Array(properties.keys).sorted(), "additionalProperties": false]
    }
    static func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
    static let string: [String: Any] = ["type": "string"]
    static let integer: [String: Any] = ["type": "integer"]
    static let number: [String: Any] = ["type": "number"]
    static let boolean: [String: Any] = ["type": "boolean"]
    static func enumeration(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
}

// MARK: - Extraction (per batch of pages)

struct ExtractionDTO: Decodable {
    struct Box: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
    struct Section: Decodable { let heading: String; let summary: String }
    struct Example: Decodable { let section_heading: String; let text: String }
    struct Item: Decodable {
        let book_ref: String
        let section_heading: String
        let page_number: Int
        let text: String
        let has_figure: Bool
        let figure_box: Box
    }
    struct Key: Decodable { let book_ref: String; let answer: String }

    let sections: [Section]
    let worked_examples: [Example]
    let questions: [Item]
    let answer_key: [Key]

    static var schema: [String: Any] {
        let box = Schema.object(["x": Schema.number, "y": Schema.number, "width": Schema.number, "height": Schema.number])
        return Schema.object([
            "sections": Schema.array(Schema.object(["heading": Schema.string, "summary": Schema.string])),
            "worked_examples": Schema.array(Schema.object(["section_heading": Schema.string, "text": Schema.string])),
            "questions": Schema.array(Schema.object([
                "book_ref": Schema.string,
                "section_heading": Schema.string,
                "page_number": Schema.integer,
                "text": Schema.string,
                "has_figure": Schema.boolean,
                "figure_box": box,
            ])),
            "answer_key": Schema.array(Schema.object(["book_ref": Schema.string, "answer": Schema.string])),
        ])
    }
}

// MARK: - Organize (whole chapter)

struct OrganizeDTO: Decodable {
    struct ConceptItem: Decodable { let name: String; let summary: String; let worked_example: String }
    struct Assignment: Decodable {
        let question_number: Int
        let concept_number: Int
        let difficulty: Int
        let estimated_seconds: Int
    }
    let chapter_title: String
    let concepts: [ConceptItem]
    let assignments: [Assignment]

    static var schema: [String: Any] {
        Schema.object([
            "chapter_title": Schema.string,
            "concepts": Schema.array(Schema.object(["name": Schema.string, "summary": Schema.string, "worked_example": Schema.string])),
            "assignments": Schema.array(Schema.object([
                "question_number": Schema.integer,
                "concept_number": Schema.integer,
                "difficulty": Schema.integer,
                "estimated_seconds": Schema.integer,
            ])),
        ])
    }
}

// MARK: - Solve

struct SolveDTO: Decodable {
    let solution: String
    let final_answer: String
    let solvable: Bool

    static var schema: [String: Any] {
        Schema.object(["solution": Schema.string, "final_answer": Schema.string, "solvable": Schema.boolean])
    }
}

struct EquivalenceDTO: Decodable {
    let all_equivalent: Bool
    let best_answer: String
    let explanation: String

    static var schema: [String: Any] {
        Schema.object(["all_equivalent": Schema.boolean, "best_answer": Schema.string, "explanation": Schema.string])
    }
}

// MARK: - Grade

struct GradeDTO: Codable {
    let transcribed_work: String
    let transcribed_final_answer: String
    let verdict: String          // correct | incorrect | unreadable
    let agrees_with_reference: Bool
    let mistake_type: String     // none | conceptual | procedural | careless | misread | incomplete
    let error_step: String
    let feedback: String
    let confidence: Double

    static var schema: [String: Any] {
        Schema.object([
            "transcribed_work": Schema.string,
            "transcribed_final_answer": Schema.string,
            "verdict": Schema.enumeration(["correct", "incorrect", "unreadable"]),
            "agrees_with_reference": Schema.boolean,
            "mistake_type": Schema.enumeration(["none"] + MistakeType.allCases.map(\.rawValue)),
            "error_step": Schema.string,
            "feedback": Schema.string,
            "confidence": Schema.number,
        ])
    }
}

// MARK: - Variants

struct VariantsDTO: Decodable {
    struct Item: Decodable { let text: String; let final_answer: String; let solution: String; let estimated_seconds: Int }
    let questions: [Item]

    static var schema: [String: Any] {
        Schema.object(["questions": Schema.array(Schema.object([
            "text": Schema.string, "final_answer": Schema.string, "solution": Schema.string, "estimated_seconds": Schema.integer,
        ]))])
    }
}
