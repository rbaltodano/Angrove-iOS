//
//  SharedTypography.swift
//  Angrove-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif


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


}

#if os(iOS)
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


#endif

/// Serif section title for manuscript-style content sections.
struct AngroveSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(BrandTypography.font("LibreBaskerville-Regular", size: 28))
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

    attributedString.font = BrandTypography.font("LibreBaskerville-Regular", size: fontSize)
    attributedString.foregroundColor = baseColor

    if let range = attributedString.range(of: keyword) {
        attributedString[range].font = BrandTypography.font("LibreBaskerville-Italic", size: fontSize)
        attributedString[range].foregroundColor = keywordColor
    }

    return attributedString
}

// MARK: - App paragraph font

/// App interface prose stays in Figtree. The response font preference is reserved for model output.
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
    @AppStorage("aquinas.settings.conversationFontSize") private var fontSize: ConversationFontSizeOption = .small

    func body(content: Content) -> some View {
        let size = role.baseSize + (fontSize.pointSize - ConversationFontSizeOption.medium.pointSize)
        content.font(BrandTypography.font("Figtree-Regular", fixedSize: size))
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

/// Settings prose always uses Figtree, while retaining the person's text-size preference.
struct SettingsTextModifier: ViewModifier {
    enum Role {
        case label, control, menuEntry, partTitle, paragraph, detail
    }

    let role: Role
    @AppStorage("aquinas.settings.conversationFontSize") private var fontSize: ConversationFontSizeOption = .small

    func body(content: Content) -> some View {
        let base = fontSize.pointSize
        switch role {
        case .label: content.font(BrandTypography.font("Figtree-Bold", fixedSize: base))
        case .control: content.font(BrandTypography.font("Figtree-Regular", fixedSize: base))
        case .menuEntry: content.font(BrandTypography.font("Figtree-SemiBold", fixedSize: base))
        case .partTitle: content.font(BrandTypography.font("LibreBaskerville-Regular", fixedSize: base))
        case .detail: content.font(BrandTypography.font("Figtree-Regular", fixedSize: max(base - 2, 11)))
        case .paragraph:
            content.font(BrandTypography.font("Figtree-Regular", fixedSize: base)).lineSpacing(FlowLayout.rowSpacing)
        }
    }
}

extension View {
    func settingsText(_ role: SettingsTextModifier.Role) -> some View {
        modifier(SettingsTextModifier(role: role))
    }
}

/// Left-aligned settings prose with consistent Figtree typography and an entrance reveal.
struct SettingsParagraphModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .settingsText(.paragraph)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .settingsTextReveal()
    }
}

extension View {
    func settingsParagraph() -> some View {
        modifier(SettingsParagraphModifier())
    }
}
