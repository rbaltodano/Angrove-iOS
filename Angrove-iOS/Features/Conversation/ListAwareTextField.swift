//
//  ListAwareTextField.swift
//  Angrove-iOS
//
//  Created by Ryan on 5/25/26.
//

import Foundation
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The shell is fading out the thread; keep its current presentation stable until removal.
    @Entry var isConversationPageDeparting = false
}

// MARK: - TextInputRelay

/// A lightweight reference-type bridge that lets submit logic synchronously read
/// the UITextView's current text without requiring per-keystroke binding writes.
/// Assign a `TextInputRelay` instance to `ListAwareTextField.relay`; call
/// `relay.currentText()` just before submitting to get the latest typed value.
final class TextInputRelay {
    var currentText: () -> String = { "" }
    /// Replaces the entire buffer (e.g. inserting a picked slash command) and moves
    /// the caret to the end, without blurring the field. Callers are responsible for
    /// any follow-up state updates (placeholder emptiness, text-change bubbling).
    var replaceAll: (String) -> Void = { _ in }
    /// Moves keyboard focus into the underlying text view.
    var focus: () -> Void = {}
}

// MARK: - ListAwareTextField

/// A UITextView-backed text input that:
/// 1. Does NOT write to the SwiftUI binding on every keystroke — text stays in the
///    UITextView's own buffer, so `onChange(of: activeBranches)` never fires while
///    typing (eliminating the primary source of typing lag).
/// 2. Intercepts the Return key (via UITextViewDelegate.shouldChangeTextIn) to
///    submit when `onSubmit` is provided, otherwise auto-continue ordered lists
///    ("1. ") and unordered lists ("- ") at UIKit speed, with zero SwiftUI overhead.
/// 3. Flushes text → binding when `submitTrigger` increments (the dock arrow button).
/// 4. Flushes text → binding on blur (textViewDidEndEditing).
struct ListAwareTextField: UIViewRepresentable {
    @Environment(\.isConversationPageDeparting) private var isPageDeparting

    // MARK: - Public API

    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = UIFont(name: "LibreBaskerville-Regular", size: 16) ?? .systemFont(ofSize: 16)
    var lineHeight: CGFloat? = nil
    var isLocked: Bool = false
    var textColor: UIColor = .angrovePrimaryReadable
    var textAlignment: NSTextAlignment = .natural
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Observes finger contact without taking over text editing gestures.
    var onPressChange: ((Bool) -> Void)? = nil
    /// Optional relay that exposes the UITextView's live text for synchronous
    /// reads at submit time (avoids per-keystroke binding writes).
    var relay: TextInputRelay? = nil
    /// Called every time the text changes (for placeholder visibility etc.).
    var onTextChange: ((String) -> Void)? = nil
    /// Called when Return should submit the current question instead of inserting a newline.
    var onSubmit: (() -> Void)? = nil
    /// Fits the live UIKit buffer up to the proposed width, then wraps.
    var hugsContentWidth: Bool = false
    /// Width reserved for the placeholder only while the live editor is empty.
    var minimumContentWidth: CGFloat = 0

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let tv = CommandHighlightTextView()
        tv.delegate = context.coordinator
        tv.isEditable = !isLocked
        tv.isSelectable = true
        if onPressChange != nil {
            let press = TextFieldContactRecognizer()
            press.cancelsTouchesInView = false
            press.delaysTouchesBegan = false
            press.delaysTouchesEnded = false
            press.onContactChange = { [weak coordinator = context.coordinator] isPressed in
                coordinator?.parent.onPressChange?(isPressed)
            }
            tv.addGestureRecognizer(press)
        }
        tv.font = font
        tv.textColor = textColor
        tv.tintColor = textColor
        tv.textAlignment = textAlignment
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.returnKeyType = onSubmit == nil ? .default : .send
        tv.typingAttributes = makeTypingAttributes()
        tv.attributedText = NSAttributedString(
            string: text,
            attributes: makeTypingAttributes()
        )
        // Allow SwiftUI to compress the view horizontally — without this the
        // UITextView demands its ideal (unbounded) width and stretches the layout.
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        relay?.currentText = { [weak tv] in tv?.text ?? "" }
        relay?.replaceAll = { [weak tv] newText in
            guard let tv else { return }
            tv.text = newText
            tv.updateCommandHighlight(baseColor: textColor)
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
            tv.invalidateIntrinsicContentSize()
        }
        relay?.focus = { [weak tv] in
            guard let tv else { return }
            tv.becomeFirstResponder()
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
        }
        tv.updateCommandHighlight(baseColor: textColor)
        return tv
    }

    private func makeTypingAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        } else {
            style.lineSpacing = font.lineHeight * 0.2
        }
        style.alignment = textAlignment
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
    }

    /// Tell SwiftUI exactly how tall the view needs to be for the available width.
    /// Without this, SwiftUI never constrains the width and the text never wraps.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        var width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        if hugsContentWidth {
            width = Self.contentWidth(
                for: uiView.attributedText ?? NSAttributedString(string: ""),
                availableWidth: width,
                minimumWidth: minimumContentWidth,
                caretWidth: isLocked ? 0 : 2
            )
        }
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fittingSize.height, uiView.font?.lineHeight ?? 20))
    }

    /// Measure without wrapping first so a growing draft reaches its maximum width
    /// before adding lines. Read the text view's buffer, not the deferred binding.
    static func contentWidth(
        for text: NSAttributedString,
        availableWidth: CGFloat,
        minimumWidth: CGFloat,
        caretWidth: CGFloat
    ) -> CGFloat {
        let naturalWidth = text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width
        let emptyWidth = text.length == 0 ? minimumWidth : 0
        return min(availableWidth, max(1, emptyWidth, ceil(naturalWidth) + caretWidth))
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Keep coordinator's parent reference current every render.
        context.coordinator.parent = self
        (uiView as? CommandHighlightTextView)?.isPresentationSuspended = isPageDeparting
        // Do not invalidate text layout while the shell animates the whole page away.
        guard !isPageDeparting else { return }

        // Always safe to update visual properties
        if uiView.font != font { uiView.font = font }
        if uiView.tintColor != textColor { uiView.tintColor = textColor }
        if uiView.backgroundColor != .clear { uiView.backgroundColor = .clear }
        if uiView.textAlignment != textAlignment {
            UIView.transition(
                with: uiView,
                duration: 0.18,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                uiView.textAlignment = textAlignment
            }
        }
        if uiView.isEditable == isLocked {
            uiView.isEditable   = !isLocked
        }
        // Submitted questions remain read-only, but native selection and Copy stay available.
        uiView.isSelectable = true
        var attributes = makeTypingAttributes()
        attributes.removeValue(forKey: .foregroundColor)
        if !isLocked {
            uiView.typingAttributes = attributes
        }
        if uiView.textStorage.length > 0 {
            let fullRange = NSRange(location: 0, length: uiView.textStorage.length)
            uiView.textStorage.addAttributes(attributes, range: fullRange)
        }
        let returnKeyType: UIReturnKeyType = onSubmit == nil ? .default : .send
        if uiView.returnKeyType != returnKeyType {
            uiView.returnKeyType = returnKeyType
            uiView.reloadInputViews()
        }

        // Sync binding → UITextView only when NOT focused.
        // While focused the UITextView is authoritative (textViewDidChange
        // writes every keystroke to the binding directly).
        if !uiView.isFirstResponder {
            let bindingText = text
            if (uiView.text ?? "") != bindingText {
                if bindingText.isEmpty {
                    uiView.text = ""
                } else {
                    uiView.attributedText = NSAttributedString(string: bindingText, attributes: makeTypingAttributes())
                }
            }
        }
        // Refresh relay so it always points at the live UITextView.
        relay?.currentText = { [weak uiView] in uiView?.text ?? "" }
        relay?.replaceAll = { [weak uiView] newText in
            guard let uiView else { return }
            uiView.text = newText
            (uiView as? CommandHighlightTextView)?.updateCommandHighlight(baseColor: textColor)
            let end = uiView.endOfDocument
            uiView.selectedTextRange = uiView.textRange(from: end, to: end)
            uiView.invalidateIntrinsicContentSize()
        }
        (uiView as? CommandHighlightTextView)?.updateCommandHighlight(baseColor: textColor)
        relay?.focus = { [weak uiView] in
            guard let uiView else { return }
            uiView.becomeFirstResponder()
            let end = uiView.endOfDocument
            uiView.selectedTextRange = uiView.textRange(from: end, to: end)
        }
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        (uiView as? CommandHighlightTextView)?.stopCommandWave()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ListAwareTextField

        // Compiled once per Coordinator instance (effectively once per field lifetime)
        private let orderedListPattern  = try! NSRegularExpression(pattern: #"^(\d+)\.\s+\S"#)
        private let orderedEmptyPattern = try! NSRegularExpression(pattern: #"^(\d+)\.\s*$"#)
        private let unorderedListPattern  = try! NSRegularExpression(pattern: #"^-\s+\S"#)
        private let unorderedEmptyPattern = try! NSRegularExpression(pattern: #"^-\s*$"#)

        init(parent: ListAwareTextField) {
            self.parent = parent
        }

        // MARK: - Return-key list interception

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            if let onSubmit = parent.onSubmit, !parent.isLocked {
                flushText(tv)
                parent.onTextChange?(tv.text ?? "")
                onSubmit()
                return false
            }
            guard let fullText = tv.text else { return true }

            let nsText = fullText as NSString
            let cursorPos = range.location

            // Find the current line (from its start up to the cursor)
            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            let lineEnd = min(cursorPos, lineRange.location + lineRange.length)
            let currentLine = nsText.substring(with: NSRange(location: lineRange.location,
                                                              length: lineEnd - lineRange.location))

            let fullRange = NSRange(currentLine.startIndex..., in: currentLine)

            // ── Ordered list ──────────────────────────────────────────────────
            if let m = orderedListPattern.firstMatch(in: currentLine, range: fullRange),
               let numRange = Range(m.range(at: 1), in: currentLine),
               let num = Int(currentLine[numRange]) {
                let insertion = "\n\(num + 1). "
                insertText(tv, in: range, text: insertion)
                return false
            }

            // ── Ordered empty item (exit list) ────────────────────────────────
            if orderedEmptyPattern.firstMatch(in: currentLine, range: fullRange) != nil {
                // Strip "N. " from the current line up to cursor, insert plain newline
                let strippedPrefixLen = lineEnd - lineRange.location
                let stripRange = NSRange(location: lineRange.location, length: strippedPrefixLen)
                replaceText(tv, in: stripRange, with: "")
                return false
            }

            // ── Unordered list ────────────────────────────────────────────────
            if unorderedListPattern.firstMatch(in: currentLine, range: fullRange) != nil {
                insertText(tv, in: range, text: "\n- ")
                return false
            }

            // ── Unordered empty item (exit list) ──────────────────────────────
            if unorderedEmptyPattern.firstMatch(in: currentLine, range: fullRange) != nil {
                let stripRange = NSRange(location: lineRange.location, length: lineEnd - lineRange.location)
                replaceText(tv, in: stripRange, with: "\n")
                return false
            }

            return true
        }

        // MARK: - Helpers

        private func insertText(_ tv: UITextView, in range: NSRange, text: String) {
            guard let textRange = tv.textRange(from: range, in: tv) else {
                // Fallback: just append
                tv.insertText(text)
                return
            }
            tv.replace(textRange, withText: text)
            notifyChange(tv)
        }

        private func replaceText(_ tv: UITextView, in range: NSRange, with text: String) {
            guard let textRange = tv.textRange(from: range, in: tv) else { return }
            tv.replace(textRange, withText: text)
            notifyChange(tv)
        }

        private func notifyChange(_ tv: UITextView) {
            (tv as? CommandHighlightTextView)?.updateCommandHighlight(baseColor: parent.textColor)
            parent.onTextChange?(tv.text ?? "")
        }

        // MARK: - UITextViewDelegate

        func textViewDidChange(_ tv: UITextView) {
            (tv as? CommandHighlightTextView)?.updateCommandHighlight(baseColor: parent.textColor)
            let current = tv.text ?? ""
            // Do NOT write to parent.text here — doing so mutates activeBranches on
            // every keystroke, which triggers an ActiveInquiryView re-render, which
            // re-creates every StreamingMessageView (parseSegments + regex) per character.
            // Text is flushed to the binding in textViewDidEndEditing (blur) and via
            // the relay at submit time, so nothing is lost.
            parent.onTextChange?(current)
            // Invalidate SwiftUI's size cache so sizeThatFits is re-evaluated
            // and the view grows/shrinks vertically as lines wrap.
            tv.invalidateIntrinsicContentSize()
        }

        func textViewShouldEndEditing(_ tv: UITextView) -> Bool {
            flushText(tv)
            return true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            // Flush once when focus leaves, then re-sync placeholder visibility with
            // the final UIKit buffer in case no change event fired during blur.
            flushText(tv)
            parent.onTextChange?(tv.text ?? "")
            parent.onFocusChange(false)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.onFocusChange(true)
        }

        private func flushText(_ tv: UITextView) {
            parent.text = tv.text ?? ""
        }
    }
}

// MARK: - One-shot command color wave

/// Animates inside the live editor without duplicating text or moving the cursor.
/// A soft green front sweeps once across the command, leaving solid green behind.
final class CommandHighlightTextView: UITextView {
    var isPresentationSuspended = false {
        didSet {
            if isPresentationSuspended { stopCommandWave() }
        }
    }
    private var command: String?
    private var commandRange: NSRange?
    private var baseColor: UIColor = .angrovePrimaryReadable
    private var waveStart: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var fadeStart: CFTimeInterval?
    private var fadeRange: NSRange?
    private var fadeColor: UIColor?
    private var lastCommandColor: UIColor?
    private let fadeDuration: CFTimeInterval = 0.3
    private let waveDuration: CFTimeInterval = 1.0 // Matches ThinkingShimmer's sweep.

    private final class WaveTarget: NSObject {
        weak var textView: CommandHighlightTextView?
        init(_ textView: CommandHighlightTextView) { self.textView = textView }
        @objc func tick(_ link: CADisplayLink) { textView?.advanceCommandWave() }
    }

    func updateCommandHighlight(baseColor: UIColor) {
        self.baseColor = baseColor
        guard !isPresentationSuspended else { return }
        // Leave marked text alone while an input method is composing it.
        guard markedTextRange == nil else { return }
        let draft = text ?? ""
        let token = draft.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let nextCommand = SlashCommand.invocation(for: draft) == nil ? nil : token?.lowercased()
        let previousRange = commandRange
        let previousColor = lastCommandColor
        if nextCommand != command {
            let wasRecognized = command != nil
            stopCommandWave()
            command = nextCommand
            if !UIAccessibility.isReduceMotionEnabled {
                if nextCommand != nil {
                    waveStart = CACurrentMediaTime()
                } else if wasRecognized, let token, let previousRange, let previousColor {
                    fadeStart = CACurrentMediaTime()
                    fadeRange = NSRange(
                        location: (draft as NSString).range(of: token).location,
                        length: min(previousRange.length, (token as NSString).length)
                    )
                    fadeColor = previousColor
                }
                if waveStart != nil || fadeStart != nil {
                    let link = CADisplayLink(target: WaveTarget(self), selector: #selector(WaveTarget.tick(_:)))
                    link.add(to: .main, forMode: .common)
                    displayLink = link
                }
            }
        }
        commandRange = nextCommand != nil ? token.map { (draft as NSString).range(of: $0) } : nil
        // Keep a fade bounded to the remaining token while the user continues editing.
        // Do not restart it on each keystroke or color newly appended invalid characters.
        if let currentFadeRange = fadeRange {
            if let token {
                fadeRange = NSRange(
                    location: (draft as NSString).range(of: token).location,
                    length: min(currentFadeRange.length, (token as NSString).length)
                )
            } else {
                stopCommandWave()
            }
        }
        advanceCommandWave()
    }

    func stopCommandWave() {
        displayLink?.invalidate()
        displayLink = nil
        waveStart = nil
        fadeStart = nil
        fadeRange = nil
        fadeColor = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyCommandColor(progress: waveProgress)
    }

    private var waveProgress: CGFloat {
        guard let waveStart else { return 1 }
        return CGFloat(min(1, (CACurrentMediaTime() - waveStart) / waveDuration))
    }

    private func advanceCommandWave() {
        let progress = UIAccessibility.isReduceMotionEnabled ? 1 : waveProgress
        if UIAccessibility.isReduceMotionEnabled {
            stopCommandWave()
        } else if let fadeStart {
            if CACurrentMediaTime() - fadeStart >= fadeDuration { stopCommandWave() }
        } else if progress >= 1 {
            stopCommandWave()
        }
        applyCommandColor(progress: progress)
    }

    private func applyCommandColor(progress: CGFloat) {
        guard !isPresentationSuspended, markedTextRange == nil else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        if let commandRange, NSMaxRange(commandRange) <= textStorage.length {
            let green = UIColor(AngroveTheme.Colors.accentGreen).resolvedColor(with: traitCollection)
            var color = green
            if progress < 1, bounds.width > 0, bounds.height > 0 {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: commandRange, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                // Green trails the moving front; the normal text color lies ahead.
                let band = max(rect.width * 0.4, 1)
                let front = rect.minX - band + (rect.width + 2 * band) * progress
                // The gradient is horizontal, so a one-point strip tiles vertically
                // without allocating a full bitmap for a tall pasted draft.
                let image = UIGraphicsImageRenderer(size: CGSize(width: bounds.width, height: 1)).image { context in
                    let colors = [green.cgColor, baseColor.resolvedColor(with: traitCollection).cgColor] as CFArray
                    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
                    context.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: front - band + textContainerInset.left, y: 0),
                        end: CGPoint(x: front + band + textContainerInset.left, y: 0),
                        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                    )
                }
                color = UIColor(patternImage: image)
            }
            lastCommandColor = color
            textStorage.addAttribute(.foregroundColor, value: color, range: commandRange)
        } else if let fadeStart, let fadeRange, let fadeColor,
                  NSMaxRange(fadeRange) <= textStorage.length {
            let elapsed = CGFloat(min(1, (CACurrentMediaTime() - fadeStart) / fadeDuration))
            let eased = elapsed * elapsed * (3 - 2 * elapsed)
            // Crossfade the last displayed color, including a partially completed gradient.
            // Only color attributes change; text, layout, selection, and typing stay intact.
            let image = UIGraphicsImageRenderer(size: CGSize(width: max(bounds.width, 1), height: 1)).image { context in
                let rect = CGRect(x: 0, y: 0, width: max(bounds.width, 1), height: 1)
                baseColor.resolvedColor(with: traitCollection).setFill()
                context.cgContext.fill(rect)
                context.cgContext.setAlpha(1 - eased)
                fadeColor.setFill()
                context.cgContext.fill(rect)
            }
            textStorage.addAttribute(.foregroundColor, value: UIColor(patternImage: image), range: fadeRange)
        } else {
            lastCommandColor = nil
        }
        // New keystrokes, including /rename arguments, begin in the normal color.
        var attributes = typingAttributes
        attributes[.foregroundColor] = baseColor
        typingAttributes = attributes
    }
}

// MARK: - Convenience extensions for Angrove types

extension ConversationFontOption {
    var uiFont: UIFont {
        uiFont(size: .large)
    }

    func uiFont(size: ConversationFontSizeOption) -> UIFont {
        uiFont(pointSize: size.pointSize)
    }

    func uiFont(pointSize: CGFloat) -> UIFont {
        switch self {
        case .serif:
            return UIFont(name: "LibreBaskerville-Regular", size: pointSize) ?? .systemFont(ofSize: pointSize)
        case .sans:
            return UIFont(name: "Figtree-Regular", size: pointSize) ?? .systemFont(ofSize: pointSize)
        }
    }
}

extension InputTextAlignmentOption {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .center: return .center
        case .left:   return .natural
        }
    }
}

// MARK: - NSRange ↔ UITextRange helper

private extension UITextView {
    /// Converts an NSRange in the text view's string to a UITextRange.
    func textRange(from nsRange: NSRange, in textView: UITextView) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
              let end   = textView.position(from: start, offset: nsRange.length) else { return nil }
        return textView.textRange(from: start, to: end)
    }
}

/// Tracks contact for visual feedback while allowing caret, selection, and scrolling gestures.
private final class TextFieldContactRecognizer: UIGestureRecognizer {
    var onContactChange: ((Bool) -> Void)?
    private var contacts: Set<UITouch> = []

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let wasEmpty = contacts.isEmpty
        contacts.formUnion(touches)
        state = wasEmpty ? .began : .changed
        if wasEmpty { onContactChange?(true) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        contacts.subtract(touches)
        if contacts.isEmpty {
            onContactChange?(false)
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        contacts.removeAll()
        onContactChange?(false)
        state = .cancelled
    }

    override func reset() {
        super.reset()
        if !contacts.isEmpty { onContactChange?(false) }
        contacts.removeAll()
    }
}
