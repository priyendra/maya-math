import Foundation
import SwiftData

/// Keeps a supply of fresh questions for skills that have run out of unseen book questions.
/// Runs in the background; each generated question is independently re-solved before use.
@MainActor
final class VariantGenerator {
    static let shared = VariantGenerator()
    static let maxGeneratedPerCell = 15
    static let maxConcurrentCells = 2

    private var inFlight: Set<CellKey> = []
    var services: ClaudeServices = .live

    func refill(_ chapter: Chapter, context: ModelContext) { refill(.chapter(chapter), context: context) }

    /// Generates questions for in-scope skills that have run out of unseen questions.
    func refill(_ set: StudySet, context: ModelContext) {
        // Not while the chapter's own book questions are still being solved.
        guard KeychainStore.apiKey != nil else { return }
        let planner = LearningStore.planner(set)
        let cells = planner.cellsNeedingVariants().filter { !inFlight.contains($0) }
        for cell in cells.prefix(max(0, Self.maxConcurrentCells - inFlight.count)) {
            let inCell = set.questions.filter { LearningStore.cellKey($0) == cell }
            guard inCell.filter({ $0.source == .generated }).count < Self.maxGeneratedPerCell else { continue }
            // Base new questions on one she got wrong if possible, else any trusted text-only-friendly one.
            let candidates = inCell.filter { $0.isAvailable && !$0.isChallenge }
            let wrong = candidates.filter { q in q.gradedAttempts.last?.effectiveVerdict == .incorrect }
            guard let example = (wrong.first ?? candidates.first(where: { $0.source == .book }) ?? candidates.first),
                  let concept = example.concept, let chapter = example.chapter else { continue }
            let mistakes = inCell.flatMap(\.attempts)
                .filter { $0.effectiveVerdict == .incorrect && !$0.errorStep.isEmpty }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(4)
                .map { "\($0.mistakeType?.displayName ?? "Mistake"): \($0.errorStep)" }

            inFlight.insert(cell)
            let ctx = QuestionContext(text: example.text, figureJPEG: example.figureData, conceptName: concept.name)
            let difficulty = example.difficulty, exampleID = example.id
            let sectionID = example.sectionID, printedPage = example.printedPage
            let services = self.services
            Task {
                defer { inFlight.remove(cell) }
                guard let generated = try? await services.generateVariants(example: ctx, difficulty: difficulty,
                                                                           recentMistakes: Array(mistakes)) else { return }
                for g in generated {
                    let q = Question(text: g.text, difficulty: difficulty, source: .generated)
                    q.referenceAnswer = g.finalAnswer
                    q.referenceSolution = g.solution
                    q.estimatedSeconds = min(max(g.estimatedSeconds, 20), 1200)
                    q.parentQuestionID = exampleID
                    q.sectionID = sectionID
                    q.printedPage = printedPage
                    q.concept = concept
                    q.chapter = chapter
                    context.insert(q)
                }
                try? context.save()
            }
        }
    }
}
