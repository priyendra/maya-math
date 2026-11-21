import Foundation

/// Append-only log of every Claude call (JSON lines in Application Support/claude_calls.jsonl), for
/// evaluating and improving the app. Readable over the cable and included in data exports.
enum CallLog {
    static let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("claude_calls.jsonl")
    }

    private static let queue = DispatchQueue(label: "CallLog")

    static func record(kind: String, model: String, effort: String, started: Date, retries: Int,
                       usage: [String: Int], error: String?, response: String?) {
        var entry: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: started),
            "kind": kind, "model": model, "effort": effort, "prompt_version": Prompts.version,
            "app_version": appVersion, "seconds": (Date().timeIntervalSince(started) * 10).rounded() / 10,
            "retries": retries, "usage": usage,
        ]
        if let error { entry["error"] = error }
        if let response { entry["response"] = response }
        let line = JSONWriter.string(entry) + "\n"
        queue.async {
            let u = url
            if let handle = try? FileHandle(forWritingTo: u) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: u)
            }
        }
    }
}
