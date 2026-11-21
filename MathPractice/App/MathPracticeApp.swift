import SwiftUI
import SwiftData

@main
struct MathPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            ChapterListView()
        }
        .modelContainer(for: [Chapter.self, PageImage.self, Concept.self, Question.self,
                              Attempt.self, SkillState.self, ExamSession.self])
    }
}
