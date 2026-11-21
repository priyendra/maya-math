import Foundation

/// One step of a tutor reply. Replies are plain tagged lines (SAY / WRITE / POINT) so they can be acted on while
/// still streaming: the voice starts on the first finished line.
enum TutorBeat: Equatable {
    /// Spoken out loud.
    case say(String)
    /// A line of Markdown + $LaTeX$ added to the board at the bottom of the page.
    case write(String)
    /// Move the cursor to a page part ("s2", "wrong", "b1"…); nil hides it.
    case point(String?)
}

/// Turns streamed reply text into beats, one finished line at a time.
struct TutorScriptParser {
    private var buffer = ""

    mutating func feed(_ chunk: String) -> [TutorBeat] {
        buffer += chunk
        var beats: [TutorBeat] = []
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<nl])
            buffer.removeSubrange(...nl)
            if let b = Self.beat(line) { beats.append(b) }
        }
        return beats
    }

    mutating func finish() -> [TutorBeat] {
        defer { buffer = "" }
        return Self.beat(buffer).map { [$0] } ?? []
    }

    static func beat(_ raw: String) -> TutorBeat? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        func value(_ tag: String) -> String? {
            guard line.uppercased().hasPrefix(tag + ":") else { return nil }
            return line.dropFirst(tag.count + 1).trimmingCharacters(in: .whitespaces)
        }
        if let v = value("SAY") { return v.isEmpty ? nil : .say(spoken(v)) }
        if let v = value("WRITE") { return v.isEmpty ? nil : .write(v) }
        if let v = value("POINT") {
            let id = v.trimmingCharacters(in: CharacterSet(charactersIn: "[]`* ")).lowercased()
            return .point(id.isEmpty || id == "none" ? nil : id)
        }
        // An untagged line: math goes on the board, anything else is spoken.
        if line.contains("$") && line.filter({ $0 == "$" }).count >= 2 && line.count < 200 { return .write(line) }
        return .say(spoken(line))
    }

    /// Text-to-speech reads symbols badly; the prompt asks for words, this cleans up whatever slips through.
    static func spoken(_ s: String) -> String {
        var t = s
        for (a, b) in [("\\cdot", " times "), ("\\times", " times "), ("\\sqrt", " the square root of "),
                       ("^2", " squared"), ("^3", " cubed"), ("\\pm", " plus or minus "), ("\\ne", " is not equal to ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.replacingOccurrences(of: "\\\\[a-zA-Z]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "[$*_`{}\\\\]", with: "", options: .regularExpression)
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// Splits a worked solution into steps the tutor can point at. Numbered items start a new step; other lines
    /// (continuations, display math) stay with the step they follow.
    static func steps(_ solution: String) -> [String] {
        var steps: [String] = []
        var afterBlank = true
        for line in solution.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { afterBlank = true; continue }
            let numbered = line.range(of: "^\\s*\\d+[.)]\\s", options: .regularExpression) != nil
            if numbered || afterBlank || steps.isEmpty { steps.append(line) } else { steps[steps.count - 1] += "\n" + line }
            afterBlank = false
        }
        return steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
