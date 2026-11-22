import SwiftUI
import SwiftData

@main
struct MathPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            Themed {
                if let v = CanvasLab.requested { CanvasLab(variant: v) }
                else if ProcessInfo.processInfo.arguments.contains("-checkInLab") { SeededCheckInLab() }
                else { LibraryView() }
            }
            #else
            Themed { LibraryView() }
            #endif
        }
        .modelContainer(for: [Chapter.self, PageImage.self, Concept.self, Question.self, Attempt.self,
                              SkillState.self, ExamSession.self, ContentBlock.self, Folder.self, StudyScope.self, TutorTurn.self, Lesson.self])
    }
}
