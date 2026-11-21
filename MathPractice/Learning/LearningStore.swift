import Foundation
import SwiftData

/// What a practice session or exam draws from: a whole chapter or a saved scope (possibly across chapters).
@MainActor
struct StudySet {
    let title: String
    let chapters: [Chapter]
    /// Available questions in scope (generated questions follow the book question they came from).
    let questions: [Question]
    let examMinutes: Int

    static func chapter(_ c: Chapter) -> StudySet {
        StudySet(title: c.title, chapters: [c], questions: c.activeQuestions, examMinutes: c.examMinutes)
    }

    static func scope(_ s: StudyScope, chapters all: [Chapter]) -> StudySet {
        var chapters: [Chapter] = []
        var questions: [Question] = []
        for c in all {
            let items = s.items.filter { $0.split(separator: "|").dropFirst().first.map(String.init) == c.id.uuidString }
            guard !items.isEmpty else { continue }
            chapters.append(c)
            let available = c.activeQuestions
            let byID = Dictionary(uniqueKeysWithValues: c.questions.map { ($0.id, $0) })
            let nodes = c.outline
            func matches(_ q: Question) -> Bool {
                let base = q.parentQuestionID.flatMap { byID[$0] } ?? q
                return items.contains { item in
                    let parts = item.split(separator: "|").map(String.init)
                    switch parts.first {
                    case "c": return true
                    case "s": return parts.count == 3 && Int(parts[2]).map { Self.isWithin(base.sectionID, $0, nodes) } == true
                    case "p":
                        guard parts.count == 4, let from = Int(parts[2]), let to = Int(parts[3]), let page = base.printedPage else { return false }
                        return page >= from && page <= to
                    default: return false
                    }
                }
            }
            questions += available.filter(matches)
        }
        return StudySet(title: s.name, chapters: chapters, questions: questions, examMinutes: s.examMinutes)
    }

    /// True if `section` is `ancestor` or below it.
    static func isWithin(_ section: Int, _ ancestor: Int, _ nodes: [SectionNode]) -> Bool {
        var cur = section
        while nodes.indices.contains(cur) {
            if cur == ancestor { return true }
            cur = nodes[cur].parent
        }
        return false
    }

    var allAttempts: [Attempt] { questions.flatMap(\.attempts) }
}

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
                            lastWasCorrect: graded.last.map { $0.effectiveVerdict == .correct },
                            isChallenge: q.isChallenge)
    }

    static func skillMap(_ chapters: [Chapter]) -> [CellKey: SkillProgress] {
        var map: [CellKey: SkillProgress] = [:]
        for chapter in chapters {
            for s in chapter.skills {
                guard let concept = s.concept else { continue }
                map[CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: s.difficulty)] = s.progress
            }
        }
        return map
    }

    static func planner(_ set: StudySet, now: Date = Date()) -> Planner {
        Planner(questions: set.questions.compactMap(questionInfo), skills: skillMap(set.chapters), now: now)
    }

    static func planner(_ chapter: Chapter, now: Date = Date()) -> Planner { planner(.chapter(chapter), now: now) }

    static func skill(for q: Question, in chapter: Chapter, context: ModelContext) -> SkillState? {
        guard let concept = q.concept else { return nil }
        if let s = chapter.skill(concept: concept, difficulty: q.difficulty) { return s }
        let s = SkillState(concept: concept, difficulty: q.difficulty)
        s.chapter = chapter
        context.insert(s)
        return s
    }

    /// Applies a newly graded attempt to its skill cell. Challenge questions never affect mastery.
    static func apply(_ attempt: Attempt, context: ModelContext) {
        guard let q = attempt.question, !q.isChallenge, let chapter = q.chapter,
              attempt.isGraded, attempt.effectiveVerdict != .needsReview,
              let skill = skill(for: q, in: chapter, context: context) else { return }
        skill.progress = MasteryModel.apply(correct: attempt.effectiveVerdict == .correct, mistake: attempt.mistakeType,
                                            seconds: attempt.activeSeconds, to: skill.progress, now: attempt.startedAt)
    }

    /// Replays all graded attempts from scratch (used after a grade is corrected or a question is recategorized).
    static func rebuild(_ chapter: Chapter, context: ModelContext) {
        for s in chapter.skills { s.progress = SkillProgress() }
        let attempts = chapter.allAttempts.filter { $0.isGraded }.sorted { $0.startedAt < $1.startedAt }
        for a in attempts { apply(a, context: context) }
        try? context.save()
    }

    static func targetSeconds(for q: Question) -> Double {
        guard let chapter = q.chapter, let concept = q.concept, let s = chapter.skill(concept: concept, difficulty: q.difficulty) else {
            return Double(q.estimatedSeconds)
        }
        return MasteryModel.targetSeconds(estimate: Double(q.estimatedSeconds), progress: s.progress)
    }

    static func inSpeedStage(_ q: Question) -> Bool {
        guard !q.isChallenge, let chapter = q.chapter, let concept = q.concept,
              let s = chapter.skill(concept: concept, difficulty: q.difficulty) else { return false }
        return MasteryModel.inSpeedStage(s.progress)
    }
}
