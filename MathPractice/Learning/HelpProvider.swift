import Foundation

/// Fetches "I'm stuck" help. Debug builds launched with `-fakeHelp` answer instantly with canned text (UI tests).
enum HelpProvider {
    static func hint(_ q: QuestionContext, _ work: Data?) async throws -> String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fakeHelp") {
            try await Task.sleep(nanoseconds: 800_000_000)
            return "What operation is being done to $x$? Try undoing it on both sides."
        }
        #endif
        return try await ClaudeServices.live.hint(q, work: work)
    }

    static func solution(_ q: QuestionContext) async throws -> GradeResult {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fakeHelp") {
            try await Task.sleep(nanoseconds: 800_000_000)
            return GradeResult(verdict: .incorrect, mistake: .conceptual, transcribedAnswer: "", ownAnswer: "x = 8",
                               errorStep: "", feedback: "", workedSolution: (["1. Subtract $7$ from both sides.", "2. $x = 8$."] + (ProcessInfo.processInfo.arguments.contains("-longHelp") ? (3...20).map { i in "\(i). Check: $8 + 7 = 15$ ✓" } : [])).joined(separator: "\n"),
                               questionFlawed: false, confidence: 1)
        }
        #endif
        return try await ClaudeServices.live.grade(q, work: nil)
    }
}
