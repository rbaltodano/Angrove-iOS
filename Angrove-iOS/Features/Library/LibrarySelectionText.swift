import SwiftUI
import UIKit

/// A selectable reader paragraph that adds Ask and Clip to UIKit's native selection menu.
struct LibrarySelectionText: UIViewRepresentable {
    let text: AttributedString
    let onAsk: (String) -> Void
    let onClip: (String) -> Void
    let onOpenURL: (URL) -> Bool
    let textColor: Color
    let fontName: String
    let fontSize: CGFloat
    /// Which word of this paragraph a reading aloud has reached, so it can be filled in green.
    var speechState: AskingTextView.SpeechState = .none
    var speechChunkIndex = 0
    var sourceID = ""
    /// Starts reading aloud at the word the selection begins on (its position in this paragraph).
    var onReadFromHere: (Int) -> Void = { _ in }
    /// Reports where the word being said sits in this paragraph, or nil when none is.
    var onActiveWordRect: (CGRect?) -> Void = { _ in }

    func makeUIView(context: Context) -> AskingTextView {
        let view = AskingTextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.ask = { [weak coordinator = context.coordinator] selected in
            coordinator?.onAsk(selected)
        }
        view.clip = { [weak coordinator = context.coordinator] selected in
            coordinator?.onClip(selected)
        }
        view.readFrom = { [weak coordinator = context.coordinator] word in
            coordinator?.onReadFromHere(word)
        }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: AskingTextView, context: Context) {
        context.coordinator.onAsk = onAsk
        context.coordinator.onClip = onClip
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.onReadFromHere = onReadFromHere
        let font = UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let incoming = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: incoming.length)
        // Keep explicit verse/link typography while supplying the reader's body font.
        incoming.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil { incoming.addAttribute(.font, value: font, range: range) }
        }
        let paragraph = NSMutableParagraphStyle()
        // Match response rows: preserve natural font metrics and add the shared gap. A read word
        // lifts 2pt, so each line keeps 2pt of room for it and the spacing gives that back.
        paragraph.minimumLineHeight = ceil(font.lineHeight) + AskingTextView.liftHeight
        paragraph.lineSpacing = FlowLayout.rowSpacing - AskingTextView.liftHeight
        incoming.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
        var needsSpeechRestyle = false
        if !view.baseText.isEqual(to: incoming) {
            let selection = view.selectedRange
            view.attributedText = incoming
            view.baseText = incoming
            view.prepareSpeechTokens(sourceID: sourceID, chunkIndex: speechChunkIndex)
            if NSMaxRange(selection) <= incoming.length { view.selectedRange = selection }
            needsSpeechRestyle = true
        }
        let color = UIColor(textColor)
        if view.lastTextColor != color || needsSpeechRestyle {
            view.textColor = color
            view.lastTextColor = color
            needsSpeechRestyle = true
        }
        // UIKit's default link attributes override the attributed citation color.
        let linkColor = UIColor.angroveLinkGreen
        view.linkTextAttributes = [.foregroundColor: linkColor]
        view.tintColor = linkColor
        view.onActiveWordRect = onActiveWordRect
        view.applySpeech(speechState, force: needsSpeechRestyle)
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AskingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAsk: onAsk, onClip: onClip, onOpenURL: onOpenURL) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onAsk: (String) -> Void
        var onClip: (String) -> Void
        var onOpenURL: (URL) -> Bool
        var onReadFromHere: (Int) -> Void = { _ in }
        init(onAsk: @escaping (String) -> Void, onClip: @escaping (String) -> Void, onOpenURL: @escaping (URL) -> Bool) {
            self.onAsk = onAsk
            self.onClip = onClip
            self.onOpenURL = onOpenURL
        }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            onOpenURL(URL)
        }
    }
}

/// Matches the conversation word's 0.4-second transform transition.
struct LibraryWordLiftAnimation {
    let from: CGFloat
    let to: CGFloat
    let startedAt: CFTimeInterval
    static let duration: CFTimeInterval = 0.4
    private static let curve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.55, y: 0), endControlPoint: UnitPoint(x: 0.17, y: 1))

    func value(at time: CFTimeInterval) -> CGFloat {
        let fraction = min(1, max(0, (time - startedAt) / Self.duration))
        return from + (to - from) * CGFloat(Self.curve.value(at: fraction))
    }
}

final class AskingTextView: UITextView {
    /// How far a reading aloud has reached into this paragraph: words before `readBefore` are read
    /// and `active`, if any, is being said.
    struct SpeechState: Equatable {
        var readBefore = 0
        var active: Int?
        static let none = SpeechState()
    }

    /// Room left above each line for a lifted word.
    static let liftHeight: CGFloat = 2

    var ask: ((String) -> Void)?
    var clip: ((String) -> Void)?
    var readFrom: ((Int) -> Void)?
    var onActiveWordRect: ((CGRect?) -> Void)?
    /// The paragraph as supplied, before any reading styling.
    var baseText = NSAttributedString()
    var lastTextColor: UIColor?

    private var tokens: [LibrarySpeech.Token] = []
    private var chunkBase = 0
    private var appliedState = SpeechState.none
    private var speechLink: CADisplayLink?
    private var liftAnimations: [Int: LibraryWordLiftAnimation] = [:]

    private final class SpeechTarget: NSObject {
        weak var view: AskingTextView?
        init(_ view: AskingTextView) { self.view = view }
        @objc func tick(_ link: CADisplayLink) { view?.refreshActiveFill() }
    }

    deinit { speechLink?.invalidate() }

    func prepareSpeechTokens(sourceID: String, chunkIndex: Int) {
        tokens = LibrarySpeech.tokens(in: baseText.string, sourceID: sourceID)
        chunkBase = chunkIndex * LibrarySpeech.wordsPerChunk
        appliedState = .none
        liftAnimations = [:]
    }

    // MARK: Reading styling

    /// Fills words already read in accent green with a soft glow and a 2pt lift, and sweeps the
    /// word being said, as the conversation reader does.
    func applySpeech(_ state: SpeechState, force: Bool) {
        guard force || state != appliedState else { return }
        let now = CACurrentMediaTime()
        let previous = appliedState
        for token in tokens {
            let wasLifted = token.local < previous.readBefore || token.local == previous.active
            let isLifted = token.local < state.readBefore || token.local == state.active
            let from = liftAnimations[token.local]?.value(at: now) ?? (wasLifted ? Self.liftHeight : 0)
            let to: CGFloat = isLifted ? Self.liftHeight : 0
            if UIAccessibility.isReduceMotionEnabled {
                liftAnimations[token.local] = nil
            } else if wasLifted != isLifted {
                liftAnimations[token.local] = LibraryWordLiftAnimation(from: from, to: to, startedAt: now)
            }
        }
        let hadStyling = appliedState != .none || force
        appliedState = state
        if hadStyling {
            let selection = selectedRange
            attributedText = baseText
            if let lastTextColor { textColor = lastTextColor }
            if NSMaxRange(selection) <= textStorage.length { selectedRange = selection }
        }
        textStorage.beginEditing()
        for token in tokens where token.local < state.readBefore || token.local == state.active {
            textStorage.addAttributes(Self.readAttributes(color: greenColor), range: token.range)
        }
        for token in tokens {
            if let animation = liftAnimations[token.local] {
                textStorage.addAttribute(.baselineOffset, value: animation.value(at: now), range: token.range)
            }
        }
        textStorage.endEditing()
        if state.active != nil || !liftAnimations.isEmpty { startSpeechLink() }
        refreshActiveFill()
        if let active = state.active {
            if let token = tokens.first(where: { $0.local == active }) {
                layoutManager.ensureLayout(for: textContainer)
                let glyphs = layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
                reportActiveWordRect(layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer))
            }
        } else {
            if liftAnimations.isEmpty { stopSpeechLink() }
            reportActiveWordRect(nil)
        }
    }

    private func reportActiveWordRect(_ rect: CGRect?) {
        DispatchQueue.main.async { [weak self] in self?.onActiveWordRect?(rect) }
    }

    private var greenColor: UIColor {
        UIColor(AngroveTheme.Colors.accentGreen).resolvedColor(with: traitCollection)
    }

    private static func readAttributes(color: UIColor) -> [NSAttributedString.Key: Any] {
        let glow = NSShadow()
        glow.shadowColor = color.withAlphaComponent(0.5)
        glow.shadowBlurRadius = 4
        glow.shadowOffset = .zero
        return [.foregroundColor: color, .shadow: glow, .baselineOffset: liftHeight]
    }

    private func startSpeechLink() {
        guard speechLink == nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let link = CADisplayLink(target: SpeechTarget(self), selector: #selector(SpeechTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        speechLink = link
    }

    private func stopSpeechLink() {
        speechLink?.invalidate()
        speechLink = nil
    }

    /// Redraws the word being said with the green front at its current place.
    private func refreshActiveFill() {
        let now = CACurrentMediaTime()
        if !liftAnimations.isEmpty {
            textStorage.beginEditing()
            for token in tokens {
                guard let animation = liftAnimations[token.local], NSMaxRange(token.range) <= textStorage.length else { continue }
                textStorage.addAttribute(.baselineOffset, value: animation.value(at: now), range: token.range)
                if now - animation.startedAt >= LibraryWordLiftAnimation.duration {
                    liftAnimations[token.local] = nil
                }
            }
            textStorage.endEditing()
        }
        if appliedState.active == nil, liftAnimations.isEmpty { stopSpeechLink() }
        guard let active = appliedState.active,
              let token = tokens.first(where: { $0.local == active }),
              NSMaxRange(token.range) <= textStorage.length else { return }
        let progress = UIAccessibility.isReduceMotionEnabled
            ? 1 : CGFloat(ResponseSpeechPlayer.shared.progress(ofWord: chunkBase + active) ?? 0)
        textStorage.addAttribute(.foregroundColor, value: fillColor(for: token.range, progress: progress), range: token.range)
    }

    private func fillColor(for range: NSRange, progress: CGFloat) -> UIColor {
        let green = greenColor
        guard progress < 1, bounds.width > 0 else { return green }
        let base = (lastTextColor ?? .label).resolvedColor(with: traitCollection)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let band = max(rect.width * 0.4, 1)
        let front = rect.minX - band + (rect.width + 2 * band) * progress
        let image = UIGraphicsImageRenderer(size: CGSize(width: bounds.width, height: 1)).image { context in
            let colors = [green.cgColor, base.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: front - band + textContainerInset.left, y: 0),
                end: CGPoint(x: front + band + textContainerInset.left, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        return UIColor(patternImage: image)
    }


    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let selected = text(in: textRange)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selected.isEmpty else { return UIMenu(children: suggestedActions) }
        let askAction = UIAction(title: "Ask", image: UIImage(systemName: "arrow.turn.down.right")) { [weak self] _ in
            self?.ask?(selected)
        }
        let clipAction = UIAction(title: "Clip", image: UIImage(systemName: "bookmark")) { [weak self] _ in
            self?.clip?(selected)
        }
        var actions = [askAction, clipAction]
        // The word the selection starts on, or the next one when it starts between words.
        let start = offset(from: beginningOfDocument, to: textRange.start)
        if let word = tokens.first(where: { NSMaxRange($0.range) > start }) {
            actions.append(UIAction(title: "Read from here", image: UIImage(systemName: "speaker.wave.2")) { [weak self] _ in
                self?.readFrom?(word.local)
            })
        }
        return UIMenu(children: actions + suggestedActions)
    }
}
