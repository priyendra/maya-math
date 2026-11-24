import Foundation

/// Small number formats shared by progress views.
enum Fmt {
    static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    static func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) m"
    }
}
