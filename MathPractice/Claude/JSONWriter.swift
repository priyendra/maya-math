import Foundation

/// A JSON object whose keys keep their insertion order. Structured outputs generate fields in schema order,
/// so ordering lets us make Claude e.g. solve a question before judging the student's answer.
struct OrderedObject {
    var pairs: [(String, Any)]
    subscript(key: String) -> Any? { pairs.first { $0.0 == key }?.1 }
}

/// Minimal JSON serializer that supports `OrderedObject` (plain dictionaries are written with sorted keys,
/// which also keeps request prefixes byte-stable for caching).
enum JSONWriter {
    static func data(_ value: Any) -> Data { Data(string(value).utf8) }

    static func string(_ value: Any) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: Any, into out: inout String) {
        switch value {
        case let o as OrderedObject:
            out += "{"
            for (i, (k, v)) in o.pairs.enumerated() {
                if i > 0 { out += "," }
                writeString(k, into: &out); out += ":"; write(v, into: &out)
            }
            out += "}"
        case let d as [String: Any]:
            out += "{"
            for (i, k) in d.keys.sorted().enumerated() {
                if i > 0 { out += "," }
                writeString(k, into: &out); out += ":"; write(d[k]!, into: &out)
            }
            out += "}"
        case let a as [Any]:
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                write(v, into: &out)
            }
            out += "]"
        case let s as String: writeString(s, into: &out)
        case let b as Bool: out += b ? "true" : "false"
        case let i as Int: out += String(i)
        case let d as Double: out += d.isFinite ? String(d) : "0"
        case is NSNull: out += "null"
        default: writeString(String(describing: value), into: &out)
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) }
                else { out.unicodeScalars.append(scalar) }
            }
        }
        out += "\""
    }
}
