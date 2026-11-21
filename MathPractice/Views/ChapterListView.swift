import SwiftUI
import SwiftData

struct ChapterListView: View {
    @Query(sort: \Chapter.createdAt, order: .reverse) private var chapters: [Chapter]

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Text(chapter.title)
            }
            .navigationTitle("Chapters")
        }
    }
}
