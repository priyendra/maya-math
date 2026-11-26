import XCTest
import SwiftData
@testable import MathPractice

final class ScopeSelectionTests: XCTestCase {
    // Unit 0 → lessons 1, 2 → exercise sets 3, 4 (under lesson 1); unit 5 with no parts.
    let nodes = [
        SectionNode(id: 0, title: "Unit A", level: 1, parent: -1),
        SectionNode(id: 1, title: "Lesson 1", level: 2, parent: 0),
        SectionNode(id: 2, title: "Lesson 2", level: 2, parent: 0),
        SectionNode(id: 3, title: "Oral", level: 3, parent: 1),
        SectionNode(id: 4, title: "Written", level: 3, parent: 1),
        SectionNode(id: 5, title: "Unit B", level: 1, parent: -1),
    ]
    func sel(_ items: Set<String> = []) -> ScopeSelection { ScopeSelection(chapterID: "C", nodes: nodes, items: items) }

    func testTickingASectionCoversEverythingUnderIt() {
        var s = sel()
        s.toggle(nodes[0])
        XCTAssertEqual(s.items, ["s|C|0"])
        XCTAssertEqual(s.mark(nodes[3]), .all)
        XCTAssertEqual(s.chapterMark, .some)
        XCTAssertEqual(s.summary, "Unit A")
    }

    func testUntickingOnePartKeepsSiblingsAndTheSectionsOwnQuestions() {
        var s = sel(["s|C|0"])
        s.toggle(nodes[3])
        XCTAssertEqual(s.items, ["n|C|0", "n|C|1", "s|C|2", "s|C|4"])
        XCTAssertEqual(s.mark(nodes[0]), .some)
        XCTAssertEqual(s.mark(nodes[1]), .some)
        XCTAssertEqual(s.mark(nodes[3]), .none)
        XCTAssertEqual(s.mark(nodes[4]), .all)
    }

    func testTickingItBackRestoresTheSection() {
        var s = sel(["s|C|0"])
        s.toggle(nodes[3])
        s.toggle(nodes[3])
        XCTAssertEqual(s.items, ["s|C|0"])
    }

    func testTickingEveryPartMeansTheWhole() {
        var s = sel()
        s.toggle(nodes[3]); s.toggle(nodes[4])
        XCTAssertEqual(s.items, ["s|C|1"])
        s.toggle(nodes[2])
        XCTAssertEqual(s.items, ["s|C|0"])
        s.toggle(nodes[5])
        XCTAssertEqual(s.items, ["c|C"])
    }

    func testUntickingFromTheWholeChapterKeepsTheRest() {
        var s = sel(["c|C"])
        s.toggle(nodes[5])
        XCTAssertEqual(s.items, ["n|C|-1", "s|C|0"])
        XCTAssertEqual(s.chapterMark, .some)
        XCTAssertEqual(s.summary, "Unit A")
    }

    func testOtherChaptersAndPageRangesAreUntouched() {
        var s = sel(["c|C", "p|C|10|12", "c|D"])
        s.toggleChapter()
        XCTAssertEqual(s.items, ["p|C|10|12", "c|D"])
        XCTAssertEqual(s.summary, "Pages 10–12")
    }
}

@MainActor
final class ScopePlanQuestionsTests: XCTestCase {
    /// A section's own questions come in with "n|", without its subsections' questions; "s|" brings in everything under it.
    func testOwnQuestionsItemTakesOnlyTheSectionsOwnQuestions() throws {
        let container = try ModelContainer(
            for: Chapter.self, PageImage.self, Concept.self, Question.self, Attempt.self, SkillState.self, ExamSession.self,
                StudyScope.self, Folder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let chapter = Chapter(title: "Test")
        chapter.outline = [SectionNode(id: 0, title: "Lesson", level: 1, parent: -1),
                           SectionNode(id: 1, title: "Exercises", level: 2, parent: 0)]
        context.insert(chapter)
        func question(_ text: String, section: Int) -> Question {
            let q = Question(text: text, difficulty: 1, source: .book)
            q.sectionID = section
            q.chapter = chapter
            context.insert(q)
            return q
        }
        let onLesson = question("on the lesson", section: 0)
        let inExercises = question("in its exercises", section: 1)
        try context.save()

        let plan = StudyScope(name: "Plan")
        context.insert(plan)
        let id = chapter.id.uuidString
        plan.items = ["n|\(id)|0"]
        XCTAssertEqual(StudySet.scope(plan, chapters: [chapter]).questions.map(\.id), [onLesson.id])
        plan.items = ["s|\(id)|0"]
        XCTAssertEqual(Set(StudySet.scope(plan, chapters: [chapter]).questions.map(\.id)), [onLesson.id, inExercises.id])
    }
}
