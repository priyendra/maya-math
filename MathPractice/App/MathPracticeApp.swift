import SwiftUI
import SwiftData

@main
struct MathPracticeApp: App {
    init() {
        #if DEBUG
        // UI tests start from an empty app: no data or settings left over from an earlier test.
        if ProcessInfo.processInfo.arguments.contains("-freshStore") {
            let dir = URL.applicationSupportDirectory
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        }
        #endif
    }

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
