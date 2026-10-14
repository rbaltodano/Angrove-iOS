import SwiftUI

extension Font {
    // MARK: Figtree aliases
    static let figtreeHeading1 = AngroveTheme.Typography.uiHeading
    static let figtreeHeading2 = AngroveTheme.Typography.uiSubheading
    static let figtreeHeading3 = AngroveTheme.Typography.uiLabel
    static let figtreeParagraph = AngroveTheme.Typography.body
    static let figtreeParagraphLarge = AngroveTheme.Typography.bodyLarge
    static let figtreeParagraphInsight = AngroveTheme.Typography.inlineInsight
    static let figtreeChipLabel = AngroveTheme.Typography.chipLabel
    static let figtreeHeadingXLarge = AngroveTheme.Typography.uiDisplayLarge
    static let figtreeSmall = BrandTypography.font("Figtree-Regular", size: 12)

    // MARK: Libre Baskerville aliases
    static let baskervilleHeadingXLarge = AngroveTheme.Typography.titleXLarge
    static let baskervilleHeading1 = AngroveTheme.Typography.title
    static let baskervilleHeading2 = AngroveTheme.Typography.heading
    static let baskervilleHeading3 = BrandTypography.font("LibreBaskerville-Regular", size: 14)
    static let baskervilleBody = BrandTypography.font("LibreBaskerville-Regular", size: 16)
    static let baskervilleParagraph = BrandTypography.font("LibreBaskerville-Regular", size: 14)
    static let baskervilleQuote = AngroveTheme.Typography.quote
    static let baskervilleSmall = AngroveTheme.Typography.baskervilleSmall

    // MARK: Display scale (24 pt)
    static let baskervilleDisplay = BrandTypography.font("LibreBaskerville-Regular", size: 24)
    static let figtreeDisplay = BrandTypography.font("Figtree-Bold", size: 24)
}

struct SFSymbolDrawOnStyle: ViewModifier {
    var delay: TimeInterval = 0
    @State private var isVisible = false

    func body(content: Content) -> some View {
        Group {
            if isVisible {
                animatedContent(content)
            } else {
                content.hidden()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.55)) {
                    isVisible = true
                }
            }
        }
    }

    @ViewBuilder
    private func animatedContent(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Draw On is a symbol transition effect, so it runs when this wrapper inserts or removes the icon.
            content.transition(.symbolEffect(.drawOn).combined(with: IconBlurRevealTransition()))
        } else {
            // Earlier OS versions still get a gentle entrance instead of a hard pop-in.
            content.transition(.opacity.combined(with: .scale(scale: 0.94)).combined(with: AnyTransition.iconBlurReveal))
        }
    }
}

private struct IconBlurRevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.blur(radius: phase.isIdentity ? 0 : 4)
    }
}

private struct IconBlurReveal: ViewModifier {
    let blur: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: blur)
    }
}

private extension AnyTransition {
    static var iconBlurReveal: AnyTransition {
        .modifier(
            active: IconBlurReveal(blur: 4),
            identity: IconBlurReveal(blur: 0)
        )
    }
}

extension View {
    func parchmentCard(
        radius: CGFloat = AngroveTheme.Spacing.cardRadius,
        background: Color = AngroveTheme.Colors.card,
        border: Color = AngroveTheme.Colors.quietBorder
    ) -> some View {
        modifier(ParchmentCardStyle(radius: radius, background: background, border: border))
    }

    func angroveCapsuleControl(isSelected: Bool = false) -> some View {
        modifier(AngroveCapsuleControlStyle(isSelected: isSelected))
    }

    func angroveIconControl(isPrimary: Bool = false) -> some View {
        modifier(AngroveIconControlStyle(isPrimary: isPrimary))
    }

    func sfSymbolDrawOn(delay: TimeInterval = 0) -> some View {
        modifier(SFSymbolDrawOnStyle(delay: delay))
    }
}

struct ParchmentCardStyle: ViewModifier {
    var radius: CGFloat = AngroveTheme.Spacing.cardRadius
    var background: Color = AngroveTheme.Colors.card
    var border: Color = AngroveTheme.Colors.quietBorder

    func body(content: Content) -> some View {
        // Shared flat card shell. Use this before adding one-off card styling.
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
}

struct AngroveCapsuleControlStyle: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        // Shared pill controls for the bottom dock and canvas controls.
        content
            .foregroundColor(AngroveTheme.Colors.primaryReadable)
            .frame(minHeight: AngroveTheme.Spacing.controlHeight)
            .background(isSelected ? AngroveTheme.Colors.secondaryMuted : AngroveTheme.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AngroveTheme.Colors.controlBorder, lineWidth: isSelected ? 0 : 1)
            )
    }
}

struct AngroveIconControlStyle: ViewModifier {
    var isPrimary: Bool = false

    func body(content: Content) -> some View {
        // Shared circular icon buttons, including plus and scroll-to-bottom.
        content
            .foregroundColor(isPrimary ? AngroveTheme.Colors.canvas : AngroveTheme.Colors.linkGreen)
            .frame(width: AngroveTheme.Spacing.iconButtonSize, height: AngroveTheme.Spacing.iconButtonSize)
            .background(isPrimary ? AngroveTheme.Colors.secondaryMuted : AngroveTheme.Colors.surface)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(AngroveTheme.Colors.controlBorder, lineWidth: isPrimary ? 0 : 1)
            )
    }
}



/// Mac uses a consistent desktop text baseline; iPhone retains its existing type scale.
enum BrandTypography {
    static func pointSize(_ size: CGFloat) -> CGFloat {
        #if os(macOS)
        return size <= 18 ? 13 : min(size, 24)
        #else
        return size
        #endif
    }
    static func font(_ name: String, fixedSize: CGFloat) -> Font {
        Font.custom(name, fixedSize: pointSize(fixedSize))
    }
    static func font(_ name: String, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(name, size: pointSize(size), relativeTo: style)
    }
}
