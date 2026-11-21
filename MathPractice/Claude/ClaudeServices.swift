import Foundation

/// Plain inputs/outputs for the Claude-backed steps. No SwiftData here, so these run off the main actor.
struct QuestionContext: Sendable {
    let text: String
    let figureJPEG: Data?
    let conceptName: String
}

struct VerifiedSolution: Sendable {
    let solution: String
    let finalAnswer: String
    let trusted: Bool
    let note: String?
}

struct GradeResult: Sendable {
    let verdict: Verdict
    let mistake: MistakeType?
    let transcribedAnswer: String
    let errorStep: String
    let feedback: String
    let confidence: Double
    /// Claude's full grading reply(s) as JSON, kept for problem reports.
    var graderLog: String = ""
}

struct GeneratedQuestion: Sendable {
    let text: String
    let solution: String
    let finalAnswer: String
    let estimatedSeconds: Int
}

struct ClaudeServices: Sendable {
    let client: ClaudeClient

    static var live: ClaudeServices { ClaudeServices(client: ClaudeClient(apiKey: { KeychainStore.apiKey })) }

    // MARK: Extraction

    /// `pages`: JPEGs for one batch; `answerKeyFlags[i]` marks answer-key pages.
    /// `contextPage`: the page just before this batch, shown only so Claude knows which section it continues.
    func extract(pages: [Data], answerKeyFlags: [Bool], contextPage: Data? = nil) async throws -> ExtractionDTO {
        var content: [ClaudeClient.Block] = []
        if let contextPage {
            content.append(.text("CONTEXT ONLY — the page before this batch. Do not extract anything from it; use it only to know which section the next images continue:"))
            content.append(.jpeg(contextPage))
        }
        for (i, page) in pages.enumerated() {
            let label = answerKeyFlags[i] ? "Image \(i + 1) (ANSWER KEY page):" : "Image \(i + 1):"
            content.append(.text(label))
            content.append(.jpeg(page))
        }
        content.append(.text("Extract the content of these \(pages.count) page images."))
        return try await client.structured(ExtractionDTO.self, system: Prompts.extract, content: content,
                                           schema: ExtractionDTO.schema, effort: .high, maxTokens: 64000)
    }

    func organize(questions: [(ref: String, section: String, text: String)],
                  sections: [ExtractionDTO.Section],
                  examples: [ExtractionDTO.Example]) async throws -> OrganizeDTO {
        var text = "Book sections:\n"
        for s in sections { text += "- \(s.heading): \(s.summary)\n" }
        if !examples.isEmpty {
            text += "\nWorked examples from the book:\n"
            for e in examples.prefix(20) { text += "[\(e.section_heading)]\n\(e.text)\n\n" }
        }
        text += "\nQuestions:\n"
        for (i, q) in questions.enumerated() { text += "\(i + 1). [\(q.ref) — \(q.section)] \(q.text)\n" }
        return try await client.structured(OrganizeDTO.self, system: Prompts.organize, content: [.text(text)],
                                           schema: OrganizeDTO.schema, effort: .high, maxTokens: 64000)
    }

    // MARK: Solving

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
                                    schema: SolveDTO.schema, effort: .high)
    }

    /// Trusted only when independent answers agree. With a book answer key, one solve that matches the key
    /// is enough (two independent sources); otherwise two independent solves must agree.
    func solveVerified(_ q: QuestionContext, answerKey: String?) async throws -> VerifiedSolution {
        if let key = answerKey, !key.isEmpty {
            let s = try await solve(q)
            if s.solvable {
                if Self.normalize(s.final_answer) == Self.normalize(key) {
                    return VerifiedSolution(solution: s.solution, finalAnswer: s.final_answer, trusted: true, note: nil)
                }
                let check = try await equivalent(q, candidates: [s.final_answer, key])
                if check.all_equivalent {
                    return VerifiedSolution(solution: s.solution, finalAnswer: key, trusted: true, note: nil)
                }
            }
            // Disagreement with the key (or unsolvable): fall through to the full two-solve check below.
        }
        async let a = solve(q)
        async let b = solve(q)
        let (s1, s2) = try await (a, b)
        guard s1.solvable && s2.solvable else {
            return VerifiedSolution(solution: s1.solution, finalAnswer: s1.final_answer, trusted: false,
                                    note: "Claude thinks this question may be ambiguous or missing information.")
        }
        var candidates = [s1.final_answer, s2.final_answer]
        if let key = answerKey, !key.isEmpty { candidates.append(key) }
        if Set(candidates.map(Self.normalize)).count == 1 {
            return VerifiedSolution(solution: s1.solution, finalAnswer: s1.final_answer, trusted: true, note: nil)
        }
        let check = try await equivalent(q, candidates: candidates)
        if check.all_equivalent {
            return VerifiedSolution(solution: s1.solution, finalAnswer: answerKey ?? s1.final_answer, trusted: true, note: nil)
        }
        let source = answerKey == nil ? "Two independent solutions disagreed" : "Claude's solution and the answer key disagreed"
        return VerifiedSolution(solution: s1.solution, finalAnswer: check.best_answer, trusted: false,
                                note: "\(source): \(candidates.joined(separator: " vs. ")). \(check.explanation)")
    }

    func equivalent(_ q: QuestionContext, candidates: [String]) async throws -> EquivalenceDTO {
        var blocks = questionBlocks(q)
        blocks.append(.text("Candidate final answers:\n" + candidates.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")))
        return try await client.structured(EquivalenceDTO.self, system: Prompts.equivalence, content: blocks,
                                           schema: EquivalenceDTO.schema, effort: .medium)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "$" }
    }

    // MARK: Grading

    func grade(_ q: QuestionContext, referenceAnswer: String, referenceSolution: String, work: Data) async throws -> GradeResult {
        let first = try await gradeOnce(q, referenceAnswer: referenceAnswer, referenceSolution: referenceSolution, work: work, effort: .medium)
        let suspicious = first.verdict == "unreadable" || first.confidence < 0.7
            || (first.verdict == "correct") != first.agrees_with_reference
        guard suspicious else {
            var result = Self.result(from: first)
            result.graderLog = Self.log(["pass1 (effort medium)": first])
            return result
        }

        // Re-check carefully; if still unsure, leave it for the parent.
        let second = try await gradeOnce(q, referenceAnswer: referenceAnswer, referenceSolution: referenceSolution, work: work, effort: .high)
        var result = Self.result(from: second)
        let stillUnsure = second.verdict == "unreadable" || second.confidence < 0.6
            || second.verdict != first.verdict
            || ((second.verdict == "correct") != second.agrees_with_reference && second.confidence < 0.85)
        if stillUnsure {
            result = GradeResult(verdict: .needsReview, mistake: result.mistake, transcribedAnswer: result.transcribedAnswer,
                                 errorStep: result.errorStep, feedback: result.feedback, confidence: second.confidence)
        }
        result.graderLog = Self.log(["pass1 (effort medium)": first, "pass2 recheck (effort high)": second,
                                     "outcome": stillUnsure ? "saved for review" : "pass2 verdict used"])
        return result
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

    private func gradeOnce(_ q: QuestionContext, referenceAnswer: String, referenceSolution: String, work: Data, effort: ClaudeClient.Effort) async throws -> GradeDTO {
        var blocks = questionBlocks(q)
        blocks.append(.text("Skill being practiced: \(q.conceptName)"))
        blocks.append(.text("Reference final answer (prepared in advance): \(referenceAnswer)\n\nReference solution (one valid method; hers may differ):\n\(referenceSolution)"))
        blocks.append(.text("Her handwritten work:"))
        blocks.append(.png(work))
        return try await client.structured(GradeDTO.self, system: Prompts.grade, content: blocks,
                                           schema: GradeDTO.schema, effort: effort)
    }

    private static func result(from g: GradeDTO) -> GradeResult {
        let verdict: Verdict = switch g.verdict {
        case "correct": .correct
        case "incorrect": .incorrect
        default: .needsReview
        }
        return GradeResult(verdict: verdict, mistake: verdict == .incorrect ? MistakeType(rawValue: g.mistake_type) : nil,
                           transcribedAnswer: g.transcribed_final_answer, errorStep: g.error_step,
                           feedback: g.feedback, confidence: g.confidence)
    }

    // MARK: Variants

    /// Generates new questions for a skill; each must survive an independent re-solve.
    func generateVariants(example: QuestionContext, exampleAnswer: String, difficulty: Int,
                          recentMistakes: [String], count: Int = 3) async throws -> [GeneratedQuestion] {
        var blocks = questionBlocks(example)
        blocks.append(.text("Example answer: \(exampleAnswer)\nSkill: \(example.conceptName)\nDifficulty (1–3): \(difficulty)"))
        if !recentMistakes.isEmpty {
            blocks.append(.text("Her recent mistakes on this skill:\n" + recentMistakes.map { "- \($0)" }.joined(separator: "\n")))
        }
        blocks.append(.text("Write \(count) new questions."))
        let dto = try await client.structured(VariantsDTO.self, system: Prompts.variants, content: blocks,
                                              schema: VariantsDTO.schema, effort: .high)
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
