import Foundation
import SwiftData

/// Writes "Teacher's feedback" for a chapter or study plan: first after `FeedbackSummary.minimumAnswers` graded
/// answers, then again after every 30 minutes of further practice time. Runs in the background; the holder keeps
/// the last feedback. If writing fails, it is tried again the next time the page checks (a minute more practice,
/// or the page opening again).
@MainActor
final class TeacherFeedback: ObservableObject {
    static let shared = TeacherFeedback()
    @Published private(set) var writing: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    var services: ClaudeServices = .live

    static func answers(_ set: StudySet) -> [FeedbackSummary.Answer] {
        zip(set.allAttempts, set.cleanSeconds).compactMap { a, seconds in
            guard let q = a.question, !q.isChallenge, a.isGraded, let c = q.concept else { return nil }
            return FeedbackSummary.Answer(date: a.startedAt, seconds: seconds, estimate: Double(q.estimatedSeconds),
                                          rawSeconds: a.activeSeconds, timed: a.mode == .exam, skill: MathPlain.render(c.name),
                                          level: q.difficulty, verdict: a.effectiveVerdict,
                                          mistake: a.correction == nil ? a.mistakeType : nil,
                                          errorStep: a.correction == nil ? a.errorStep : "",
                                          helped: a.wasStuck || a.usedHint)
        }
    }

    /// Practice time: every answer's active time, breaks left out (the same total as the page's figure and the chart).
    static func practiceSeconds(_ set: StudySet) -> Double { set.practiceSeconds }

    /// Graded answers that count (enough of them before the card appears).
    static func gradedCount(_ set: StudySet) -> Int {
        answers(set).filter { $0.verdict != .needsReview }.count
    }

    static func shouldShow(_ set: StudySet, _ holder: FeedbackHolder) -> Bool {
        !holder.feedbackText.isEmpty || gradedCount(set) >= FeedbackSummary.minimumAnswers
    }

    /// The summary Claude sees, with mastery points per skill level.
    static func summary(_ set: StudySet) -> String {
        let planner = LearningStore.planner(set)
        var names: [UUID: String] = [:]
        for ch in set.chapters { for c in ch.concepts { names[c.id] = MathPlain.render(c.name) } }
        var points: [String: Int] = [:]
        for cell in planner.allCells {
            guard let name = names[cell.conceptID] else { continue }
            let key = "\(name)|\(cell.difficulty)"
            points[key] = Int(SkillBarsGrid.points(planner.skills[cell]))
        }
        return FeedbackSummary.text(answers(set), points: points)
    }

    func refreshIfDue(_ set: StudySet, _ holder: FeedbackHolder, context: ModelContext) {
        #if DEBUG
        // Screenshots without an API key: dump what Claude would get, and show feedback from a file.
        let env = ProcessInfo.processInfo.environment
        if let path = env["FEEDBACK_DUMP"] { try? Self.summary(set).write(toFile: path, atomically: true, encoding: .utf8) }
        if let path = env["FEEDBACK_SEED"], let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let parts = text.components(separatedBy: "\n---\n")
            holder.feedbackHeadline = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            holder.feedbackText = parts.dropFirst().joined().trimmingCharacters(in: .whitespacesAndNewlines)
            holder.feedbackAtSeconds = Self.practiceSeconds(set) - 6 * 60
            holder.feedbackDate = Date().addingTimeInterval(-25 * 60)
            return
        }
        #endif
        let id = holder.id
        guard !writing.contains(id), KeychainStore.apiKey != nil else { return }
        let seconds = Self.practiceSeconds(set)
        let last = holder.feedbackAtSeconds < 0 ? nil : holder.feedbackAtSeconds
        guard FeedbackSummary.isDue(practiceSeconds: seconds, answered: Self.gradedCount(set), lastFeedbackAt: last) else { return }
        let summary = Self.summary(set)
        let title = MathPlain.render(set.title)
        writing.insert(id)
        errors[id] = nil
        let services = self.services
        Task {
            defer { writing.remove(id) }
            do {
                let r = try await services.teacherFeedback(chapter: title, summary: summary)
                holder.feedbackHeadline = r.headline
                holder.feedbackText = r.feedback
                holder.feedbackAtSeconds = seconds
                holder.feedbackDate = Date()
                try? context.save()
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }
}
