import Foundation
import SwiftData

// Enums are stored as raw strings in SwiftData models for robustness.

enum ChapterStatus: String, Codable, CaseIterable {
    case processing, ready, failed
    /// Pages were read, but some need another scan (or pages are missing) before the chapter is built.
    case needsRescan
}

enum QuestionSource: String, Codable {
    case book, generated
}

enum QuestionStatus: String, Codable {
    case ok                 // trusted, available for practice
    case needsCheck         // solvers disagreed / answer-key mismatch; held back until checked
    case retired            // removed from practice
}

enum AttemptMode: String, Codable {
    case practice, exam
    /// A "your turn" problem inside a lesson (counts toward mastery like practice).
    case lesson
}

enum Verdict: String, Codable {
    case correct, incorrect, needsReview
}

enum MistakeType: String, Codable, CaseIterable {
    case conceptual, procedural, careless, misread, incomplete

    var displayName: String {
        switch self {
        case .conceptual: return "Concept"
        case .procedural: return "Method step"
        case .careless: return "Careless slip"
        case .misread: return "Misread question"
        case .incomplete: return "Incomplete"
        }
    }
}

@Model
final class Chapter {
    var id: UUID = UUID()
    var title: String = "New chapter"
    var createdAt: Date = Date()
    var statusRaw: String = ChapterStatus.processing.rawValue
    var progressMessage: String = ""
    var progressFraction: Double = 0
    var errorMessage: String?
    /// Exam length in minutes (configurable per chapter).
    var examMinutes: Int = 30
    /// 2 = digital-chapter pipeline. Chapters below this were processed by the old pipeline and need re-reading.
    var formatVersion: Int = 1
    /// Section tree as JSON: [SectionNode] in book order.
    var outlineJSON: String = ""
    /// Problems found with the scanned pages (missing / repeated page numbers), shown after processing.
    var pageWarning: String?
    /// She chose "Continue anyway" on the rescan list: build the chapter without asking again.
    var scanIssuesAccepted: Bool = false
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \PageImage.chapter) var pages: [PageImage] = []
    @Relationship(deleteRule: .cascade, inverse: \Concept.chapter) var concepts: [Concept] = []
    @Relationship(deleteRule: .cascade, inverse: \Question.chapter) var questions: [Question] = []
    @Relationship(deleteRule: .cascade, inverse: \SkillState.chapter) var skills: [SkillState] = []
    @Relationship(deleteRule: .cascade, inverse: \ExamSession.chapter) var exams: [ExamSession] = []
    @Relationship(deleteRule: .cascade, inverse: \ContentBlock.chapter) var blocks: [ContentBlock] = []
    @Relationship(deleteRule: .cascade, inverse: \Lesson.chapter) var lessons: [Lesson] = []
    /// Sections deliberately left out of lessons, with why: JSON [LessonPlan.Skipped].
    var lessonSkippedJSON: String = ""
    /// LessonPlanner.version the lessons were planned with (older plans may be replanned).
    var lessonPlanVersion: Int = 0
    /// "Teacher's feedback": Claude's notes on her answers so far (Markdown), its one-line headline,
    /// the practice time (seconds) it was written at, and when.
    var feedbackHeadline: String = ""
    var feedbackText: String = ""
    var feedbackAtSeconds: Double = -1
    var feedbackDate: Date?

    init(title: String = "New chapter") {
        self.title = title
    }

    var status: ChapterStatus {
        get { ChapterStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var sortedPages: [PageImage] { pages.sorted { $0.order < $1.order } }
    var sortedConcepts: [Concept] { concepts.sorted { $0.bookOrder < $1.bookOrder } }
    /// Questions available for practice and exams (not removed, doable with a pencil or included by hand).
    var activeQuestions: [Question] { questions.filter(\.isAvailable) }
    var sortedBlocks: [ContentBlock] { blocks.sorted { $0.order < $1.order } }
    var sortedLessons: [Lesson] { lessons.sorted { $0.order < $1.order } }
    /// 2 = digital chapter; 3 = outline mapped per run in reading order.
    static let currentFormat = 3
    var needsRereading: Bool { formatVersion < 2 && !pages.isEmpty }

    var outline: [SectionNode] {
        get { (try? JSONDecoder().decode([SectionNode].self, from: Data(outlineJSON.utf8))) ?? [] }
        set { outlineJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "" }
    }
    var allAttempts: [Attempt] { questions.flatMap { $0.attempts } }

    func skill(concept: Concept, difficulty: Int) -> SkillState? {
        skills.first { $0.concept?.id == concept.id && $0.difficulty == difficulty }
    }
}

@Model
final class PageImage {
    var id: UUID = UUID()
    var order: Int = 0
    var isAnswerKey: Bool = false
    @Attribute(.externalStorage) var imageData: Data = Data()
    /// Claude's extraction for this page (JSON), saved as soon as it arrives so an interrupted
    /// large chapter resumes without re-reading pages already done.
    var extractionJSON: String?
    /// New pipeline: Claude's reading of this page (JSON of ReadDTO.Page), saved as it arrives.
    var readJSON: String?
    /// The page number printed in the book (read or inferred from neighbours).
    var printedPageNumber: Int?
    var chapter: Chapter?

    init(order: Int, imageData: Data, isAnswerKey: Bool = false) {
        self.order = order
        self.imageData = imageData
        self.isAnswerKey = isAnswerKey
    }
}

@Model
final class Concept {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var bookOrder: Int = 0
    /// Markdown + LaTeX worked example shown after conceptual mistakes.
    var workedExample: String = ""
    var chapter: Chapter?
    @Relationship(inverse: \Question.concept) var questions: [Question] = []

    init(name: String, summary: String, bookOrder: Int, workedExample: String = "") {
        self.name = name
        self.summary = summary
        self.bookOrder = bookOrder
        self.workedExample = workedExample
    }
}

@Model
final class Question {
    var id: UUID = UUID()
    var sourceRaw: String = QuestionSource.book.rawValue
    var statusRaw: String = QuestionStatus.ok.rawValue
    var bookRef: String = ""
    /// Markdown with $...$ / $$...$$ LaTeX.
    var text: String = ""
    @Attribute(.externalStorage) var figureData: Data?
    var pageIndex: Int?
    var difficulty: Int = 1
    var referenceAnswer: String = ""
    var referenceSolution: String = ""
    var answerKeyAnswer: String?
    var estimatedSeconds: Int = 120
    var reviewNote: String?
    var parentEdited: Bool = false
    /// For generated variants: the question it was derived from.
    var parentQuestionID: UUID?
    var createdAt: Date = Date()
    /// Position in the digital chapter (section tree node id; -1 = unknown).
    var sectionID: Int = -1
    /// Exercise number as printed in the book — display only.
    var printedNumber: String = ""
    /// Page number printed in the book.
    var printedPage: Int?
    /// Claude's judgment: answerable completely with a pencil using only what's on the page.
    var pencilOK: Bool = true
    var pencilReason: String = ""
    /// The book marks this as beyond the standard material.
    var isChallenge: Bool = false
    /// Manual include (true) / exclude (false); nil = follow pencilOK.
    var includeOverride: Bool?

    var chapter: Chapter?
    var concept: Concept?
    @Relationship(deleteRule: .cascade, inverse: \Attempt.question) var attempts: [Attempt] = []

    init(text: String, difficulty: Int, source: QuestionSource, bookRef: String = "") {
        self.text = text
        self.difficulty = difficulty
        self.sourceRaw = source.rawValue
        self.bookRef = bookRef
    }

    var source: QuestionSource {
        get { QuestionSource(rawValue: sourceRaw) ?? .book }
        set { sourceRaw = newValue.rawValue }
    }

    var status: QuestionStatus {
        get { QuestionStatus(rawValue: statusRaw) ?? .ok }
        set { statusRaw = newValue.rawValue }
    }

    var isIncluded: Bool { includeOverride ?? pencilOK }
    var isAvailable: Bool { status != .retired && isIncluded }

    var gradedAttempts: [Attempt] {
        attempts.filter { $0.effectiveVerdict != .needsReview }.sorted { $0.startedAt < $1.startedAt }
    }
}

@Model
final class Attempt {
    var id: UUID = UUID()
    var modeRaw: String = AttemptMode.practice.rawValue
    var startedAt: Date = Date()
    var activeSeconds: Double = 0
    @Attribute(.externalStorage) var inkData: Data?
    @Attribute(.externalStorage) var renderedImage: Data?
    var verdictRaw: String = Verdict.needsReview.rawValue
    var mistakeTypeRaw: String?
    var transcribedAnswer: String = ""
    var errorStep: String = ""
    var feedback: String = ""
    var graderConfidence: Double = 0
    /// Claude's full grading reply (JSON), for problem reports.
    var graderLog: String = ""
    /// The student's own correction of the verdict, if any.
    var correctionRaw: String?
    var isGraded: Bool = false
    var examSessionID: UUID?
    /// The grader's own answer (it solves the question before judging hers).
    var ownAnswer: String = ""
    /// Full worked solution, written by the grader when she got it wrong or was stuck.
    var workedSolution: String = ""
    /// Last grading error (network etc.); grading is retried.
    var gradingError: String?
    /// Shown to her at a check-in (or an interruption).
    var revealed: Bool = false
    var wasStuck: Bool = false
    /// The hint she asked for before answering ("" if none). Hinted answers don't move mastery.
    var hintText: String = ""
    /// Voice conversations with the tutor about this answer, in order.
    @Relationship(deleteRule: .cascade, inverse: \TutorTurn.attempt) var tutorTurns: [TutorTurn] = []
    var question: Question?

    init(mode: AttemptMode, startedAt: Date = Date()) {
        self.modeRaw = mode.rawValue
        self.startedAt = startedAt
    }

    var mode: AttemptMode { AttemptMode(rawValue: modeRaw) ?? .practice }

    var verdict: Verdict {
        get { Verdict(rawValue: verdictRaw) ?? .needsReview }
        set { verdictRaw = newValue.rawValue }
    }

    var mistakeType: MistakeType? {
        get { mistakeTypeRaw.flatMap(MistakeType.init(rawValue:)) }
        set { mistakeTypeRaw = newValue?.rawValue }
    }

    var correction: Verdict? {
        get { correctionRaw.flatMap(Verdict.init(rawValue:)) }
        set { correctionRaw = newValue?.rawValue }
    }

    /// Verdict used everywhere: a correction wins over the grader.
    var effectiveVerdict: Verdict { correction ?? verdict }
}

@Model
final class SkillState {
    var id: UUID = UUID()
    var difficulty: Int = 1
    var mastery: Double = 0
    var attemptCount: Int = 0
    /// Most recent results, oldest first (true = correct). Capped.
    var recentResults: [Bool] = []
    /// Most recent correct solve times in seconds. Capped.
    var recentCorrectSeconds: [Double] = []
    var lastPracticed: Date?
    var nextDue: Date?
    var intervalDays: Double = 0
    var careless: Int = 0
    var chapter: Chapter?
    var concept: Concept?

    init(concept: Concept, difficulty: Int) {
        self.concept = concept
        self.difficulty = difficulty
    }
}

@Model
final class ExamSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var finishedAt: Date?
    var timeLimitSeconds: Int = 1800
    var questionIDs: [UUID] = []
    var chapter: Chapter?
    /// The settings she chose (ExamDifficulty, ExamPace) and the time allowed per question (questionIDs order).
    var difficultyRaw: Int = 0
    var paceRaw: Int = 0
    var allowedSeconds: [Double] = []

    init(questionIDs: [UUID], timeLimitSeconds: Int) {
        self.questionIDs = questionIDs
        self.timeLimitSeconds = timeLimitSeconds
    }
}

/// One node of a chapter's section tree.
struct SectionNode: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let level: Int
    let parent: Int
}

/// A piece of the digital chapter, in reading order.
@Model
final class ContentBlock {
    var id: UUID = UUID()
    var order: Int = 0
    /// heading | text | example | figure | exercise
    var kind: String = "text"
    /// Markdown + LaTeX as it should be displayed in the chapter.
    var markdown: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    var pageIndex: Int = 0
    var sectionID: Int = -1
    /// For exercise blocks: the practice question.
    var questionID: UUID?
    var printedNumber: String = ""
    var chapter: Chapter?

    init(order: Int, kind: String, markdown: String, pageIndex: Int, sectionID: Int) {
        self.order = order
        self.kind = kind
        self.markdown = markdown
        self.pageIndex = pageIndex
        self.sectionID = sectionID
    }
}

/// Free-form folder; contains chapters, scopes, and other folders.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = "New folder"
    var createdAt: Date = Date()
    var parent: Folder?
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent) var children: [Folder] = []
    @Relationship(deleteRule: .nullify, inverse: \Chapter.folder) var chapters: [Chapter] = []
    @Relationship(deleteRule: .nullify, inverse: \StudyScope.folder) var scopes: [StudyScope] = []

    init(name: String, parent: Folder? = nil) {
        self.name = name
        self.parent = parent
    }
}

/// A saved selection of material to practice for (a test, a final…). History stays on the chapters.
@Model
final class StudyScope {
    var id: UUID = UUID()
    var name: String = "New scope"
    var createdAt: Date = Date()
    var testDate: Date?
    var examMinutes: Int = 30
    /// Selections: "c|<chapterID>", "s|<chapterID>|<sectionID>", "p|<chapterID>|<from>|<to>".
    var items: [String] = []
    var folder: Folder?
    /// "Teacher's feedback" for this study plan (see Chapter).
    var feedbackHeadline: String = ""
    var feedbackText: String = ""
    var feedbackAtSeconds: Double = -1
    var feedbackDate: Date?

    init(name: String) { self.name = name }
}

/// One turn of a tutor conversation about an answer: what she said (with a picture of her page and pencil
/// marks), or the tutor's reply (its raw SAY/WRITE/POINT script).
@Model
final class TutorTurn {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var fromStudent: Bool = false
    var text: String = ""
    @Attribute(.externalStorage) var snapshot: Data?
    var attempt: Attempt?

    init(fromStudent: Bool, text: String, snapshot: Data? = nil) {
        self.fromStudent = fromStudent
        self.text = text
        self.snapshot = snapshot
    }
}

// MARK: - Lessons

/// One part of a lesson: a unit of teaching (an idea with its worked example(s)), then a "your turn" problem.
struct LessonPart: Codable, Hashable {
    var title: String
    /// Sections whose explanation and examples this part teaches.
    var sectionIDs: [Int]
    /// Sections whose exercises can be used for "your turn" (the part's own sections are used too).
    var practiceSectionIDs: [Int]
    /// A long section can be taught across parts: this part teaches its worked examples fromExample…toExample
    /// (1-based) and the explanation leading up to them. nil = the whole section.
    var fromExample: Int? = nil
    var toExample: Int? = nil
}

/// What the lesson page shows and says for one part (generated when she first reaches it, then saved).
struct LessonPartScript: Codable, Hashable {
    struct Item: Codable, Hashable {
        /// Pointable id, unique in the lesson ("p2e3").
        var id: String
        /// heading | text | example | figure
        var kind: String
        var markdown: String
        /// For figures: the content block whose picture to show.
        var blockID: UUID?
    }
    var items: [Item]
    /// SAY / WRITE / POINT lines, played in order.
    var narration: String
    /// Candidate "your turn" questions, best first (the second is for a retry).
    var questionIDs: [UUID]
}

enum LessonStatus: String, Codable { case notStarted, inProgress, done }

/// A lesson: one logical unit of the chapter (usually a numbered section), taught in parts.
@Model
final class Lesson {
    var id: UUID = UUID()
    var order: Int = 0
    var title: String = ""
    var summary: String = ""
    /// Extra material (not needed for the core of the chapter).
    var optional: Bool = false
    var partsJSON: String = "[]"
    /// Generated scripts by part index: JSON [Int: LessonPartScript].
    var scriptsJSON: String = "{}"
    /// Parts finished so far (resume point).
    var partsDone: Int = 0
    var statusRaw: String = LessonStatus.notStarted.rawValue
    var lastOpened: Date?
    var chapter: Chapter?

    init(order: Int, title: String, summary: String, optional: Bool, parts: [LessonPart]) {
        self.order = order
        self.title = title
        self.summary = summary
        self.optional = optional
        self.parts = parts
    }

    var parts: [LessonPart] {
        get { (try? JSONDecoder().decode([LessonPart].self, from: Data(partsJSON.utf8))) ?? [] }
        set { partsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    var scripts: [Int: LessonPartScript] {
        get { (try? JSONDecoder().decode([Int: LessonPartScript].self, from: Data(scriptsJSON.utf8))) ?? [:] }
        set { scriptsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}" }
    }

    var status: LessonStatus {
        get { LessonStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    /// Every section the lesson touches (teaching and practice).
    var allSectionIDs: [Int] { parts.flatMap { $0.sectionIDs + $0.practiceSectionIDs } }
}

/// Something that keeps "Teacher's feedback": a chapter or a study plan.
@MainActor
protocol FeedbackHolder: AnyObject {
    var id: UUID { get }
    var feedbackHeadline: String { get set }
    var feedbackText: String { get set }
    var feedbackAtSeconds: Double { get set }
    var feedbackDate: Date? { get set }
}
extension Chapter: FeedbackHolder {}
extension StudyScope: FeedbackHolder {}
