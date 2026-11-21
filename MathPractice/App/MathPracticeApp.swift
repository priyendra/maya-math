import SwiftUI
import SwiftData

@main
struct MathPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: [Chapter.self, PageImage.self, Concept.self, Question.self, Attempt.self,
                              SkillState.self, ExamSession.self, ContentBlock.self, Folder.self, StudyScope.self])
    }
}
