import Foundation

/// Short labels (skill names, section and lesson titles) may contain $...$ LaTeX. Rendering each with KaTeX is too
/// heavy for lists and grids, so simple math is turned into Unicode instead: "$x^2 + bx + c$" → "𝑥² + 𝑏𝑥 + 𝑐".
enum MathPlain {
    static func render(_ s: String) -> String {
        var out = ""
        var math = ""
        var inMath = false
        var chars = Array(s)
        // A display "$$" counts as a single delimiter here.
        chars = Array(String(chars).replacingOccurrences(of: "$$", with: "$"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "$" {
                (inMath ? { math.append("$") } : { out.append("$") })()
                i += 2
                continue
            }
            if c == "$" {
                if inMath { out += spaced(convert(math)); math = "" }
                inMath.toggle()
            } else if inMath {
                math.append(c)
            } else {
                out.append(c)
            }
            i += 1
        }
        if inMath { out += "$" + math }   // unbalanced: leave as typed
        return out
    }

    /// Longer commands first (\left before \le, \cdots before \cdot).
    private static let symbols: [(String, String)] = [
        ("\\left", ""), ("\\right", ""), ("\\cdots", "⋯"), ("\\ldots", "…"), ("\\dots", "…"), ("\\quad", " "),
        ("\\cdot", "·"), ("\\times", "×"), ("\\div", "÷"), ("\\pm", "±"), ("\\mp", "∓"),
        ("\\leq", "≤"), ("\\geq", "≥"), ("\\le", "≤"), ("\\ge", "≥"), ("\\neq", "≠"), ("\\ne", "≠"),
        ("\\approx", "≈"), ("\\infty", "∞"), ("\\pi", "π"), ("\\theta", "θ"), ("\\alpha", "α"), ("\\beta", "β"),
        ("\\Delta", "Δ"), ("\\rightarrow", "→"), ("\\to", "→"),
        ("\\%", "%"), ("\\,", " "), ("\\;", " "), ("\\!", ""),
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "m": "ᵐ", "k": "ᵏ",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "n": "ₙ", "i": "ᵢ", "x": "ₓ", "k": "ₖ",
    ]

    /// Math italic letters (h has its own code point).
    private static func italic(_ c: Character) -> String {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return String(c) }
        if c == "h" { return "ℎ" }
        if (97...122).contains(v), let u = UnicodeScalar(0x1D44E + v - 97) { return String(Character(u)) }
        if (65...90).contains(v), let u = UnicodeScalar(0x1D434 + v - 65) { return String(Character(u)) }
        return String(c)
    }

    /// One {group} or single character starting at i; returns its content and the index after it.
    private static func group(_ a: [Character], _ i: Int) -> (String, Int) {
        guard i < a.count else { return ("", i) }
        guard a[i] == "{" else { return (String(a[i]), i + 1) }
        var depth = 0, j = i
        while j < a.count {
            if a[j] == "{" { depth += 1 }
            if a[j] == "}" { depth -= 1; if depth == 0 { break } }
            j += 1
        }
        return (String(a[(i + 1)..<min(j, a.count)]), min(j + 1, a.count))
    }

    /// Spaces around relations (=, <, ≤ …) and around + and − between terms at the top level, as typeset math
    /// does: "3𝑥²−41𝑥=−60" → "3𝑥² − 41𝑥 = −60". Inside brackets stays compact: "(𝑎+𝑏)".
    static func spaced(_ s: String) -> String {
        let relations: Set<Character> = ["=", "<", ">", "≤", "≥", "≠", "≈"]
        var out = ""
        var depth = 0
        for c in s {
            if "([".contains(c) { depth += 1 }
            if ")]".contains(c) { depth = max(0, depth - 1) }
            let prev = out.last(where: { $0 != " " })
            let binary = (c == "+" || c == "−") && depth == 0 && prev != nil
                && !relations.contains(prev!) && !"+−·×÷±(,".contains(prev!)
            if relations.contains(c) || binary {
                while out.last == " " { out.removeLast() }
                out += " \(c) "
            } else if c == " " && out.last == " " {
                continue
            } else {
                out.append(c)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func convert(_ tex: String) -> String {
        var t = tex
        for (k, v) in symbols { t = t.replacingOccurrences(of: k, with: v) }
        // \text{…}, \mathrm{…}: words, kept upright.
        t = t.replacingOccurrences(of: "\\\\(?:text|mathrm|textbf|mathbf|operatorname)\\{([^{}]*)\\}", with: "\u{1}$1\u{2}",
                                   options: .regularExpression)
        let a = Array(t)
        var out = ""
        var upright = false
        var i = 0
        func needsParens(_ s: String) -> Bool { s.count > 1 && s.contains { "+-−·×/ ".contains($0) } }
        while i < a.count {
            let c = a[i]
            switch c {
            case "\u{1}": upright = true; i += 1
            case "\u{2}": upright = false; i += 1
            case "^", "_":
                let (g, next) = group(a, i + 1)
                let inner = convert(g)
                let table = c == "^" ? superscripts : subscripts
                let mapped = g.map { table[$0] }
                if mapped.allSatisfy({ $0 != nil }) && !g.isEmpty {
                    out += String(mapped.compactMap { $0 })
                } else {
                    out += String(c) + (needsParens(inner) ? "(\(inner))" : inner)
                }
                i = next
            case "\\":
                var j = i + 1
                while j < a.count, a[j].isLetter { j += 1 }
                let name = String(a[(i + 1)..<j])
                if name == "frac" || name == "dfrac" || name == "tfrac" {
                    let (n, k) = group(a, j)
                    let (d, k2) = group(a, k)
                    let num = convert(n), den = convert(d)
                    out += (needsParens(num) ? "(\(num))" : num) + "/" + (needsParens(den) ? "(\(den))" : den)
                    i = k2
                } else if name == "sqrt" {
                    let (g, k) = group(a, j)
                    let inner = convert(g)
                    out += "√" + (inner.count > 1 ? "(\(inner))" : inner)
                    i = k
                } else {
                    i = max(j, i + 1)   // unknown command: dropped
                }
            case "{", "}":
                i += 1
            case "-":
                out += "−"; i += 1
            default:
                out += upright ? String(c) : italic(c)
                i += 1
            }
        }
        return out
    }
}

import SwiftUI

/// Markdown with math as native text (Unicode math, no web view): for lists, where many web views would make
/// scrolling stutter. Full typesetting (MathText) is for single-item pages.
struct MathPlainText: View {
    let markdown: String

    var body: some View {
        Text(Self.attributed(markdown))
    }

    static func attributed(_ markdown: String) -> AttributedString {
        let plain = MathPlain.render(markdown)
        return (try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(plain)
    }
}
