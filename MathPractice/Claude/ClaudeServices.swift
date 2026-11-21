import Foundation

/// Plain inputs/outputs for the Claude-backed steps. No SwiftData here, so these run off the main actor.
struct QuestionContext: Sendable {
    let text: String
    let figureJPEG: Data?
    let conceptName: String
    var bookAnswer: String? = nil
}

struct GradeResult: Sendable {
    let verdict: Verdict
    let mistake: MistakeType?
    let transcribedAnswer: String
    let ownAnswer: String
    let errorStep: String
    let feedback: String
    let workedSolution: String
    let questionFlawed: Bool
    let confidence: Double
    /// Claude's full grading reply(s) as JSON, kept for review and problem reports.
    var graderLog: String = ""
}

struct GeneratedQuestion: Sendable {
    let text: String
    let solution: String
    let finalAnswer: String
    let estimatedSeconds: Int
}

/// One question as sent to the classification step.
struct AssignInput: Sendable {
    let text: String
    let printedNumber: String
    let section: String
}

struct ClaudeServices: Sendable {
    let client: ClaudeClient

    static var live: ClaudeServices { ClaudeServices(client: ClaudeClient(apiKey: { KeychainStore.apiKey })) }

    // MARK: Reading pages

    /// `pages`: JPEGs for one batch. `contextPage`: the page just before, for section continuity only.
    func read(pages: [Data], answerKeyHints: [Bool], contextPage: Data?) async throws -> ReadDTO {
        var content: [ClaudeClient.Block] = []
        if let contextPage {
            content.append(.text("CONTEXT ONLY — the page before these images. Return nothing for it; use it only to know which section the next images continue:"))
            content.append(.jpeg(contextPage))
        }
        for (i, page) in pages.enumerated() {
            content.append(.text(answerKeyHints[i] ? "Image \(i + 1) (marked as an answer-key page):" : "Image \(i + 1):"))
            content.append(.jpeg(page))
        }
        content.append(.text("Read these \(pages.count) page images."))
        return try await client.structured(ReadDTO.self, system: Prompts.read, content: content,
                                           schema: ReadDTO.schema, effort: .high, maxTokens: 64000, kind: "read_pages")
    }

    // MARK: Organizing

    func outline(runs: [(path: [String], page: String, samples: [String])]) async throws -> OutlineDTO {
        var text = "Runs of content in reading order (page, section path as read on that page, first items):\n"
        for (i, r) in runs.enumerated() {
            text += "\(i + 1). [\(r.page)] " + r.path.joined(separator: " › ") + "\n"
            for s in r.samples.prefix(2) { text += "     e.g. " + s.prefix(120).replacingOccurrences(of: "\n", with: " ") + "\n" }
        }
        return try await client.structured(OutlineDTO.self, system: Prompts.outline, content: [.text(text)],
                                           schema: OutlineDTO.schema, effort: .high, maxTokens: 32000, kind: "outline")
    }

    func assign(questions: [AssignInput], concepts: [String], answers: [String]) async throws -> AssignDTO {
        var text = "Concepts:\n"
        for (i, c) in concepts.enumerated() { text += "\(i + 1). \(c)\n" }
        if !answers.isEmpty {
            text += "\nAnswer-key entries that may belong to these questions:\n"
            for (i, a) in answers.enumerated() { text += "\(i + 1). \(a)\n" }
        }
        text += "\nQuestions:\n"
        for (i, q) in questions.enumerated() {
            let label = q.printedNumber.isEmpty ? "" : " #\(q.printedNumber)"
            text += "\(i + 1). [\(q.section)\(label)] \(q.text)\n"
        }
        return try await client.structured(AssignDTO.self, system: Prompts.assign, content: [.text(text)],
                                           schema: AssignDTO.schema, effort: .medium, maxTokens: 32000, kind: "assign")
    }

    // MARK: Solving (generated questions only)

    private func questionBlocks(_ q: QuestionContext) -> [ClaudeClient.Block] {
        var blocks: [ClaudeClient.Block] = [.text("Question:\n\(q.text)")]
        if let fig = q.figureJPEG {
            blocks.append(.text("Figure for the question:"))
            blocks.append(.jpeg(fig))
        }
        return blocks
    }

    func solve(_ q: QuestionContext) async throws -> SolveDTO {
        try await client.structured(SolveDTO.self, system: Prompts.solve, content: questionBlocks(q),
                                    schema: SolveDTO.schema, effort: .high, kind: "solve_generated")
    }

    func equivalent(_ q: QuestionContext, candidates: [String]) async throws -> EquivalenceDTO {
        var blocks = questionBlocks(q)
        blocks.append(.text("Candidate final answers:\n" + candidates.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")))
        return try await client.structured(EquivalenceDTO.self, system: Prompts.equivalence, content: blocks,
                                           schema: EquivalenceDTO.schema, effort: .medium, kind: "equivalence")
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "$" }
    }

    // MARK: Grading

    /// Grades her work. `work == nil` means she was stuck (returns a worked solution).
    /// `strict`: always re-check an "incorrect" verdict (used for generated questions).
    func grade(_ q: QuestionContext, work: Data?, strict: Bool = false) async throws -> GradeResult {
        let first = try await gradeOnce(q, work: work, effort: .medium)
        if work == nil {
            var r = Self.result(from: first, stuck: true)
            r.graderLog = Self.log(["pass1 (stuck, effort medium)": first])
            return r
        }
        let suspicious = first.verdict == "unreadable" || first.confidence < 0.7
            || (first.verdict == "correct") != first.answers_equivalent
            || first.question_flawed
            || (strict && first.verdict == "incorrect")
        guard suspicious else {
            var result = Self.result(from: first, stuck: false)
            result.graderLog = Self.log(["pass1 (effort medium)": first])
            return result
        }

        let second = try await gradeOnce(q, work: work, effort: .high)
        var result = Self.result(from: second, stuck: false)
        let stillUnsure = second.verdict == "unreadable" || second.confidence < 0.6
            || second.verdict != first.verdict
            || ((second.verdict == "correct") != second.answers_equivalent && second.confidence < 0.85)
        if stillUnsure && !second.question_flawed {
            result = GradeResult(verdict: .needsReview, mistake: result.mistake, transcribedAnswer: result.transcribedAnswer,
                                 ownAnswer: result.ownAnswer, errorStep: result.errorStep, feedback: result.feedback,
                                 workedSolution: result.workedSolution, questionFlawed: false, confidence: second.confidence)
        }
        result.graderLog = Self.log(["pass1 (effort medium)": first, "pass2 recheck (effort high)": second,
                                     "outcome": stillUnsure ? "saved for review" : "pass2 verdict used"])
        return result
    }

    /// A nudge for a student who is stuck (optionally looking at her work so far). Never the final answer.
    func hint(_ q: QuestionContext, work: Data?) async throws -> String {
        var blocks = questionBlocks(q)
        blocks.append(.text("Skill being practiced: \(q.conceptName)"))
        if let key = q.bookAnswer, !key.isEmpty { blocks.append(.text("The book's answer key says: \(key)")) }
        if let work {
            blocks.append(.text("Her work so far:"))
            blocks.append(.png(work))
        }
        let dto = try await client.structured(HintDTO.self, system: Prompts.hint, content: blocks,
                                              schema: HintDTO.schema, effort: .medium, kind: "hint")
        return dto.hint
    }

    private static func log(_ items: [String: Any]) -> String {
        var obj: [String: Any] = [:]
        for (k, v) in items {
            if let g = v as? GradeDTO, let data = try? JSONEncoder().encode(g),
               let json = try? JSONSerialization.jsonObject(with: data) { obj[k] = json } else { obj[k] = v }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func gradeOnce(_ q: QuestionContext, work: Data?, effort: ClaudeClient.Effort) async throws -> GradeDTO {
        var blocks = questionBlocks(q)
        blocks.append(.text("Skill being practiced: \(q.conceptName)"))
        if let key = q.bookAnswer, !key.isEmpty { blocks.append(.text("The book's answer key says: \(key)")) }
        if let work {
            blocks.append(.text("Her handwritten work:"))
            blocks.append(.png(work))
        } else {
            blocks.append(.text("She tapped \"I'm stuck\" without an answer. Solve it and write a worked solution she can learn from."))
        }
        return try await client.structured(GradeDTO.self, system: Prompts.grade, content: blocks,
                                           schema: GradeDTO.schema, effort: effort, kind: work == nil ? "grade_stuck" : "grade")
    }

    private static func result(from g: GradeDTO, stuck: Bool) -> GradeResult {
        let verdict: Verdict
        if stuck { verdict = .incorrect }
        else if g.verdict == "correct" { verdict = .correct }
        else if g.verdict == "incorrect" { verdict = .incorrect }
        else { verdict = .needsReview }
        let mistake: MistakeType? = stuck ? .conceptual : (verdict == .incorrect ? MistakeType(rawValue: g.mistake_type) : nil)
        return GradeResult(verdict: verdict, mistake: mistake, transcribedAnswer: g.transcribed_final_answer,
                           ownAnswer: g.own_final_answer, errorStep: g.error_step, feedback: g.feedback,
                           workedSolution: g.worked_solution.isEmpty && verdict != .correct ? g.own_solution : g.worked_solution,
                           questionFlawed: g.question_flawed, confidence: g.confidence)
    }

    // MARK: Variants

    /// Generates new questions for a skill; each must survive an independent re-solve.
    func generateVariants(example: QuestionContext, difficulty: Int,
                          recentMistakes: [String], count: Int = 3) async throws -> [GeneratedQuestion] {
        var blocks = questionBlocks(example)
        blocks.append(.text("Skill: \(example.conceptName)\nDifficulty (1–3): \(difficulty)"))
        if !recentMistakes.isEmpty {
            blocks.append(.text("Her recent mistakes on this skill:\n" + recentMistakes.map { "- \($0)" }.joined(separator: "\n")))
        }
        blocks.append(.text("Write \(count) new questions."))
        let dto = try await client.structured(VariantsDTO.self, system: Prompts.variants, content: blocks,
                                              schema: VariantsDTO.schema, effort: .high, kind: "variants")
        return try await withThrowingTaskGroup(of: GeneratedQuestion?.self) { group in
            for item in dto.questions.prefix(count) {
                group.addTask {
                    let ctx = QuestionContext(text: item.text, figureJPEG: nil, conceptName: example.conceptName)
                    let check = try await solve(ctx)
                    guard check.solvable else { return nil }
                    if Self.normalize(check.final_answer) != Self.normalize(item.final_answer) {
                        let eq = try await equivalent(ctx, candidates: [item.final_answer, check.final_answer])
                        guard eq.all_equivalent else { return nil }
                    }
                    return GeneratedQuestion(text: item.text, solution: item.solution, finalAnswer: item.final_answer,
                                             estimatedSeconds: item.estimated_seconds)
                }
            }
            var out: [GeneratedQuestion] = []
            for try await q in group { if let q { out.append(q) } }
            return out
        }
    }
}
