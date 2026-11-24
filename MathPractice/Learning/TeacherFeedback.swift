import Foundation
import SwiftData

/// Writes "Teacher's feedback" for a chapter: first after `FeedbackSummary.minimumAnswers` answers, then again after
/// every 30 minutes of further practice. Runs in the background; the chapter keeps the last feedback.
@MainActor
final class TeacherFeedback: ObservableObject {
    static let shared = TeacherFeedback()
    @Published private(set) var writing: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    var services: ClaudeServices = .live

    static func answers(_ chapter: Chapter) -> [FeedbackSummary.Answer] {
        chapter.allAttempts.compactMap { a in
            guard let q = a.question, !q.isChallenge, a.isGraded, let c = q.concept else { return nil }
            return FeedbackSummary.Answer(date: a.startedAt, seconds: a.activeSeconds, skill: MathPlain.render(c.name),
                                          level: q.difficulty, verdict: a.effectiveVerdict,
                                          mistake: a.correction == nil ? a.mistakeType : nil,
                                          errorStep: a.correction == nil ? a.errorStep : "",
                                          helped: a.wasStuck || !a.hintText.isEmpty)
        }
    }

    static func practiceSeconds(_ chapter: Chapter) -> Double {
        answers(chapter).map(\.seconds).reduce(0, +)
    }

    /// The summary Claude sees, with progress toward the star per skill level.
    static func summary(_ chapter: Chapter) -> String {
        let planner = LearningStore.planner(.chapter(chapter))
        var names: [UUID: String] = [:]
        for c in chapter.concepts { names[c.id] = MathPlain.render(c.name) }
        var steps: [String: Int] = [:]
        var mastered: Set<String> = []
        for cell in planner.allCells {
            guard let name = names[cell.conceptID] else { continue }
            let key = "\(name)|\(cell.difficulty)"
            steps[key] = MasteryModel.dots(planner.skills[cell]?.mastery ?? 0)
            if planner.isMastered(cell) { mastered.insert(key) }
        }
        return FeedbackSummary.text(answers(chapter), steps: steps, mastered: mastered)
    }

    func refreshIfDue(_ chapter: Chapter, context: ModelContext, force: Bool = false) {
        #if DEBUG
        // Screenshots without an API key: dump what Claude would get, and show feedback from a file.
        let env = ProcessInfo.processInfo.environment
        if let path = env["FEEDBACK_DUMP"] { try? Self.summary(chapter).write(toFile: path, atomically: true, encoding: .utf8) }
        if let path = env["FEEDBACK_SEED"], let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let parts = text.components(separatedBy: "\n---\n")
            chapter.feedbackHeadline = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            chapter.feedbackText = parts.dropFirst().joined().trimmingCharacters(in: .whitespacesAndNewlines)
            chapter.feedbackAtSeconds = Self.practiceSeconds(chapter) - 6 * 60
            chapter.feedbackDate = Date().addingTimeInterval(-25 * 60)
            return
        }
        #endif
        guard !writing.contains(chapter.id), KeychainStore.apiKey != nil else { return }
        let all = Self.answers(chapter)
        let seconds = all.map(\.seconds).reduce(0, +)
        let graded = all.filter { $0.verdict != .needsReview }.count
        let last = chapter.feedbackAtSeconds < 0 ? nil : chapter.feedbackAtSeconds
        guard force ? graded > 0 : FeedbackSummary.isDue(practiceSeconds: seconds, answered: graded, lastFeedbackAt: last) else { return }
        let summary = Self.summary(chapter)
        let title = MathPlain.render(chapter.title)
        let id = chapter.id
        writing.insert(id)
        errors[id] = nil
        let services = self.services
        Task {
            defer { writing.remove(id) }
            do {
                let r = try await services.teacherFeedback(chapter: title, summary: summary)
                chapter.feedbackHeadline = r.headline
                chapter.feedbackText = r.feedback
                chapter.feedbackAtSeconds = seconds
                chapter.feedbackDate = Date()
                try? context.save()
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }
}
