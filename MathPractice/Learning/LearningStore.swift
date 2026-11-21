import Foundation
import SwiftData

/// Bridges SwiftData models and the pure learning engine.
@MainActor
enum LearningStore {
    static func cellKey(_ q: Question) -> CellKey? {
        guard let concept = q.concept else { return nil }
        return CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: q.difficulty)
    }

    static func questionInfo(_ q: Question) -> QuestionInfo? {
        guard let cell = cellKey(q) else { return nil }
        let graded = q.gradedAttempts
        return QuestionInfo(id: q.id, cell: cell, isGenerated: q.source == .generated,
                            estimatedSeconds: Double(q.estimatedSeconds), timesSeen: q.attempts.count,
                            lastSeen: q.attempts.map(\.startedAt).max(),
                            lastWasCorrect: graded.last.map { $0.effectiveVerdict == .correct })
    }

    static func skillMap(_ chapter: Chapter) -> [CellKey: SkillProgress] {
        var map: [CellKey: SkillProgress] = [:]
        for s in chapter.skills {
            guard let concept = s.concept else { continue }
            map[CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: s.difficulty)] = s.progress
        }
        return map
    }

    static func planner(_ chapter: Chapter, now: Date = Date()) -> Planner {
        Planner(questions: chapter.activeQuestions.compactMap(questionInfo), skills: skillMap(chapter), now: now)
    }

    static func skill(for q: Question, in chapter: Chapter, context: ModelContext) -> SkillState? {
        guard let concept = q.concept else { return nil }
        if let s = chapter.skill(concept: concept, difficulty: q.difficulty) { return s }
        let s = SkillState(concept: concept, difficulty: q.difficulty)
        s.chapter = chapter
        context.insert(s)
        return s
    }

    /// Applies a newly graded attempt to its skill cell.
    static func apply(_ attempt: Attempt, context: ModelContext) {
        guard let q = attempt.question, let chapter = q.chapter,
              attempt.effectiveVerdict != .needsReview,
              let skill = skill(for: q, in: chapter, context: context) else { return }
        skill.progress = MasteryModel.apply(correct: attempt.effectiveVerdict == .correct, mistake: attempt.mistakeType,
                                            seconds: attempt.activeSeconds, to: skill.progress, now: attempt.startedAt)
    }

    /// Replays all graded attempts from scratch (used after a parent overrides a grade or edits categories).
    static func rebuild(_ chapter: Chapter, context: ModelContext) {
        for s in chapter.skills { s.progress = SkillProgress() }
        let attempts = chapter.allAttempts.filter { $0.isGraded }.sorted { $0.startedAt < $1.startedAt }
        for a in attempts { apply(a, context: context) }
        try? context.save()
    }

    static func targetSeconds(for q: Question, in chapter: Chapter) -> Double {
        guard let concept = q.concept, let s = chapter.skill(concept: concept, difficulty: q.difficulty) else {
            return Double(q.estimatedSeconds)
        }
        return MasteryModel.targetSeconds(estimate: Double(q.estimatedSeconds), progress: s.progress)
    }

    static func inSpeedStage(_ q: Question, in chapter: Chapter) -> Bool {
        guard let concept = q.concept, let s = chapter.skill(concept: concept, difficulty: q.difficulty) else { return false }
        return MasteryModel.inSpeedStage(s.progress)
    }
}
