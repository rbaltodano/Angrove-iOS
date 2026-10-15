import SwiftUI

extension View {
    /// Desktop help is rendered by the dock host, above its clipped controls pill.
    func modelControlHoverLabel(_ title: String, shortcut: String? = nil) -> some View {
        modifier(MacModelControlHoverSource(title: title, shortcut: shortcut))
    }

    func modelControlHoverPill() -> some View {
        transformAnchorPreference(key: MacModelControlHoverKey.self, value: .bounds) { value, anchor in
            value.pill = anchor
        }
    }

    func modelControlHoverOverlay(isVisible: Bool) -> some View {
        overlayPreferenceValue(MacModelControlHoverKey.self) {
            MacModelControlHoverOverlay(preference: isVisible ? $0 : .init())
        }
    }
}

struct MacModelControlHelp: Hashable {
    let title: String
    let shortcut: String?
}

struct MacModelControlHoverPreference {
    var help: MacModelControlHelp?
    var button: Anchor<CGRect>?
    var pill: Anchor<CGRect>?
}

struct MacModelControlHoverKey: PreferenceKey {
    static let defaultValue = MacModelControlHoverPreference()

    static func reduce(value: inout MacModelControlHoverPreference,
                       nextValue: () -> MacModelControlHoverPreference) {
        let next = nextValue()
        if let help = next.help { value.help = help; value.button = next.button }
        if let pill = next.pill { value.pill = pill }
    }
}

struct MacModelControlHoverSource: ViewModifier {
    let title: String
    let shortcut: String?
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .anchorPreference(key: MacModelControlHoverKey.self, value: .bounds) {
                isHovered ? MacModelControlHoverPreference(
                    help: MacModelControlHelp(title: title, shortcut: shortcut), button: $0
                ) : .init()
            }
    }
}

struct MacModelControlHoverOverlay: View {
    let preference: MacModelControlHoverPreference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if let help = preference.help, let button = preference.button, let pill = preference.pill {
                MacModelControlHoverLayout(buttonX: geometry[button].midX, pillTop: geometry[pill].minY) {
                    MacModelControlHoverLabel(help: help)
                }
                .id(help)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 16)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: preference.help)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MacModelControlHoverLabel: View {
    let help: MacModelControlHelp

    var body: some View {
        HStack(spacing: 4) {
            Text(help.title)
            if let shortcut = help.shortcut {
                Text(shortcut).opacity(0.5)
            }
        }
        .font(AngroveTheme.Typography.body)
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(AngroveTheme.Colors.canvasSecondary,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AngroveTheme.Colors.border, lineWidth: 1)
        }
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
}

/// Keep help above the pill and within the pane even for its outermost buttons.
struct MacModelControlHoverLayout: Layout {
    let buttonX: CGFloat
    let pillTop: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let x = Self.leadingX(buttonX: buttonX, labelWidth: size.width, availableWidth: bounds.width)
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + pillTop - 8 - size.height),
                          proposal: ProposedViewSize(size))
        }
    }

    static func leadingX(buttonX: CGFloat, labelWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        max(8, min(buttonX - labelWidth / 2, availableWidth - labelWidth - 8))
    }
}
