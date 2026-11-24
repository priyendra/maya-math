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
    /// Lessons: her question is answered, carry on with the lesson.
    case resume
    /// Lessons: a board line with a blank ("___") she fills in by writing; the answer, and a short spoken why that
    /// says the answer.
    case blank(String, answer: String, why: String)
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
        if line.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ":. ")) == "CONTINUE" { return .resume }
        if let v = value("SAY") { return v.isEmpty ? nil : .say(spoken(v)) }
        if let v = value("WRITE") { return v.isEmpty ? nil : .write(v) }
        if let v = value("BLANK") {
            let parts = v.components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, !parts[1].isEmpty else { return nil }
            var line = parts[0]
            if !line.contains("___") { line += " ___" }
            return .blank(line, answer: parts[1], why: spoken(parts.count > 2 ? parts[2] : ""))
        }
        if let v = value("POINT") {
            let id = v.trimmingCharacters(in: CharacterSet(charactersIn: "[]`* ")).lowercased()
            return .point(id.isEmpty || id == "none" ? nil : id)
        }
        // An untagged line: math goes on the board, anything else is spoken.
        if line.contains("$") && line.filter({ $0 == "$" }).count >= 2 && line.count < 200 { return .write(line) }
        return .say(spoken(line))
    }

    /// Text-to-speech reads symbols badly; the prompt asks for words, this cleans up whatever slips through.
    static let letterNames: [Character: String] = [
        "a": "ay", "b": "bee", "c": "see", "d": "dee", "e": "ee", "f": "eff", "g": "jee", "h": "aitch", "i": "eye",
        "j": "jay", "k": "kay", "l": "el", "m": "em", "n": "en", "o": "oh", "p": "pee", "q": "cue", "r": "ar",
        "s": "ess", "t": "tee", "u": "you", "v": "vee", "w": "double you", "x": "ex", "y": "why", "z": "zee",
    ]

    /// Variable letters said by name: "[a]" → "ay". Also catches an unmarked variable "a" where English never puts
    /// the article (after a number, or before squared/cubed/equals…), so "nine a squared" isn't read "nine uh squared".
    static func nameVariables(_ s: String) -> String {
        var t = s
        for (letter, name) in letterNames {
            t = t.replacingOccurrences(of: "[\(letter)]", with: name)
            t = t.replacingOccurrences(of: "[\(letter.uppercased())]", with: name)
        }
        let numbers = "\\d|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|forty|fifty|hundred"
        t = t.replacingOccurrences(of: "(?i)(\\b(?:\(numbers)))\\s+a\\b", with: "$1 ay", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\ba(?=\\s+(?:squared|cubed|equals|plus|minus|times|over|to the|and b\\b))",
                                   with: "ay", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?<=\\b(?:plus|minus|times|over|equals)\\s)a\\b(?!\\s+(?:lot|few|bit|little|number|term|factor|perfect|difference|sum|product)\\b)",
                                   with: "ay", options: .regularExpression)
        return t
    }

    static func spoken(_ s: String) -> String {
        var t = nameVariables(s)
        // Fractions first: "\frac{3}{4}" → "3 over 4" (not "3 4").
        t = t.replacingOccurrences(of: "\\\\[dt]?frac\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}", with: " $1 over $2 ", options: .regularExpression)
        // Longer commands before their prefixes (\neq before \ne, \leq before \le).
        for (a, b) in [("\\cdot", " times "), ("\\times", " times "), ("\\div", " divided by "), ("\\sqrt", " the square root of "),
                       ("^{2}", " squared"), ("^{3}", " cubed"), ("^2", " squared"), ("^3", " cubed"),
                       ("\\pm", " plus or minus "), ("\\neq", " is not equal to "), ("\\ne", " is not equal to "),
                       ("\\leq", " is less than or equal to "), ("\\geq", " is greater than or equal to "),
                       ("\\le", " is less than or equal to "), ("\\ge", " is greater than or equal to "),
                       ("\\approx", " is about "), ("\\pi", " pi "), ("\\%", " percent"), ("\\$", " dollars ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.replacingOccurrences(of: "\\^\\{?([0-9a-zA-Z]+)\\}?", with: " to the power of $1", options: .regularExpression)
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

/// A fill-in-the-blank board line split around its blank, each side valid Markdown + $LaTeX$ on its own.
enum BlankLine {
    /// The math before and after the blank. A blank inside a formula ("$= x^2 - ___$") closes the formula before it
    /// and reopens it after, so neither side shows raw LaTeX.
    static func pieces(_ line: String) -> (before: String, after: String) {
        let parts = line.components(separatedBy: "___")
        var before = parts[0]
        var after = parts.dropFirst().joined(separator: " ")
        if dollars(before) % 2 == 1 {
            before = before.trimmingCharacters(in: .whitespaces) + "$"
            after = "$" + after.trimmingCharacters(in: .whitespaces)
            if after.trimmingCharacters(in: CharacterSet(charactersIn: "$ ")).isEmpty { after = "" }
        }
        let clean = { (s: String) in s.replacingOccurrences(of: "$$", with: "").trimmingCharacters(in: .whitespaces) }
        return (clean(before), clean(after))
    }

    /// The answer as it is shown: math typeset as math ("9", "x^2", "\frac{1}{2}"), words as words ("per").
    static func answerMarkdown(_ answer: String) -> String {
        let a = answer.trimmingCharacters(in: .whitespaces)
        if a.contains("$") { return a }
        let words = a.split(separator: " ").count > 1 || (a.count > 1 && a.allSatisfy(\.isLetter))
        return words ? a : "$\(a)$"
    }

    /// Unescaped dollar signs.
    private static func dollars(_ s: String) -> Int {
        var n = 0, prev: Character = " "
        for c in s { if c == "$" && prev != "\\" { n += 1 }; prev = c }
        return n
    }
}
