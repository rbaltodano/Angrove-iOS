import SwiftUI

extension AngroveTheme {
    /// The SF Symbol size scale. Feature code picks a step instead of a point size.
    enum IconSize: CGFloat, CaseIterable {
        case micro = 8
        case xSmall = 10
        case small = 12
        case medium = 14
        case large = 16
        case xLarge = 18
        case xxLarge = 20
        case display = 24
        case hero = 28
        case feature = 42
    }

    /// SF Symbol weights by role.
    enum IconWeight {
        /// Sidebar, navigation and chrome icons that sit beside quiet labels.
        case navigation
        /// In-content controls and status icons; the default.
        case standard
        /// Small glyphs (10pt and under) that need extra ink to stay legible.
        case strong

        var fontWeight: Font.Weight {
            switch self {
            case .navigation: .medium
            case .standard: .semibold
            case .strong: .bold
            }
        }
    }
}

extension View {
    /// Sizes an SF Symbol on the shared icon scale.
    func angroveIcon(_ size: AngroveTheme.IconSize, _ weight: AngroveTheme.IconWeight = .standard) -> some View {
        font(.system(size: size.rawValue, weight: weight.fontWeight))
    }

    /// Sizes an SF Symbol that must track a text size (for example the response font size).
    /// Use the scale overload everywhere else.
    func angroveIcon(textRelativeSize size: CGFloat, _ weight: AngroveTheme.IconWeight = .standard) -> some View {
        font(.system(size: size, weight: weight.fontWeight))
    }
}
