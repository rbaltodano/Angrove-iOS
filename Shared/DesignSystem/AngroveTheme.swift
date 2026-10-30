// Shared visual tokens compiled by both the iOS and macOS targets.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        static let lightGreen = Color(light: 0x86803E, dark: 0xB7AE78)
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
        /// The selected or hovered row in the sidebar: Canvas Primary, at half strength in dark mode.
        static let sideMenuSelection = Color(light: 0xF3EEE2, lightAlpha: 1.0, dark: 0x120F0C, darkAlpha: 0.5)
        /// Every search field's magnifying glass.
        static let searchIcon = lightGreen
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
        /// Resting connections share one quiet style across concept, Insight, Branch and Midpoint lines.
        static let treeConnector = brownBorder.opacity(0.55)
        static let border = brownBorder
        static let quietBorder = brownBorder
        /// Floating menus and popover cards: the Mac's menus share one border; iPhone keeps its softer one.
        #if os(macOS)
        static let popupBorder = border
        #else
        static let popupBorder = darkBrown.opacity(0.08)
        #endif
        static let controlBorder = brownBorder
        static let mutedIcon = responseButton
        static let controlGlow = canvas
        static let floatingShadow = Color(
            light: 0x220F01,
            lightAlpha: 0.20,
            dark: 0x181511
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
        static let title = BrandTypography.font("LibreBaskerville-Regular", size: 24)
        static let illustratedCardHeading = BrandTypography.font("LibreBaskerville-Regular", size: 28)
        static let titleLarge = BrandTypography.font("LibreBaskerville-Regular", size: 34)
        static let titleHome = BrandTypography.font("LibreBaskerville-Regular", size: 40)
        static let titleXLarge = BrandTypography.font("LibreBaskerville-Regular", size: 40)
        static let heading = BrandTypography.font("LibreBaskerville-Regular", size: 20)
        static let quote = BrandTypography.font("LibreBaskerville-Italic", size: 16)
        static let baskervilleSmall = BrandTypography.font("LibreBaskerville-Bold", size: 12)
        static let uiDisplayLarge = BrandTypography.font("Figtree-Bold", size: 40)
        static let uiHeading = BrandTypography.font("Figtree-Bold", size: 18)
        static let uiSubheading = BrandTypography.font("Figtree-Bold", size: 14)
        static let uiLabel = BrandTypography.font("Figtree-Bold", size: 12)
        static let body = BrandTypography.font("Figtree-Regular", size: 14)
        static let bodyLarge = BrandTypography.font("Figtree-Regular", size: 16)
        static let inlineInsight = BrandTypography.font("Figtree-Bold", size: 16)
        static let chipLabel = BrandTypography.font("Figtree-Bold", size: 12)

        // Settings subpages follow the iPhone's Text Size setting.
        static let settingsTitle = BrandTypography.font("Figtree-Regular", size: 28, relativeTo: .title)
        static let settingsDetailTitleTracking: CGFloat = 0
        static let settingsHubEntry = BrandTypography.font("Figtree-SemiBold", fixedSize: 16)
        static let settingsDetailTitle = BrandTypography.font("Figtree-Regular", fixedSize: 40)
        static let settingsGuideTitleLineSpacing: CGFloat = 1.6
        static let settingsGuideTitle = BrandTypography.font("Figtree-Regular", size: 34, relativeTo: .largeTitle)
        static let settingsPartTitle = BrandTypography.font("Figtree-Regular", size: 24, relativeTo: .title2)
        static let settingsHeading = BrandTypography.font("Figtree-Bold", size: 17, relativeTo: .headline)
        static let settingsLabel = BrandTypography.font("Figtree-Bold", size: 17, relativeTo: .body)
        static let settingsBody = BrandTypography.font("Figtree-Regular", size: 17, relativeTo: .body)
        static let settingsSerifBody = BrandTypography.font("LibreBaskerville-Regular", size: 17, relativeTo: .body)
        static let settingsDetail = BrandTypography.font("Figtree-Regular", size: 13, relativeTo: .footnote)
    }

    // MARK: Spacing and Shape
    // Shared dimensions for cards, capsules, and icon controls.
    enum Spacing {
        static let insightCardMaxWidth: CGFloat = 400
        /// Search fields, search results, and the sidebar's selected row.
        static let selectionRadius: CGFloat = 16
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

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(light: UInt, lightAlpha: Double = 1, dark: UInt, darkAlpha: Double = 1) {
        #if canImport(UIKit)
        self.init(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light, alpha: CGFloat(isDark ? darkAlpha : lightAlpha))
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(isDark ? darkAlpha : lightAlpha)
            )
        })
        #endif
    }
}
