import Foundation

/// Work in progress that must survive the app closing: the ink on the current practice question, and every answer of a
/// running exam. Saved as small files under Application Support/Drafts, one per practice set or exam.
struct Draft: Codable, Equatable {
    var questionIDs: [UUID] = []
    /// Ink (PKDrawing data) per question.
    var ink: [UUID: Data] = [:]
    /// Time spent so far per question.
    var seconds: [UUID: Double] = [:]
    /// The question she was on.
    var index = 0
    var savedAt = Date()
}

enum DraftStore {
    /// A practice draft older than this is stale (she has moved on).
    static let practiceMaxAge: TimeInterval = 12 * 3600

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Drafts", isDirectory: true)
    }

    static func url(_ key: String) -> URL { folder.appendingPathComponent("\(key).json") }

    static func save(_ draft: Draft, key: String) {
        guard !key.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var d = draft
        d.savedAt = Date()
        if let data = try? JSONEncoder().encode(d) { try? data.write(to: url(key), options: .atomic) }
    }

    static func load(_ key: String) -> Draft? {
        guard !key.isEmpty, let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    static func clear(_ key: String) {
        try? FileManager.default.removeItem(at: url(key))
    }

    static func practiceKey(_ setKey: String) -> String { "practice-\(setKey)" }
    static func examKey(_ examID: UUID) -> String { "exam-\(examID)" }
}
