import Foundation
import SwiftData

/// Grades answers in the background so the student never waits. Ungraded attempts are persisted
/// (isGraded == false) and retried when the app comes back or the network returns.
@MainActor
final class GradingQueue: ObservableObject {
    static let shared = GradingQueue()
    static let concurrency = 4

    /// Bumped whenever an attempt finishes grading (views re-check their attempts).
    @Published private(set) var version = 0
    private var inFlight: Set<UUID> = []
    private var waiting: [Attempt] = []
    var services: ClaudeServices = .live

    func pendingCount(_ attempts: [Attempt]) -> Int { attempts.filter { !$0.isGraded }.count }

    func enqueue(_ attempt: Attempt, context: ModelContext) {
        guard !attempt.isGraded, !inFlight.contains(attempt.id), !waiting.contains(where: { $0.id == attempt.id }) else { return }
        waiting.append(attempt)
        pump(context: context)
    }

    /// Re-queues anything left ungraded (app relaunch, network failures).
    func resumePending(context: ModelContext) {
        let pending = (try? context.fetch(FetchDescriptor<Attempt>(predicate: #Predicate { !$0.isGraded }))) ?? []
        for a in pending { enqueue(a, context: context) }
    }

    private func pump(context: ModelContext) {
        while inFlight.count < Self.concurrency, !waiting.isEmpty {
            let attempt = waiting.removeFirst()
            guard let q = attempt.question else { continue }
            inFlight.insert(attempt.id)
            let ctx = QuestionContext(text: q.text, figureJPEG: q.figureData, conceptName: q.concept?.name ?? "",
                                      bookAnswer: q.answerKeyAnswer)
            let work = attempt.wasStuck ? nil : attempt.renderedImage
            let blank = !attempt.wasStuck && work == nil
            let strict = q.source == .generated
            let services = self.services
            Task {
                defer {
                    inFlight.remove(attempt.id)
                    version += 1
                    pump(context: context)
                }
                if blank {
                    finish(attempt, GradeResult(verdict: .incorrect, mistake: .incomplete, transcribedAnswer: "", ownAnswer: "",
                                                errorStep: "", feedback: "This one was left blank.", workedSolution: "",
                                                questionFlawed: false, confidence: 1), context: context)
                    return
                }
                do {
                    let r = try await services.grade(ctx, work: work, strict: strict)
                    finish(attempt, r, context: context)
                } catch {
                    attempt.gradingError = error.localizedDescription
                    try? context.save()
                    if case ClaudeClient.ClientError.missingAPIKey = error { return }
                    // Retry later (network back / next check-in).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        self?.enqueue(attempt, context: context)
                    }
                }
            }
        }
    }

    /// Records a result obtained in the foreground (e.g. the solution she asked for) and notifies views.
    func record(_ attempt: Attempt, _ r: GradeResult, context: ModelContext) {
        finish(attempt, r, context: context)
        version += 1
    }

    private func finish(_ attempt: Attempt, _ r: GradeResult, context: ModelContext) {
        attempt.verdict = r.verdict
        attempt.mistakeType = r.mistake
        attempt.transcribedAnswer = r.transcribedAnswer
        attempt.ownAnswer = r.ownAnswer
        attempt.errorStep = r.errorStep
        attempt.feedback = r.verdict == .needsReview
            ? "I couldn't check this one for sure. It's saved under My answers → To check, so you can look at it later."
            : r.feedback
        attempt.workedSolution = r.workedSolution
        attempt.graderConfidence = r.confidence
        attempt.graderLog = r.graderLog
        attempt.gradingError = nil
        attempt.isGraded = true
        if r.questionFlawed, let q = attempt.question {
            // A flawed question doesn't count against her; take it out of practice.
            q.status = .retired
            q.reviewNote = "Claude found a problem with this question while grading: \(r.feedback)"
            attempt.verdict = .needsReview
            attempt.feedback = "This question seems to have a problem (it may be missing information), so it won't count. " + r.feedback
        }
        LearningStore.apply(attempt, context: context)
        try? context.save()
    }
}
