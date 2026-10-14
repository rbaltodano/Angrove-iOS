import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacQuestionLineSpacingTests {
    private let question = "How does practical wisdom guide our decisions when we have several responsibilities?"

    @Test func wrappedDraftsAndReplacedTextKeepSubmittedLineSpacing() async throws {
        let host = NSHostingView(rootView: editor(question).frame(width: 240))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let native = try #require(findEditor(in: host))
        try expectLineSpacing(native)
        host.rootView = editor("First explicit line\nSecond explicit line\nThird explicit line").frame(width: 240)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try expectLineSpacing(native)
        native.setSelectedRange(NSRange(location: 4, length: 3))
        let selection = native.selectedRange()
        native.refreshHighlight()
        #expect(native.selectedRange() == selection)
        let typingStyle = try #require(native.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(typingStyle.lineSpacing == AngroveTheme.Spacing.unit)
        native.insertText(" inserted text", replacementRange: NSRange(location: (native.string as NSString).length, length: 0))
        native.refreshHighlight()
        try expectLineSpacing(native)
    }

    @Test func editableAndSubmittedQuestionsRenderWithMatchingHeightInBothAppearances() throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let input = NSHostingView(rootView: editor(question).frame(width: 240))
            let submitted = NSHostingView(rootView: MacLineText(text: question, serif: true,
                lineHeight: MacConversationStyle.questionLineHeight).frame(width: 240))
            input.frame = NSRect(x: 0, y: 0, width: 240, height: 200)
            submitted.frame = input.frame
            input.layoutSubtreeIfNeeded()
            submitted.layoutSubtreeIfNeeded()
            #expect(abs(input.fittingSize.height - submitted.fittingSize.height) <= 2)
            let comparison = VStack(alignment: .trailing, spacing: 32) {
                Text("Before Enter").font(AngroveTheme.Typography.uiLabel)
                QuotedQuestionContainer(isEmpty: false, lineHeight: MacConversationStyle.questionLineHeight,
                    fontName: MacConversationStyle.questionFontName) {
                    editor(question).frame(width: 240)
                }
                Text("After Enter").font(AngroveTheme.Typography.uiLabel)
                QuotedQuestionContainer(isEmpty: false, lineHeight: MacConversationStyle.questionLineHeight,
                    fontName: MacConversationStyle.questionFontName) {
                    MacLineText(text: question, serif: true, lineHeight: MacConversationStyle.questionLineHeight)
                        .frame(width: 240)
                }
            }
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .padding(24)
            .background(AngroveTheme.Colors.canvas)
            let host = NSHostingView(rootView: comparison)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: 350, height: 440)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appending(path: "angrove-question-spacing-\(name).png"))
        }
    }

    private func editor(_ text: String) -> MacCommandEditor {
        MacCommandEditor(text: .constant(text), isFocused: .constant(false),
            reduceMotion: true, onSubmit: {}, onEscape: {})
    }

    private func findEditor(in view: NSView) -> MacCommandEditor.Editor? {
        if let editor = view as? MacCommandEditor.Editor { return editor }
        return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
    }

    private func expectLineSpacing(_ editor: MacCommandEditor.Editor) throws {
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        manager.ensureLayout(for: container)
        var origins: [CGFloat] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, _, _ in
            origins.append(rect.minY)
        }
        #expect(origins.count >= 3)
        for index in 1..<origins.count {
            #expect(abs(origins[index] - origins[index - 1] - MacConversationStyle.questionLineHeight) <= 1)
        }
    }
}
