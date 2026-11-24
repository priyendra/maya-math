import SwiftUI
import UIKit

/// The app's visual design: type, colours with fixed meanings, surfaces. Views read it from the environment.
struct Theme {
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
    /// Big buttons and covers use gradients.
    let gradients: Bool

    // Colours with one meaning each.
    let learn: Color        // the tutor, lessons, explanations
    let done: Color         // correct, finished, your turn
    let attention: Color    // needs attention, worked examples
    let notQuite: Color     // a wrong answer (kind, not alarming)
    let board: Color        // the tutor's board

    /// Skill mastery colours: not tried, weak, getting there, nearly, mastered.
    func skillColor(_ stage: SkillStage) -> Color {
        switch stage {
        case .new: return learn.opacity(0.14)
        case .learning: return notQuite
        case .gettingThere: return attention
        case .almost: return Color(red: 1, green: 0.86, blue: 0.35)
        case .mastered: return done
        }
    }

    /// Dots and icons drawn on a skill colour.
    func skillInk(_ stage: SkillStage) -> Color { stage == .almost ? .black.opacity(0.75) : .white }

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
        design: .default, accent: .blue, accent2: .indigo,
        background: Color(uiColor: .systemGroupedBackground), surface: Color(uiColor: .secondarySystemGroupedBackground),
        border: nil, radius: 14, shadow: false, gradients: false,
        learn: .blue, done: .green, attention: .orange, notQuite: rgb(0xE5484D), board: .indigo)

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

/// Applies the design to everything below it.
struct Themed<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let t = Theme.classic
        let _ = t.applyNavigationBar()
        content
            .environment(\.theme, t)
            .tint(t.accent)
            .fontDesign(t.design)
    }
}
