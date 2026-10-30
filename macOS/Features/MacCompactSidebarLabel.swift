import SwiftUI

struct MacCompactSidebarHover {
    let destination: MacDestination
    let anchor: Anchor<CGRect>
}

struct MacCompactSidebarHoverKey: PreferenceKey {
    static var defaultValue: MacCompactSidebarHover? { nil }
    static func reduce(value: inout MacCompactSidebarHover?, nextValue: () -> MacCompactSidebarHover?) {
        if let next = nextValue() { value = next }
    }
}

struct MacCompactSidebarButton: View {
    let destination: MacDestination
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            MacIconView(icon: destination.asset)
                .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
                .animation(reduceMotion ? nil : .springMicro, value: isHovered)
                .frame(width: 44, height: 44)
                .background(isSelected || isHovered ? AngroveTheme.Colors.sideMenuSelection : .clear,
                            in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous))
                .contentShape(Rectangle())
                // The icon hides itself from VoiceOver, which left the Mac button unnamed.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(destination.title))
        }
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .anchorPreference(key: MacCompactSidebarHoverKey.self, value: .bounds) { anchor in
            isHovered || isFocused ? MacCompactSidebarHover(destination: destination, anchor: anchor) : nil
        }
        .accessibilityLabel(Text(destination.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MacCompactSidebarLabelOverlay: View {
    let hover: MacCompactSidebarHover?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if let hover {
                let bounds = geometry[hover.anchor]
                Text(hover.destination.title)
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
                    .offset(x: bounds.maxX + MacSidebarLayout.compactWidth - MacSidebarLayout.contentInset - 44 + 8,
                            y: bounds.midY - 18)
                    .id(hover.destination)
                    .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : -16)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: hover?.destination)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
