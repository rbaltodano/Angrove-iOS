import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardTypographyTests {
    @Test func revealKeepsTheFinishedNotesLayoutAndFont() async throws {
        let text = "Prudence perfects practical judgment, guiding the other virtues toward their proper end.\n\nA second paragraph keeps its spacing as the summary finishes."
        let elapsed = Elapsed()
        let changing = NSHostingView(rootView: RevealFixture(elapsed: elapsed, text: text))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 360, height: 420),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = changing
        defer { window.contentView = nil; window.close() }
        changing.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        let editor = try #require(findEditor(changing))
        let storage = try #require(editor.textStorage)
        let layout = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        layout.ensureLayout(for: container)
        let initialRect = layout.usedRect(for: container)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let paragraph = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(font == WorktreeTextEditor.font)
        #expect((storage.attribute(.foregroundColor, at: storage.length - 1, effectiveRange: nil) as? NSColor)?.alphaComponent == 0)
        elapsed.value = nil
        try await Task.sleep(for: .milliseconds(40))
        changing.layoutSubtreeIfNeeded()
        layout.ensureLayout(for: container)
        #expect(layout.usedRect(for: container) == initialRect)
        #expect(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == font)
        #expect(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle == paragraph)
        try await Task.sleep(for: .seconds(1))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            changing.needsDisplay = true
            changing.displayIfNeeded()
            let bitmap = try #require(changing.bitmapImageRepForCachingDisplay(in: changing.bounds))
            changing.cacheDisplay(in: changing.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "angrove-board-note-\(name).png"))
        }
    }

    private func findEditor(_ view: NSView) -> WorktreeTextEditor.Editor? {
        if let editor = view as? WorktreeTextEditor.Editor { return editor }
        return view.subviews.lazy.compactMap { findEditor($0) }.first
    }

    @Observable final class Elapsed { var value: Double? = 0.1 }
    private struct RevealFixture: View {
        let elapsed: Elapsed
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                WorktreeRevealedText(text: "The Cardinal Virtues", font: MacPageHeading.pageFont,
                    color: AngroveTheme.Colors.headingText, naturalFont: WorktreeItemView.headingFont,
                    lineHeight: WorktreeItemView.headingLineHeight, tracking: WorktreeItemView.headingTracking,
                    width: 280, onEdit: {})
                WorktreeTextEditor(text: .constant(text), isEditing: false,
                fillsWidth: true, maxWidth: 280, color: AngroveTheme.Colors.paragraphText,
                revealElapsed: elapsed.value, onBeginEditing: {}, onEndEditing: {}, onCommit: {}, onEscape: {})
                .frame(width: 280)
            }
                .padding(24)
                .background(AngroveTheme.Colors.canvas)
        }
    }
}
