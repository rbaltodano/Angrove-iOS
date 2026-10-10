//
//  SharedTypography.swift
//  Angrove-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI
import UIKit

enum AngroveTheme {
    // MARK: Colors
    // Canonical visual tokens mirrored from the Figma paint styles.
    enum Colors {
        static let canvas = Color(light: 0xF3EEE2, lightAlpha: 1.0, dark: 0x120F0C, darkAlpha: 1.0)
        static let insightTreeCanvas = canvasSecondary
        /// The canvas colour of the *opposite* mode — dark in light-mode, light in dark-mode.
        static let canvasInverse = Color(light: 0x14110F, dark: 0xF2E7D4)
        static let canvasSecondary = Color(light: 0xFFFAF0, dark: 0x24201C)
        static let canvasTertiary = Color(light: 0x2A2520, dark: 0xC0B494)
        static let componentBackground = Color(
            light: 0x6F6844,
            lightAlpha: 0.05,
            dark: 0x4D453B,
            darkAlpha: 0.10
        )
        static let responseButton = Color(
            light: 0x6F6844,
            lightAlpha: 0.50,
            dark: 0xFFFAF0,
            darkAlpha: 0.25
        )
        static let lightGreen = Color(UIColor.angroveLinkGreen)
        static let darkGreen = Color(light: 0x6F6844, dark: 0xB7AE78)
        static let primaryBrown = Color(light: 0x4A321C, dark: 0xFFFAF0)
        static let headingText = Color(light: 0x614C40, dark: 0xFFFAF0)
        static let illustratedCardTitle = Color(light: 0x2A2520, dark: 0xFFFAF0)
        // Light Brown: floating scroll control fill.
        static let lightBrown = Color(light: 0x614C40, dark: 0x2B2521)
        static let paragraphText = Color(
            light: 0x4A321C,
            lightAlpha: 0.75,
            dark: 0xFFFAF0,
            darkAlpha: 0.75
        )
        static let placeholderText = Color(
            light: 0x4A321C,
            lightAlpha: 0.50,
            dark: 0xFFFAF0,
            darkAlpha: 0.50
        )
        static let placeholderTextDarkMode = Color(hex: 0xFFFAF0, alpha: 0.50)
        static let paragraphTextDarkMode = Color(hex: 0xFFFAF0, alpha: 0.75)
        static let primaryReadableDarkMode = Color(hex: 0xFFFAF0)
        static let darkGreenDarkMode = Color(hex: 0xB7AE78)
        static let darkBrown = Color(light: 0x220F01, dark: 0xFFFAF0)
        static let branchConnector = Color(light: 0x220F01, dark: 0xFFFAF0)
        static let brownBorder = Color(
            light: 0x220F01,
            lightAlpha: 0.10,
            dark: 0xFFFAF0,
            darkAlpha: 0.08
        )
        static let sideMenuSearchBorder = Color(
            light: 0x6F6844,
            lightAlpha: 0.25,
            dark: 0xFFFAF0,
            darkAlpha: 0.08
        )
        static let systemSelection = Color(light: 0xF0E9DA, dark: 0x181511)
        /// A tint of `lightGreen` behind a response word while its Copy/Define menu is open.
        static let wordHighlight = Color(
            light: 0x86803E,
            lightAlpha: 0.28,
            dark: 0xB7AE78,
            darkAlpha: 0.30
        )
        static let accentRed = Color(light: 0xAF4949, dark: 0xAF4949)
        /// The "new" dot on an undiscovered Insight or Node Concept and on a conversation
        /// whose response finished while it wasn't open.
        static let unreadDot = Color(light: 0x408CFF, dark: 0x408CFF)
        static let uploadBorder = Color(light: 0xFFFFFF, dark: 0xFFFAF0)

        // Compatibility aliases used by older views. New code should prefer the tokens above.
        static let primary = primaryBrown
        static let primaryReadable = primaryBrown
        static let secondary = lightGreen
        static let secondaryMuted = darkGreen
        static let secondaryLight = lightGreen
        static let linkGreen = lightGreen
        static let background = componentBackground
        static let card = componentBackground
        static let cardRaised = canvas
        static let surface = canvas
        static let sideMenuSurface = canvasSecondary
        static let activeInquiryChrome = componentBackground
        static let darkText = darkBrown
        static let bodyText = paragraphText
        static let accent = accentRed
        static let accentMuted = accentRed
        static let divider = brownBorder
        static let border = brownBorder
        static let quietBorder = brownBorder
        static let controlBorder = brownBorder
        static let mutedIcon = responseButton
        static let controlGlow = canvas
        static let floatingShadow = Color(
            light: 0x220F01,
            lightAlpha: 0.20,
            dark: 0x220F01
        )
        static let dropShadow = floatingShadow
        static let mediaShadow = dropShadow

        // Floating-card glow: one warm brown in both modes, used by `cardGlow()`.
        static let cardGlowBase = Color(hex: 0x220F00)
        static let cardGlow = cardGlowBase.opacity(0.15)
        static let scrim = Color.black
        static let onAccent = Color(hex: 0xFFFAF0)
        static let pulse = Color(hex: 0x877D4F)
        static let deepSurface = Color(light: 0x201C18, dark: 0x130F0C)
        static let insightNodeFill = Color(light: 0xFFFAF0, dark: 0x0A0602)
        static let chipFill = Color(light: 0xFBF4E7, dark: 0x1B1714)
        static let menuFade = Color(light: 0xFAF5E8, dark: 0x141210)
        static let gaugeTrack = Color(light: 0xFFFFFF, dark: 0x130F0C)
        static let gaugeTrackBorder = Color(light: 0x220F01, lightAlpha: 0.15, dark: 0xFFFAF0, darkAlpha: 0.08)
        static let gaugeFill = Color(light: 0x4A321C, lightAlpha: 0.375, dark: 0xFFFAF0, darkAlpha: 0.55)
        static let hairline = Color(light: 0x220F00, lightAlpha: 0.18, dark: 0xFFFAF0, darkAlpha: 0.18)

        /// Scheme-resolved for UIViewRepresentable-hosted text, where dynamic colors can freeze.
        static func placeholder(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(hex: 0xFFFAF0, alpha: 0.50) : Color(hex: 0x4A321C, alpha: 0.50)
        }
        static func dotGrid(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(hex: 0xB7AE78) : Color(hex: 0x4A321C)
        }
    }

    // MARK: Typography
    // Libre Baskerville carries the editorial/conversation voice.
    // Figtree carries UI labels, body copy, buttons, and cards.
    enum Typography {
        static let title = Font.custom("LibreBaskerville-Regular", size: 24)
        static let illustratedCardHeading = Font.custom("LibreBaskerville-Regular", size: 28)
        static let titleLarge = Font.custom("LibreBaskerville-Regular", size: 34)
        static let titleHome = Font.custom("LibreBaskerville-Regular", size: 40)
        static let titleXLarge = Font.custom("LibreBaskerville-Regular", size: 40)
        static let heading = Font.custom("LibreBaskerville-Regular", size: 20)
        static let quote = Font.custom("LibreBaskerville-Italic", size: 16)
        static let baskervilleSmall = Font.custom("LibreBaskerville-Bold", size: 12)
        static let uiDisplayLarge = Font.custom("Figtree-Bold", size: 40)
        static let uiHeading = Font.custom("Figtree-Bold", size: 18)
        static let uiSubheading = Font.custom("Figtree-Bold", size: 14)
        static let uiLabel = Font.custom("Figtree-Bold", size: 12)
        static let body = Font.custom("Figtree-Regular", size: 14)
        static let bodyLarge = Font.custom("Figtree-Regular", size: 16)
        static let inlineInsight = Font.custom("Figtree-Bold", size: 16)
        static let chipLabel = Font.custom("Figtree-Bold", size: 12)

        // Settings subpages follow the iPhone's Text Size setting.
        static let settingsTitle = Font.custom("LibreBaskerville-Regular", size: 28, relativeTo: .title)
        static let settingsDetailTitle = Font.custom("LibreBaskerville-Regular", fixedSize: 40)
        static let settingsGuideParagraph = Font.custom("Figtree-Regular", size: 18, relativeTo: .body)
        static let settingsGuideLineSpacing: CGFloat = 8.1
        static let settingsGuideTitleLineSpacing: CGFloat = 1.6
        static let settingsGuideTitle = Font.custom("LibreBaskerville-Regular", size: 34, relativeTo: .largeTitle)
        static let settingsHeading = Font.custom("Figtree-Bold", size: 17, relativeTo: .headline)
        static let settingsLabel = Font.custom("Figtree-Bold", size: 17, relativeTo: .body)
        static let settingsBody = Font.custom("Figtree-Regular", size: 17, relativeTo: .body)
        static let settingsSerifBody = Font.custom("LibreBaskerville-Regular", size: 17, relativeTo: .body)
        static let settingsDetail = Font.custom("Figtree-Regular", size: 13, relativeTo: .footnote)
    }

    // MARK: Spacing and Shape
    // Shared dimensions for cards, capsules, and icon controls.
    enum Spacing {
        static let unit: CGFloat = 8
        static let screenPadding: CGFloat = 16
        static let cardPadding: CGFloat = 24
        static let illustratedCardPadding: CGFloat = 28
        static let cardRadius: CGFloat = 28
        static let smallCardRadius: CGFloat = 16
        static let controlHeight: CGFloat = 44
        static let iconButtonSize: CGFloat = 44
    }
}

extension Animation {
    /// Gentle spring shared by the Insight card's height changes (bars → definition) and
    /// swiping between saved insights, keeping the motion soft with only a subtle bounce.
    static let insightCardBounce = Animation.springQuick
}

extension AnyTransition {
    /// Shared entrance/removal for cards presented immediately above the bottom control dock.
    /// The bottom anchor and vertical transform make the card feel connected to its trigger.
    /// Giving each direction its own animation keeps removals from falling back to an
    /// opacity-only fade when their state is cleared outside an explicit transaction.
    static var bottomDockCard: AnyTransition {
        let cardTransform = AnyTransition.scale(scale: 0.35, anchor: .bottom)
            .combined(with: .offset(y: 24))
            .combined(with: .opacity)

        return .asymmetric(
            insertion: cardTransform.animation(.springStandard),
            removal: cardTransform.animation(.springQuick)
        )
    }
}

struct QueuedWorkBreatheModifier: ViewModifier {
    let isQueued: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathingOpacity: Double = 1

    func body(content: Content) -> some View {
        content
            .opacity(isQueued ? breathingOpacity : 1)
            .task(id: animationState) {
                await runAnimation()
            }
    }

    private var animationState: Int {
        guard isQueued else { return 0 }
        return reduceMotion ? 1 : 2
    }

    private func runAnimation() async {
        guard isQueued else {
            withAnimation(.easeInOut(duration: 0.2)) {
                breathingOpacity = 1
            }
            return
        }

        guard !reduceMotion else {
            breathingOpacity = 0.75
            return
        }

        breathingOpacity = 0.5
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.9)) {
                breathingOpacity = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                breathingOpacity = 0.5
            }
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
        }
    }
}

extension Color {
    // Older views still use these brand names. They point back to the canonical theme tokens above.
    static let brandRed = AngroveTheme.Colors.accent
    static let brandDarkText = AngroveTheme.Colors.darkText
    static let brandGreen = AngroveTheme.Colors.linkGreen
    static let brandBrown = AngroveTheme.Colors.primary
    static let brandLightGreen = AngroveTheme.Colors.linkGreen
    static let chatBubbleColor = AngroveTheme.Colors.card
    static let backgroundColor = AngroveTheme.Colors.background

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(light: UInt, lightAlpha: Double = 1, dark: UInt, darkAlpha: Double = 1) {
        self.init(UIColor(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha))
    }
}

extension UIColor {
    static let angroveAccent = UIColor(light: 0xAF4949, dark: 0xAF4949)
    static let angroveLinkGreen = UIColor(light: 0x86803E, dark: 0xB7AE78)
    /// Primary readable text — warm brown in light, warm cream in dark.
    /// Prefer this over UIColor(AngroveTheme.Colors.primaryReadable) for UIKit
    /// text-color properties; the Color→UIColor round-trip can freeze at the
    /// light-mode value inside UIViewRepresentable contexts.
    static let angrovePrimaryReadable = UIColor(light: 0x4A321C, dark: 0xFFFAF0)
    static let angrovePlaceholderText = UIColor(
        light: 0x4A321C, lightAlpha: 0.50,
        dark: 0xFFFAF0,  darkAlpha: 0.50
    )
    static let angroveParagraphText = UIColor(
        light: 0x4A321C,
        lightAlpha: 0.75,
        dark: 0xFFFAF0,
        darkAlpha: 0.75
    )

    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init(light: UInt, lightAlpha: Double = 1, dark: UInt, darkAlpha: Double = 1) {
        self.init { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(hex: dark, alpha: CGFloat(darkAlpha))
            default:
                return UIColor(hex: light, alpha: CGFloat(lightAlpha))
            }
        }
    }
}

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
    static let figtreeSmall = Font.custom("Figtree-Regular", size: 12)

    // MARK: Libre Baskerville aliases
    static let baskervilleHeadingXLarge = AngroveTheme.Typography.titleXLarge
    static let baskervilleHeading1 = AngroveTheme.Typography.title
    static let baskervilleHeading2 = AngroveTheme.Typography.heading
    static let baskervilleHeading3 = Font.custom("LibreBaskerville-Regular", size: 14)
    static let baskervilleBody = Font.custom("LibreBaskerville-Regular", size: 16)
    static let baskervilleParagraph = Font.custom("LibreBaskerville-Regular", size: 14)
    static let baskervilleQuote = AngroveTheme.Typography.quote
    static let baskervilleSmall = AngroveTheme.Typography.baskervilleSmall

    // MARK: Display scale (24 pt)
    static let baskervilleDisplay = Font.custom("LibreBaskerville-Regular", size: 24)
    static let figtreeDisplay = Font.custom("Figtree-Bold", size: 24)
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

// MARK: - Section Structure

/// Serif section title used to break scrollable content into manuscript-style sections
/// (e.g. Home's "Where You Left Off", Open Conversations' "Pinned").
struct AngroveSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.custom("LibreBaskerville-Regular", size: 28))
            .foregroundColor(AngroveTheme.Colors.primaryReadable)
            .lineSpacing(7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thin centered rule that separates sections, mimicking a page break between manuscript entries.
struct AngroveSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(AngroveTheme.Colors.quietBorder)
            .frame(width: 253, height: 1)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Text Helpers

/// Reusable paragraph text with the app's body color and line spacing.
struct BodyText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.figtreeParagraph)
            .lineSpacing(6)
            .foregroundColor(AngroveTheme.Colors.bodyText)
    }
}

/// Builds a Libre Baskerville title with one italic highlighted keyword.
func createEditorialTitle(
    fullText: String,
    keyword: String,
    fontSize: CGFloat,
    baseColor: Color = AngroveTheme.Colors.darkText,
    keywordColor: Color = AngroveTheme.Colors.accent
) -> AttributedString {
    var attributedString = AttributedString(fullText)

    attributedString.font = .custom("LibreBaskerville-Regular", size: fontSize)
    attributedString.foregroundColor = baseColor

    if let range = attributedString.range(of: keyword) {
        attributedString[range].font = .custom("LibreBaskerville-Italic", size: fontSize)
        attributedString[range].foregroundColor = keywordColor
    }

    return attributedString
}

// MARK: - User paragraph font

/// Applies the user's response font and size settings to app-wide paragraph text.
/// Sans/Medium reproduces the design-system body (14) and bodyLarge (16) exactly.
struct ParagraphFontModifier: ViewModifier {
    enum Role {
        case regular
        case large

        var baseSize: CGFloat {
            switch self {
            case .regular: 14
            case .large: 16
            }
        }
    }

    let role: Role
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var fontSize: ConversationFontSizeOption = .medium

    func body(content: Content) -> some View {
        let size = role.baseSize + (fontSize.pointSize - ConversationFontSizeOption.medium.pointSize)
        switch responseFont {
        case .sans: content.font(.custom("Figtree-Regular", fixedSize: size))
        case .serif: content.font(.custom("LibreBaskerville-Regular", fixedSize: size))
        }
    }
}

extension View {
    func paragraphFont(_ role: ParagraphFontModifier.Role = .regular) -> some View {
        modifier(ParagraphFontModifier(role: role))
    }
}

extension View {
    /// Shared soft glow for cards that float over the canvas.
    func cardGlow(yOffset: CGFloat = 0) -> some View {
        shadow(color: AngroveTheme.Colors.cardGlow, radius: 24, x: 0, y: yOffset)
    }
}

// MARK: - Settings text

/// Settings-page text that follows the user's conversation font size. Paragraphs also follow
/// the response font; labels, controls, and details stay in the UI sans face.
struct SettingsTextModifier: ViewModifier {
    enum Role {
        case label, control, paragraph, detail
    }

    let role: Role
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var fontSize: ConversationFontSizeOption = .medium

    func body(content: Content) -> some View {
        let base = fontSize.pointSize
        switch role {
        case .label: content.font(.custom("Figtree-Bold", fixedSize: base))
        case .control: content.font(.custom("Figtree-Regular", fixedSize: base))
        case .detail: content.font(.custom("Figtree-Regular", fixedSize: max(base - 2, 11)))
        case .paragraph:
            switch responseFont {
            case .sans: content.font(.custom("Figtree-Regular", fixedSize: base))
            case .serif: content.font(.custom("LibreBaskerville-Regular", fixedSize: base))
            }
        }
    }
}

extension View {
    func settingsText(_ role: SettingsTextModifier.Role) -> some View {
        modifier(SettingsTextModifier(role: role))
    }
}

/// Matches the bundled User Guide's introductory copy (18pt Figtree, 1.65 line height).
struct SettingsGuideParagraphModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AngroveTheme.Typography.settingsGuideParagraph)
            .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func settingsGuideParagraph() -> some View {
        modifier(SettingsGuideParagraphModifier())
    }
}
