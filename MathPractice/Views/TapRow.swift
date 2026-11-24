import SwiftUI

/// A whole row that is clearly tappable: highlights while pressed (rows in a list or grid that open a page).
struct TapRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// The "opens a page" mark at the end of a tappable row.
struct GoChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.accentColor.opacity(0.12)))
    }
}
