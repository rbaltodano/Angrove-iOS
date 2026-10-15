import AppKit
import SwiftUI

/// Uses the same symbol names and context gauge as the iOS app.
enum MacIcon: String {
    case home, insights, conversations, library, topics, studyTopic, worktree
    case ellipsis, settings, plus, send, statusArrow, contextRing
    var symbol: String {
        switch self {
        case .home: AppPage.home.sidebarIconName
        case .insights: AppPage.insights.sidebarIconName
        case .conversations: AppPage.openConversations.sidebarIconName
        case .library: AppPage.library.sidebarIconName
        case .topics, .studyTopic: AppPage.studyTopics.sidebarIconName
        case .settings: AppPage.settings.sidebarIconName
        case .worktree: "square.on.square.dashed"
        case .ellipsis: "ellipsis"
        case .plus, .statusArrow: "plus"
        case .send: "paperplane.fill"
        case .contextRing: "circle"
        }
    }
    var size: CGFloat {
        switch self {
        case .studyTopic, .plus: 10
        case .ellipsis, .statusArrow: 12
        default: 16
        }
    }
    var color: Color {
        switch self {
        case .home, .insights, .conversations, .library, .topics, .studyTopic, .worktree, .send, .statusArrow:
            AngroveTheme.Colors.lightGreen
        case .plus: AngroveTheme.Colors.canvas
        default: AngroveTheme.Colors.paragraphText
        }
    }
}

struct MacIconView: View {
    let icon: MacIcon
    var body: some View {
        if icon == .contextRing {
            ContextUsageIcon(progress: 0, color: AngroveTheme.Colors.paragraphText.opacity(0.75))
                .accessibilityHidden(true)
        } else {
            Image(systemName: icon.symbol)
                .font(.system(size: icon.size, weight: .medium))
                .foregroundStyle(icon.color)
                .frame(width: icon.size, height: icon.size)
                .accessibilityHidden(true)
        }
    }
}

/// Mac-specific additions to the shared visual language; shared colors and
/// existing type styles continue to come from AngroveTheme.
enum MacConversationStyle {
    /// One size for the sidebar menu, response paragraphs, and native question editor.
    static let bodyFontSize: ConversationFontSizeOption = .medium
    /// The widest any page's content grows, matching the conversation column.
    static let pageContentMaxWidth: CGFloat = 800
    /// The conversation column is narrower than other pages.
    static let conversationColumnMaxWidth: CGFloat = 600
    /// The space above a page's content, matching the side padding.
    static let pageTopPadding: CGFloat = 84
    /// The space between a page's content and the left and right edges of the window.
    static let pageHorizontalPadding: CGFloat = 84
    /// The iOS question field's width, 50% wider for the desktop.
    static let questionMaxWidth = QuotedQuestionContainer<Text>.quotedMaxWidth * 1.5
    /// Settings › Question font, shared with the iPhone's input font preference.
    static let questionFontKey = "aquinas.settings.inputFont"
    static var usesSerifQuestions: Bool {
        UserDefaults.standard.string(forKey: questionFontKey) != ConversationFontOption.sans.rawValue
    }
    static var questionFontName: String { usesSerifQuestions ? "LibreBaskerville-Regular" : "Figtree-Regular" }
    static var questionNativeFont: NSFont {
        let size = BrandTypography.pointSize(bodyFontSize.pointSize)
        return NSFont(name: questionFontName, size: size) ?? .systemFont(ofSize: size)
    }
    static var questionLineHeight: CGFloat {
        ceil(questionNativeFont.ascender - questionNativeFont.descender + questionNativeFont.leading + AngroveTheme.Spacing.unit)
    }
    static func questionContentWidth(_ text: String, minimum: String = "") -> CGFloat {
        let font = questionNativeFont
        let textWidth = text.components(separatedBy: .newlines).map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let minimumWidth = text.isEmpty ? (minimum as NSString).size(withAttributes: [.font: font]).width : 0
        return max(1, ceil(max(textWidth, minimumWidth)) + 2)
    }
    static let serifBody = ConversationFontOption.serif.textFont(size: bodyFontSize)
    static let pinnedTitle = BrandTypography.font("LibreBaskerville-Regular", size: 18, relativeTo: .headline)
    static let status = BrandTypography.font("Figtree-SemiBold", size: 14, relativeTo: .body)
    static let border = AngroveTheme.Colors.darkBrown.opacity(0.08)
    static let edgeFade = Color(light: 0xF4EFE4, dark: 0x120F0C)
}

/// Figma's line boxes include leading above and below the glyphs, while
/// SwiftUI lineSpacing only adds it between lines.
struct MacLineText: View {
    let text: String
    var serif = false
    var size: CGFloat = 14
    var lineHeight: CGFloat = 22

    private var extraLeading: CGFloat {
        let name = serif ? "LibreBaskerville-Regular" : "Figtree-Regular"
        guard let font = NSFont(name: name, size: BrandTypography.pointSize(size)) else { return 0 }
        return max(0, lineHeight - ceil(font.ascender - font.descender + font.leading))
    }

    var body: some View {
        Text(verbatim: text)
            .font(serif ? (size == 28 ? AngroveTheme.Typography.illustratedCardHeading : MacConversationStyle.serifBody) : AngroveTheme.Typography.body)
            .lineSpacing(extraLeading)
            .padding(.vertical, extraLeading / 2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Fixtures are only compiled into development builds. Nothing in this screen
/// pretends these Figma samples were generated by the native runtime.
enum MacDesignPreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mac-design-preview") || startsScrolled
        #else
        false
        #endif
    }
    static var startsScrolled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mac-design-preview-scrolled")
        #else
        false
        #endif
    }
    static var colorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mac-preview-light") { return .light }
        if ProcessInfo.processInfo.arguments.contains("--mac-preview-dark") { return .dark }
        #endif
        return nil
    }
    static var compact: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mac-preview-compact")
        #else
        false
        #endif
    }
    #if DEBUG
    static let question = "“Why does God allow bad things to happend to good people?”"
    static let response = "As I analyze \"The Didache,\" I recognize it as a foundational text from early Christianity, often called \"The Teaching of the Twelve Apostles.\" This document serves as an early church manual, outlining ethics, rituals, and organizational structure. Its name shares roots with the word \"didactic,\" highlighting its instructional purpose. Understanding \"The Didache\" helps me grasp how early Christian communities structured their beliefs and practices."
    #endif
}
