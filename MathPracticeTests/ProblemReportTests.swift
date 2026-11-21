import XCTest
import SwiftData
@testable import MathPractice

@MainActor
final class ProblemReportTests: XCTestCase {
    func testBuildsZipForEachKind() throws {
        let container = try ModelContainer(
            for: Chapter.self, PageImage.self, Concept.self, Question.self, Attempt.self, SkillState.self, ExamSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let chapter = Chapter(title: "Test")
        context.insert(chapter)
        let page = PageImage(order: 0, imageData: Data([0xFF, 0xD8, 0xFF]))
        page.chapter = chapter
        context.insert(page)
        let q = Question(text: "Solve $x+1=2$.", difficulty: 1, source: .book, bookRef: "1.1 #1")
        q.referenceAnswer = "x = 1"
        q.pageIndex = 0
        q.chapter = chapter
        context.insert(q)
        let a = Attempt(mode: .practice)
        a.question = q
        a.renderedImage = Data([0x89, 0x50, 0x4E, 0x47])
        a.graderLog = #"{"pass1":{"verdict":"incorrect"}}"#
        context.insert(a)
        try context.save()

        for subject: ProblemReport.Subject in [.question(q), .attempt(a), .chapter(chapter)] {
            let url = try ProblemReport.build(subject, note: "marked wrong but correct")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(url.pathExtension, "zip")
            XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "not a zip: \(url.lastPathComponent)") // "PK"
            try? FileManager.default.removeItem(at: url)
        }
    }
}
