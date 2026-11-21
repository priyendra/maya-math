import Foundation

// JSON schemas for structured outputs + matching Codable DTOs.
// Every object needs additionalProperties:false and a full `required` list.
// Properties are generated in the order listed (OrderedObject), which we use deliberately.
// Numeric bounds aren't supported by the API, so ranges are validated in code.

enum Schema {
    static func object(_ properties: KeyValuePairs<String, Any>) -> OrderedObject {
        OrderedObject(pairs: [
            ("type", "object"),
            ("properties", OrderedObject(pairs: properties.map { ($0.key, $0.value) })),
            ("required", properties.map(\.key)),
            ("additionalProperties", false),
        ])
    }
    static func array(_ items: Any) -> [String: Any] { ["type": "array", "items": items] }
    static let string: [String: Any] = ["type": "string"]
    static let integer: [String: Any] = ["type": "integer"]
    static let number: [String: Any] = ["type": "number"]
    static let boolean: [String: Any] = ["type": "boolean"]
    static func enumeration(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
    static let box = object(["x": number, "y": number, "width": number, "height": number])
}

struct BoxDTO: Codable, Hashable {
    let x: Double; let y: Double; let width: Double; let height: Double
    var isEmpty: Bool { width <= 0 || height <= 0 }
}

// MARK: - Reading pages (batch of images)

struct ReadDTO: Codable {
    struct Block: Codable {
        /// heading | text | example | figure | exercise | answer
        let kind: String
        let section_path: [String]
        let markdown: String
        let question_markdown: String
        let printed_number: String
        let has_figure: Bool
        let figure_box: BoxDTO
        let pencil_ok: Bool
        let pencil_reason: String
        let is_challenge: Bool
    }
    struct Page: Codable {
        let image_number: Int
        let printed_page_number: Int
        let is_answer_key: Bool
        let blocks: [Block]
    }
    let pages: [Page]

    static var schema: OrderedObject {
        Schema.object([
            "pages": Schema.array(Schema.object([
                "image_number": Schema.integer,
                "printed_page_number": Schema.integer,
                "is_answer_key": Schema.boolean,
                "blocks": Schema.array(Schema.object([
                    "kind": Schema.enumeration(["heading", "text", "example", "figure", "exercise", "answer"]),
                    "section_path": Schema.array(Schema.string),
                    "markdown": Schema.string,
                    "question_markdown": Schema.string,
                    "printed_number": Schema.string,
                    "has_figure": Schema.boolean,
                    "figure_box": Schema.box,
                    "pencil_ok": Schema.boolean,
                    "pencil_reason": Schema.string,
                    "is_challenge": Schema.boolean,
                ])),
            ])),
        ])
    }
}

// MARK: - Outline (whole chapter): canonical sections + concepts

struct OutlineDTO: Decodable {
    struct Section: Decodable { let title: String; let level: Int }
    struct PathMap: Decodable { let run_number: Int; let section_number: Int }
    struct ConceptItem: Decodable { let name: String; let summary: String; let worked_example: String }
    let chapter_title: String
    let sections: [Section]
    let path_map: [PathMap]
    let concepts: [ConceptItem]

    static var schema: OrderedObject {
        Schema.object([
            "chapter_title": Schema.string,
            "sections": Schema.array(Schema.object(["title": Schema.string, "level": Schema.integer])),
            "path_map": Schema.array(Schema.object(["run_number": Schema.integer, "section_number": Schema.integer])),
            "concepts": Schema.array(Schema.object(["name": Schema.string, "summary": Schema.string, "worked_example": Schema.string])),
        ])
    }
}

// MARK: - Assign (batch of questions): concept, difficulty, time, answer-key link

struct AssignDTO: Decodable {
    struct Item: Decodable {
        let question_number: Int
        let concept_number: Int
        let difficulty: Int
        let estimated_seconds: Int
        let answer_number: Int
    }
    let items: [Item]

    static var schema: OrderedObject {
        Schema.object(["items": Schema.array(Schema.object([
            "question_number": Schema.integer,
            "concept_number": Schema.integer,
            "difficulty": Schema.integer,
            "estimated_seconds": Schema.integer,
            "answer_number": Schema.integer,
        ]))])
    }
}

// MARK: - Solve (generated questions only)

struct SolveDTO: Decodable {
    let solution: String
    let final_answer: String
    let solvable: Bool

    static var schema: OrderedObject {
        Schema.object(["solution": Schema.string, "final_answer": Schema.string, "solvable": Schema.boolean])
    }
}

struct EquivalenceDTO: Decodable {
    let all_equivalent: Bool
    let best_answer: String
    let explanation: String

    static var schema: OrderedObject {
        Schema.object(["all_equivalent": Schema.boolean, "best_answer": Schema.string, "explanation": Schema.string])
    }
}

// MARK: - Grade (the grader solves first)

struct GradeDTO: Codable {
    let own_solution: String
    let own_final_answer: String
    let transcribed_work: String
    let transcribed_final_answer: String
    let answers_equivalent: Bool
    let verdict: String          // correct | incorrect | unreadable
    let mistake_type: String     // none | conceptual | procedural | careless | misread | incomplete
    let error_step: String
    let feedback: String
    let worked_solution: String
    let question_flawed: Bool
    let confidence: Double

    static var schema: OrderedObject {
        Schema.object([
            "own_solution": Schema.string,
            "own_final_answer": Schema.string,
            "transcribed_work": Schema.string,
            "transcribed_final_answer": Schema.string,
            "answers_equivalent": Schema.boolean,
            "verdict": Schema.enumeration(["correct", "incorrect", "unreadable"]),
            "mistake_type": Schema.enumeration(["none"] + MistakeType.allCases.map(\.rawValue)),
            "error_step": Schema.string,
            "feedback": Schema.string,
            "worked_solution": Schema.string,
            "question_flawed": Schema.boolean,
            "confidence": Schema.number,
        ])
    }
}

// MARK: - Variants

struct VariantsDTO: Decodable {
    struct Item: Decodable { let text: String; let final_answer: String; let solution: String; let estimated_seconds: Int }
    let questions: [Item]

    static var schema: OrderedObject {
        Schema.object(["questions": Schema.array(Schema.object([
            "text": Schema.string, "final_answer": Schema.string, "solution": Schema.string, "estimated_seconds": Schema.integer,
        ]))])
    }
}
