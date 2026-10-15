import AppKit
import SwiftUI

/// A selectable reader paragraph that adds Ask, Clip and Read from Here to AppKit's
/// selection menu. It mirrors the iPhone's `LibrarySelectionText` interface.
struct LibrarySelectionText: NSViewRepresentable {
    let text: AttributedString
    let onAsk: (String) -> Void
    let onClip: (String) -> Void
    let onOpenURL: (URL) -> Bool
    let textColor: Color
    let fontName: String
    let fontSize: CGFloat
    var speechState: LibrarySpeechState = .none
    var speechChunkIndex = 0
    var sourceID = ""
    var onReadFromHere: (Int) -> Void = { _ in }
    var onActiveWordRect: (CGRect?) -> Void = { _ in }

    func makeNSView(context: Context) -> MacAskingTextView {
        let view = MacAskingTextView()
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: MacAskingTextView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        view.ask = onAsk
        view.clip = onClip
        view.readFrom = onReadFromHere
        view.onActiveWordRect = onActiveWordRect
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let incoming = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: incoming.length)
        incoming.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil { incoming.addAttribute(.font, value: font, range: range) }
        }
        let color = NSColor(textColor)
        incoming.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil { incoming.addAttribute(.foregroundColor, value: color, range: range) }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ceil(font.ascender - font.descender + font.leading)
        paragraph.lineSpacing = FlowLayout.rowSpacing
        incoming.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
        view.linkTextAttributes = [.foregroundColor: NSColor(AngroveTheme.Colors.lightGreen), .cursor: NSCursor.pointingHand]
        view.selectedTextAttributes = [.backgroundColor: NSColor(AngroveTheme.Colors.wordHighlight)]
        view.update(text: incoming, sourceID: sourceID, chunkIndex: speechChunkIndex, speech: speechState)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MacAskingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onOpenURL: onOpenURL) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpenURL: (URL) -> Bool
        init(onOpenURL: @escaping (URL) -> Bool) { self.onOpenURL = onOpenURL }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL { return onOpenURL(url) }
            if let string = link as? String, let url = URL(string: string) { return onOpenURL(url) }
            return false
        }
    }
}

final class MacAskingTextView: NSTextView {
    var ask: (String) -> Void = { _ in }
    var clip: (String) -> Void = { _ in }
    var readFrom: (Int) -> Void = { _ in }
    var onActiveWordRect: (CGRect?) -> Void = { _ in }
    private var baseText = NSAttributedString()
    private var tokens: [LibrarySpeech.Token] = []
    private var appliedSpeech = LibrarySpeechState.none

    override var isFlipped: Bool { true }

    func update(text: NSAttributedString, sourceID: String, chunkIndex: Int, speech: LibrarySpeechState) {
        let textChanged = !baseText.isEqual(to: text)
        if textChanged {
            baseText = text
            tokens = LibrarySpeech.tokens(in: text.string, sourceID: sourceID)
        }
        guard textChanged || speech != appliedSpeech else { return }
        appliedSpeech = speech
        let selection = selectedRange()
        let styled = NSMutableAttributedString(attributedString: baseText)
        // Words already read fill in accent green, as the conversation reader does.
        let green = NSColor(AngroveTheme.Colors.lightGreen)
        for token in tokens where token.local < speech.readBefore || token.local == speech.active {
            styled.addAttribute(.foregroundColor, value: green, range: token.range)
        }
        textStorage?.setAttributedString(styled)
        if NSMaxRange(selection) <= styled.length { setSelectedRange(selection) }
        invalidateIntrinsicContentSize()
        reportActiveWord(speech.active)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return 0 }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

    private func reportActiveWord(_ active: Int?) {
        guard let active, let token = tokens.first(where: { $0.local == active }),
              let container = textContainer, let layout = layoutManager else {
            DispatchQueue.main.async { [weak self] in self?.onActiveWordRect(nil) }
            return
        }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        DispatchQueue.main.async { [weak self] in self?.onActiveWordRect(rect) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard range.length > 0, !selected.isEmpty else { return menu }
        var items = [
            MacLibraryMenuItem(title: "Ask", symbol: "arrow.turn.down.right") { [weak self] in self?.ask(selected) },
            MacLibraryMenuItem(title: "Clip", symbol: "bookmark") { [weak self] in self?.clip(selected) },
        ]
        if let word = tokens.first(where: { NSMaxRange($0.range) > range.location }) {
            items.append(MacLibraryMenuItem(title: "Read from Here", symbol: "speaker.wave.2") { [weak self] in
                self?.readFrom(word.local)
            })
        }
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        menu.insertItem(.separator(), at: items.count)
        return menu
    }
}

private final class MacLibraryMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @objc private func run() { handler() }
}
