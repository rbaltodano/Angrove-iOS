import AppKit
import SwiftUI

/// Bare canvas text: no field chrome. Return commits (Shift-Return breaks the line; Command-Return
/// also commits) and Escape deselects. Without `fillsWidth` the editor hugs its longest line, wrapping at `maxWidth`.
struct WorktreeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditing: Bool
    var placeholder: String?
    var alignment: NSTextAlignment = .left
    var fillsWidth = false
    /// Return commits (Shift-Return breaks the line), as in a conversation's composer.
    var submitsOnReturn = true
    var maxWidth: CGFloat = 480
    var color: Color = AngroveTheme.Colors.headingText
    /// Recognised slash commands turn green with the conversation composer's sweep.
    var highlightsCommands = false
    var textFont: NSFont = WorktreeTextEditor.font
    var textLineHeight: CGFloat = WorktreeTextEditor.lineHeight
    var textTracking: CGFloat = 0
    /// Full text stays laid out while the summary fades in, keeping its final note geometry.
    var revealElapsed: Double? = nil
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void
    let onCommit: () -> Void
    let onEscape: () -> Void

    static let font = NSFont(name: "Figtree-Regular", size: 14) ?? .systemFont(ofSize: 14)
    /// The design's 2× line height for Figtree 14.
    nonisolated static let lineHeight: CGFloat = 28
    private var naturalLineHeight: CGFloat { ceil(textFont.ascender - textFont.descender + textFont.leading) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Editor {
        let view = Editor()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = fillsWidth
        let extra = max(0, textLineHeight - naturalLineHeight)
        view.textContainerInset = NSSize(width: 0, height: extra / 2)
        view.font = textFont
        view.insertionPointColor = NSColor(AngroveTheme.Colors.lightGreen)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = extra
        paragraph.alignment = alignment
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: textFont, .paragraphStyle: paragraph, .foregroundColor: NSColor(color), .kern: textTracking]
        view.string = text
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    static func dismantleNSView(_ view: Editor, coordinator: Coordinator) { view.stopWave() }

    func updateNSView(_ view: Editor, context: Context) {
        if context.coordinator.parent.text != text {
            context.coordinator.revealWords = Self.wordRanges(in: text)
        }
        context.coordinator.parent = self
        view.placeholder = placeholder
        view.placeholderAlignment = alignment
        view.baseColor = NSColor(color)
        view.highlightsCommands = highlightsCommands
        view.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if view.string != text, !view.hasMarkedText() {
            view.undoManager?.removeAllActions()
            view.string = text
            view.invalidateIntrinsicContentSize()
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        view.refreshHighlight()
        if let revealElapsed, let storage = view.textStorage {
            let words = context.coordinator.revealWords
            for (index, range) in words.enumerated() {
                let start = Double(index / 4) * 0.0275
                let progress = min(1, max(0, (revealElapsed - start) / 0.55))
                let alpha = 1 - pow(1 - progress, 3)
                storage.addAttribute(.foregroundColor, value: NSColor(color).withAlphaComponent(NSColor(color).alphaComponent * alpha), range: range)
            }
        }
        if isEditing, view.window?.firstResponder !== view {
            DispatchQueue.main.async { [weak view] in
                guard let view, context.coordinator.parent.isEditing else { return }
                view.window?.makeFirstResponder(view)
            }
        } else if !isEditing, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    static func wordRanges(in text: String) -> [NSRange] {
        let pattern = try! NSRegularExpression(pattern: #"\S+"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Editor, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        let width = fillsWidth ? (proposal.width ?? maxWidth) : maxWidth
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let lines = max(1, layout.numberOfGlyphs == 0 ? 1 : Int(round(used.height / textLineHeight)))
        let height = max(textLineHeight, ceil(used.height) + nsView.textContainerInset.height * 2,
                         CGFloat(lines) * textLineHeight)
        let placeholderWidth = text.isEmpty ? (placeholder.map { ($0 as NSString).size(withAttributes: [.font: textFont]).width } ?? 0) : 0
        // Two points of slack keep the insertion point visible after the last character.
        return CGSize(width: fillsWidth ? width : min(width, max(ceil(used.width), placeholderWidth) + 2), height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WorktreeTextEditor
        var revealWords: [NSRange]
        init(_ parent: WorktreeTextEditor) {
            self.parent = parent
            revealWords = WorktreeTextEditor.wordRanges(in: parent.text)
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? Editor else { return }
            parent.text = view.string
            view.refreshHighlight()
            view.invalidateIntrinsicContentSize()
        }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            if parent.submitsOnReturn, selector == #selector(NSResponder.insertNewline(_:)),
               !NSEvent.modifierFlags.contains(.shift) { parent.onCommit(); return true }
            return false
        }
        func commit() { parent.onCommit() }
    }

    final class Editor: NSTextView {
        private let editingUndoManager: UndoManager = {
            let manager = UndoManager()
            manager.levelsOfUndo = 20
            return manager
        }()
        override var undoManager: UndoManager? { editingUndoManager }

        var placeholder: String? { didSet { if placeholder != oldValue { needsDisplay = true } } }
        var placeholderAlignment: NSTextAlignment = .left
        var baseColor: NSColor = .textColor
        var highlightsCommands = false
        var reduceMotion = false
        private var commands: [NSRange] = []
        private var waveStart = Date.distantPast
        private var timer: Timer?

        /// Matches `MacCommandEditor`: a newly recognised command sweeps from ink to green over a second.
        func refreshHighlight() {
            guard !hasMarkedText() else { return }
            let next = highlightsCommands ? WorktreeCommandParser.commandRanges(in: string) : []
            let known = Set(commands.map { "\($0.location):\($0.length)" })
            if next.contains(where: { !known.contains("\($0.location):\($0.length)") }), !reduceMotion {
                waveStart = Date()
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
                    MainActor.assumeIsolated {
                        guard let self else { timer.invalidate(); return }
                        self.applyHighlight()
                        if Date().timeIntervalSince(self.waveStart) >= 1 { timer.invalidate() }
                    }
                }
            }
            commands = next
            applyHighlight()
        }

        func stopWave() { timer?.invalidate() }

        private func applyHighlight() {
            guard !hasMarkedText(), let storage = textStorage else { return }
            storage.addAttribute(.foregroundColor, value: baseColor, range: NSRange(location: 0, length: storage.length))
            typingAttributes[.foregroundColor] = baseColor
            let green = NSColor(AngroveTheme.Colors.lightGreen)
            let progress = reduceMotion ? 1 : min(1, Date().timeIntervalSince(waveStart))
            for range in commands where NSMaxRange(range) <= storage.length {
                var color = green
                if progress < 1, let manager = layoutManager, let container = textContainer, bounds.width > 0 {
                    let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                    let band = max(rect.width * 0.4, 1)
                    let front = rect.minX - band + (rect.width + 2 * band) * progress
                    let base = baseColor
                    let image = NSImage(size: NSSize(width: max(bounds.width, rect.maxX + band), height: 1), flipped: false) { _ in
                        guard let gradient = NSGradient(starting: green, ending: base) else { return false }
                        gradient.draw(from: NSPoint(x: front - band, y: 0), to: NSPoint(x: front + band, y: 0),
                                      options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
                        return true
                    }
                    color = NSColor(patternImage: image)
                }
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, let placeholder else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = placeholderAlignment
            (placeholder as NSString).draw(in: NSRect(x: 0, y: textContainerInset.height, width: bounds.width, height: bounds.height),
                withAttributes: [.font: font ?? WorktreeTextEditor.font, .paragraphStyle: paragraph,
                                 .foregroundColor: NSColor(AngroveTheme.Colors.placeholderText)])
        }

        // Command-Return arrives as a key equivalent before ordinary key handling.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self, isCommandReturn(event) {
                (delegate as? Coordinator)?.commit()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func keyDown(with event: NSEvent) {
            if isCommandReturn(event) { (delegate as? Coordinator)?.commit(); return }
            super.keyDown(with: event)
        }

        // Focus, not the first edit, marks the field as being edited. Otherwise clicking into
        // an existing field and typing would be undone by the next update.
        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { (delegate as? Coordinator)?.parent.onBeginEditing() }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { (delegate as? Coordinator)?.parent.onEndEditing() }
            return resigned
        }

        override func mouseDown(with event: NSEvent) {
            if window?.firstResponder !== self { window?.makeFirstResponder(self) }
            super.mouseDown(with: event)
        }

        private func isCommandReturn(_ event: NSEvent) -> Bool {
            (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command)
        }
    }
}
