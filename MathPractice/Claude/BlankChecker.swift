import Foundation

/// Reads what she wrote in a lesson's fill-in-the-blank and checks it against the expected answer.
enum BlankChecker {
    struct Result: Codable, Equatable {
        let read: String
        let correct: Bool
    }

    static let schema = Schema.object(["read": Schema.string, "correct": Schema.boolean])

    static func check(line: String, answer: String, image: Data) async throws -> Result {
        if ProcessInfo.processInfo.arguments.contains("-fakeTutor") { return Result(read: answer, correct: true) }
        let content: [ClaudeClient.Block] = [
            .text("Board line: \(line)\nExpected answer: \(answer)\nHer handwriting in the blank:"),
            .png(image),
        ]
        return try await ClaudeServices.live.client.structured(
            Result.self, system: Prompts.blankCheck, content: content, schema: schema,
            effort: .low, maxTokens: 300, kind: "blank_check")
    }
}
