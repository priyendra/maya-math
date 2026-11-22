import SwiftUI
import UIKit

/// The app's visual design: type, colours with fixed meanings, surfaces. Several designs can be tried from Settings
/// (Design); views read the current one from the environment.
struct Theme: Identifiable, Equatable {
    let id: Int
    let name: String
    let tagline: String
    /// Font design for the whole app (rounded / serif / default).
    let design: Font.Design
    let accent: Color
    /// A second brand colour (secondary big button, highlights).
    let accent2: Color
    let background: Color
    let surface: Color
    /// Outline for cards (nil = none).
    let border: Color?
    let radius: CGFloat
    let shadow: Bool
    /// Library shows chapters as a grid of cards (else a list of rows).
    let libraryGrid: Bool
    /// Big buttons and covers use gradients.
    let gradients: Bool

    // Colours with one meaning each.
    let learn: Color        // the tutor, lessons, explanations
    let done: Color         // correct, finished, your turn
    let attention: Color    // needs attention, worked examples
    let notQuite: Color     // a wrong answer (kind, not alarming)
    let board: Color        // the tutor's board

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }

    /// Skill mastery colours: not tried, weak, getting there, nearly, mastered.
    func skillColor(_ mastery: Double, attempted: Bool) -> Color {
        guard attempted else { return learn.opacity(0.14) }
        switch mastery {
        case ..<0.3: return notQuite
        case ..<0.6: return attention
        case ..<0.8: return Color(red: 1, green: 0.86, blue: 0.35)
        default: return done
        }
    }

    // MARK: Type scale (six roles)

    func font(_ role: TypeRole) -> Font {
        switch role {
        case .pageTitle: return .system(size: 34, weight: .bold, design: design)
        case .section: return .system(size: 22, weight: .bold, design: design)
        case .cardTitle: return .system(size: 19, weight: .semibold, design: design)
        case .body: return .system(size: 17, weight: .regular, design: design)
        case .label: return .system(size: 15, weight: .medium, design: design)
        case .caption: return .system(size: 13, weight: .regular, design: design)
        }
    }

    enum TypeRole { case pageTitle, section, cardTitle, body, label, caption }

    /// A filled background for a big button (gradient or flat).
    func fill(_ c: Color) -> AnyShapeStyle { gradients ? AnyShapeStyle(c.gradient) : AnyShapeStyle(c) }

    // MARK: The designs

    private static func rgb(_ hex: UInt32, dark: UInt32? = nil) -> Color {
        func ui(_ h: UInt32) -> UIColor {
            UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        let light = ui(hex), darkC = dark.map(ui) ?? light
        return Color(UIColor { $0.userInterfaceStyle == .dark ? darkC : light })
    }

    static let classic = Theme(
        id: 0, name: "Classic", tagline: "Clean and familiar, like Apple's own apps",
        design: .default, accent: .blue, accent2: .indigo,
        background: Color(uiColor: .systemGroupedBackground), surface: Color(uiColor: .secondarySystemGroupedBackground),
        border: nil, radius: 14, shadow: false, libraryGrid: false, gradients: false,
        learn: .blue, done: .green, attention: .orange, notQuite: rgb(0xE5484D), board: .indigo)

    static let playful = Theme(
        id: 1, name: "Playful", tagline: "Rounded letters, warm colours, big friendly cards",
        design: .rounded, accent: rgb(0xFF6B4A), accent2: rgb(0x14A3A3),
        background: rgb(0xFFF7EC, dark: 0x1D1914), surface: rgb(0xFFFFFF, dark: 0x2A241D),
        border: nil, radius: 24, shadow: true, libraryGrid: true, gradients: false,
        learn: rgb(0x14A3A3), done: rgb(0x2FB36B), attention: rgb(0xF5A524), notQuite: rgb(0xE8708A), board: rgb(0x8B6CEF))

    static let notebook = Theme(
        id: 2, name: "Notebook", tagline: "Calm and studious: paper, ink and a serif type",
        design: .serif, accent: rgb(0x2F4B8C, dark: 0x8FA8E6), accent2: rgb(0x7A5C3E, dark: 0xC9A37E),
        background: rgb(0xFBF8F1, dark: 0x1A1916), surface: rgb(0xFFFEFA, dark: 0x24221E),
        border: rgb(0xD9D2C3, dark: 0x3C3832), radius: 10, shadow: false, libraryGrid: false, gradients: false,
        learn: rgb(0x2F4B8C, dark: 0x8FA8E6), done: rgb(0x3E8E5A), attention: rgb(0xC0812B), notQuite: rgb(0xB5524C), board: rgb(0x6B4FA0, dark: 0xA990D6))

    static let bold = Theme(
        id: 3, name: "Bold", tagline: "Vivid and energetic, with colourful gradient cards",
        design: .rounded, accent: rgb(0x5B4BE8, dark: 0x8C80FF), accent2: rgb(0xFF4F8B),
        background: rgb(0xF3F2FA, dark: 0x121120), surface: rgb(0xFFFFFF, dark: 0x1E1C33),
        border: nil, radius: 20, shadow: true, libraryGrid: true, gradients: true,
        learn: rgb(0x5B4BE8, dark: 0x8C80FF), done: rgb(0x18B57A), attention: rgb(0xFF9F1C), notQuite: rgb(0xFF4F8B), board: rgb(0x7B61FF))

    static let all = [classic, playful, notebook, bold]

    /// Chosen in Settings (or `-design N` for screenshots).
    static var currentID: Int {
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-design"),
           ProcessInfo.processInfo.arguments.indices.contains(i + 1), let n = Int(ProcessInfo.processInfo.arguments[i + 1]) { return n }
        return UserDefaults.standard.integer(forKey: "designOption")
    }

    /// Navigation bar titles in the theme's font design.
    func applyNavigationBar() {
        let a = UINavigationBarAppearance()
        a.configureWithTransparentBackground()
        func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let d: UIFontDescriptor.SystemDesign = design == .rounded ? .rounded : design == .serif ? .serif : .default
            return base.fontDescriptor.withDesign(d).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        a.largeTitleTextAttributes = [.font: font(34, .bold)]
        a.titleTextAttributes = [.font: font(17, .semibold)]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.largeTitleTextAttributes = a.largeTitleTextAttributes
        scrolled.titleTextAttributes = a.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = a
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.classic }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// The theme's card surface: fill, corner radius, optional outline and shadow.
    func card(_ t: Theme, tint: Color? = nil, radius: CGFloat? = nil) -> some View {
        let r = radius ?? t.radius
        return background {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(tint.map { AnyShapeStyle($0.opacity(0.10)) } ?? AnyShapeStyle(t.surface))
                .overlay {
                    if let b = t.border { RoundedRectangle(cornerRadius: r, style: .continuous).stroke(tint?.opacity(0.4) ?? b, lineWidth: 1) }
                }
                .shadow(color: t.shadow && tint == nil ? .black.opacity(0.07) : .clear, radius: 10, x: 0, y: 4)
        }
    }

    /// A screen's background in the theme.
    func themedBackground(_ t: Theme) -> some View {
        background(t.background.ignoresSafeArea())
    }
}

/// Applies the chosen design to everything below it.
struct Themed<Content: View>: View {
    @AppStorage("designOption") private var stored = 0
    @ViewBuilder let content: Content

    var body: some View {
        let id = ProcessInfo.processInfo.arguments.contains("-design") ? Theme.currentID : stored
        let t = Theme.all.indices.contains(id) ? Theme.all[id] : .classic
        // Set before the views below are (re)built, so new navigation bars pick it up.
        let _ = t.applyNavigationBar()
        content
            .environment(\.theme, t)
            .tint(t.accent)
            .fontDesign(t.design)
            .id(t.id)   // rebuild everything in the new design
    }
}
