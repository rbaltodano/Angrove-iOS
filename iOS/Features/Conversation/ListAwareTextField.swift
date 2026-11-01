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
    /// Question recall, for a swipe area around the field (see `RecallSwipeArea`).
    var shouldBeginRecall: (UIPanGestureRecognizer) -> Bool = { _ in false }
    var handleRecallPan: (UIPanGestureRecognizer) -> Void = { _ in }
    /// Which directions can recall right now: older (swipe right) and newer (swipe left).
    var recallDirections: () -> (older: Bool, newer: Bool) = { (false, false) }
}

/// A swipe area behind a question field, larger than the field, so recall swipes are easy to
/// start. Drags here drive the same recall as drags on the field; contact shows the hints.
struct RecallSwipeArea: UIViewRepresentable {
    let relay: TextInputRelay
    var onContactChange: (Bool) -> Void

    /// Marks the area so page-wide swipes leave its drags to recall.
    final class AreaView: UIView {}

    func makeUIView(context: Context) -> AreaView {
        let view = AreaView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let contact = TextFieldContactRecognizer()
        contact.cancelsTouchesInView = false
        contact.delaysTouchesBegan = false
        contact.delaysTouchesEnded = false
        contact.onContactChange = { [weak coordinator = context.coordinator] in coordinator?.parent.onContactChange($0) }
        view.addGestureRecognizer(contact)
        return view
    }

    func updateUIView(_ view: AreaView, context: Context) { context.coordinator.parent = self }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RecallSwipeArea
        init(parent: RecallSwipeArea) { self.parent = parent }

        @objc func pan(_ pan: UIPanGestureRecognizer) { parent.relay.handleRecallPan(pan) }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            return parent.relay.shouldBeginRecall(pan)
        }

        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other is TextFieldContactRecognizer || gesture is TextFieldContactRecognizer
        }
    }
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
    /// Dragging right (`true`) or left steps through earlier questions; returns the question to
    /// show, committed only if the drag completes, or nil to leave the field unchanged.
    var onSwipeRecall: ((Bool) -> QuestionRecallStep?)? = nil
    /// Recognized `#title` Insight mentions in a draft, colored like a command.
    var insightMentions: ((String) -> [InsightMention.Mention])? = nil
    /// Reports the recall slide starting and ending, so a SwiftUI placeholder can step aside.
    var onRecallSlideChange: ((Bool) -> Void)? = nil
    var placeholderColor: UIColor = .placeholderText
    /// Fits the live UIKit buffer up to the proposed width, then wraps.
    var hugsContentWidth: Bool = false
    /// Width reserved for the placeholder only while the live editor is empty.
    var minimumContentWidth: CGFloat = 0

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let tv = CommandHighlightTextView()
        tv.delegate = context.coordinator
        tv.mentionRanges = { [weak coordinator = context.coordinator] text in
            coordinator?.parent.insightMentions?(text).map(\.range) ?? []
        }
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
        if onSwipeRecall != nil {
            context.coordinator.recallTextView = tv
            relay?.shouldBeginRecall = { [weak coordinator = context.coordinator] pan in
                coordinator?.shouldBeginRecall(pan) ?? false
            }
            relay?.handleRecallPan = { [weak coordinator = context.coordinator] pan in
                coordinator?.handleRecallPan(pan)
            }
            relay?.recallDirections = { [weak coordinator = context.coordinator] in
                guard let parent = coordinator?.parent, !parent.isLocked else { return (false, false) }
                return (parent.onSwipeRecall?(true) != nil, parent.onSwipeRecall?(false) != nil)
            }
            tv.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: String(localized: "Previous question")) {
                    [weak coordinator = context.coordinator, weak tv] _ in
                    guard let tv else { return false }
                    return coordinator?.recall(older: true, in: tv) ?? false
                },
                UIAccessibilityCustomAction(name: String(localized: "Next question")) {
                    [weak coordinator = context.coordinator, weak tv] _ in
                    guard let tv else { return false }
                    return coordinator?.recall(older: false, in: tv) ?? false
                }
            ]
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
        context.coordinator.attachRecallPanIfNeeded()
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

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
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

        // MARK: - Question recall

        private var activeSlide: RecallSlide?

        weak var recallTextView: UITextView?
        private var recallPan: UIPanGestureRecognizer?

        /// The recall pan lives on the field's container: on the text view itself, a focused
        /// field's selection gestures hold it back until most of the drag is over.
        func attachRecallPanIfNeeded() {
            guard recallPan?.view == nil, let tv = recallTextView, let container = tv.superview else { return }
            let pan = recallPan ?? UIPanGestureRecognizer(target: self, action: #selector(handleRecallPan(_:)))
            pan.delegate = self
            container.addGestureRecognizer(pan)
            recallPan = pan
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, pan === recallPan else { return true }
            return shouldBeginRecall(pan)
        }

        /// Recall begins on a mostly horizontal drag toward a question that can be shown.
        func shouldBeginRecall(_ pan: UIPanGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: pan.view)
            guard activeSlide == nil, !parent.isLocked,
                  abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
            return parent.onSwipeRecall?(velocity.x > 0) != nil
        }

        /// A focused field's caret loupe starts on touch, before a drag can read as recall, so
        /// recall runs alongside the field's own gestures and cancels them once it begins.
        /// Recall never begins on a draft, which keeps native caret dragging and selection.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard gesture === recallPan, let container = gesture.view,
                  let otherView = other.view else { return false }
            return otherView.isDescendant(of: container)
        }

        /// While the field can recall (empty, or showing an unedited recalled question), its
        /// caret loupe and other holds wait to see whether a drag is recall, so the questions
        /// track the finger from the first point. Taps, and every gesture on a draft, are unchanged.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            guard gesture === recallPan, !(other is UITapGestureRecognizer),
                  let textView = recallTextView, let otherView = other.view,
                  otherView.isDescendant(of: textView) else { return false }
            return parent.onSwipeRecall?(true) != nil || parent.onSwipeRecall?(false) != nil
        }

        private func cancelTextInteractions(in tv: UITextView, except recall: UIGestureRecognizer) {
            var views: [UIView] = [tv]
            while let view = views.popLast() {
                // Contact tracking stays, so the swipe hints remain while the finger is down.
                for gesture in view.gestureRecognizers ?? []
                where gesture !== recall && gesture.isEnabled && !(gesture is TextFieldContactRecognizer) {
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                }
                views.append(contentsOf: view.subviews)
            }
        }

        /// Dragging right shows the previous question and left the next, tracking the finger.
        @objc func handleRecallPan(_ pan: UIPanGestureRecognizer) {
            guard let tv = recallTextView else { return }
            let dx = pan.translation(in: tv.superview).x
            switch pan.state {
            case .began:
                let older = pan.velocity(in: tv.superview).x > 0
                guard let step = parent.onSwipeRecall?(older) else { return }
                cancelTextInteractions(in: tv, except: pan)
                activeSlide = RecallSlide(coordinator: self, textView: tv, older: older, step: step)
                activeSlide?.track(dx)
            case .changed:
                activeSlide?.track(dx)
            case .ended:
                activeSlide?.release(dx: dx, velocity: pan.velocity(in: tv.superview).x)
                activeSlide = nil
            default:
                activeSlide?.release(dx: 0, velocity: 0)
                activeSlide = nil
            }
        }

        /// VoiceOver's Previous and Next question actions run the whole switch at once.
        @discardableResult
        func recall(older: Bool, in tv: UITextView) -> Bool {
            guard activeSlide == nil, !parent.isLocked,
                  let step = parent.onSwipeRecall?(older) else { return false }
            RecallSlide(coordinator: self, textView: tv, older: older, step: step).complete()
            return true
        }

        fileprivate func show(_ text: String, in tv: UITextView) {
            tv.text = text
            (tv as? CommandHighlightTextView)?.updateCommandHighlight(baseColor: parent.textColor)
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
            tv.invalidateIntrinsicContentSize()
            // Write through so an unfocused field isn't reset from the binding on the next update.
            flushText(tv)
            parent.onTextChange?(text)
        }

        /// A horizontal mask that fades content out over the last stretch of each edge.
        fileprivate static func edgeFade(for bounds: CGRect) -> CAGradientLayer {
            let fade = CAGradientLayer()
            fade.frame = bounds
            fade.startPoint = CGPoint(x: 0, y: 0.5)
            fade.endPoint = CGPoint(x: 1, y: 0.5)
            fade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
            fade.locations = edgeFadeLocations(for: bounds.width)
            return fade
        }

        fileprivate static func edgeFadeLocations(for width: CGFloat, fraction: CGFloat? = nil) -> [NSNumber] {
            let fraction = fraction ?? (width > 0 ? min(0.25, 28 / width) : 0.25)
            return [0, fraction, 1 - fraction, 1].map { NSNumber(value: Double($0)) }
        }
    }
}

/// The Study tool carousel's swap, driven by the finger: the old question moves with the drag
/// and fades, the recalled one arrives from the opposite side, and both fade out toward the
/// field's edges. Releasing past halfway, or with a flick, finishes on the carousel's spring;
/// otherwise the old question springs back.
@MainActor
private final class RecallSlide {
    private weak var coordinator: ListAwareTextField.Coordinator?
    private let textView: UITextView
    private let step: QuestionRecallStep
    private let originalText: String
    private let isAnimated = !UIAccessibility.isReduceMotionEnabled
    private var outgoing: UIView?
    private var clip: UIView?
    private var container: UIView?
    private var previousMask: CALayer?
    private var containerFade: CAGradientLayer?
    private var fadeTracker: EdgeFadeTracker?
    private var incomingPlaceholder: UILabel?
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    private var hasPlayedHaptic = false
    /// Signed distance a full switch moves: rightward for older questions.
    private var travel: CGFloat = 1
    private var progress: CGFloat = 0
    private let direction: CGFloat

    init(coordinator: ListAwareTextField.Coordinator, textView tv: UITextView, older: Bool, step: QuestionRecallStep) {
        self.coordinator = coordinator
        textView = tv
        self.step = step
        originalText = tv.text ?? ""
        direction = older ? 1 : -1
        haptic.prepare()
        guard isAnimated, let container = tv.superview, let window = tv.window else { return }
        let parent = coordinator.parent

        // Capture from the window so the SwiftUI placeholder leaves with the field.
        let outgoingRect = tv.convert(tv.bounds, to: window)
        let outgoing = UIImageView(image: UIGraphicsImageRenderer(bounds: outgoingRect).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        })
        // Host the outgoing question above the field so it keeps its place and width while the
        // field resizes for the recalled one.
        let host = container.superview ?? container
        let clip = UIView(frame: tv.convert(tv.bounds, to: host))
        clip.isUserInteractionEnabled = false
        clip.layer.mask = ListAwareTextField.Coordinator.edgeFade(for: clip.bounds)
        outgoing.frame = clip.bounds
        clip.addSubview(outgoing)
        host.addSubview(clip)
        previousMask = container.layer.mask
        let containerFade = ListAwareTextField.Coordinator.edgeFade(for: container.bounds)
        container.layer.mask = containerFade
        // The field resizes for the recalled question on SwiftUI's next layout pass.
        fadeTracker = EdgeFadeTracker(container: container, fade: containerFade)
        self.outgoing = outgoing
        self.clip = clip
        self.container = container
        self.containerFade = containerFade
        travel = direction * max(outgoing.bounds.width, 1)

        parent.onRecallSlideChange?(true)
        coordinator.show(step.text, in: tv)
        // The SwiftUI placeholder is hidden while sliding; carry a copy in with an empty field.
        if step.text.isEmpty {
            incomingPlaceholder = Self.placeholderLabel(for: parent, in: tv)
        }
        apply(progress: 0)
    }

    /// Moves both questions with the finger, 1:1.
    func track(_ dx: CGFloat) {
        guard outgoing != nil else { return }
        apply(progress: min(1, max(0, dx / travel)))
        if progress >= 0.5 { playHapticOnce() }
    }

    func release(dx: CGFloat, velocity: CGFloat) {
        let towardSwitch = velocity * direction
        let flicked = towardSwitch > 500 && dx * direction > 8
        let reversed = towardSwitch < -500
        let completes = outgoing != nil
            ? !reversed && (progress >= 0.5 || flicked)
            : abs(dx) > 40 && dx * direction > 0
        if completes {
            complete(velocity: velocity)
        } else {
            cancel(velocity: velocity)
        }
    }

    func complete(velocity: CGFloat = 0) {
        step.commit()
        playHapticOnce()
        // Without a slide (Reduce Motion), the question simply changes.
        guard outgoing != nil else {
            coordinator?.show(step.text, in: textView)
            return
        }
        // Clear the fade as the question settles so its edge letters don't pop in at the end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.clearFade()
        }
        animate(to: 1, velocity: velocity)
    }

    private func cancel(velocity: CGFloat) {
        guard outgoing != nil else { return }
        animate(to: 0, velocity: velocity) { [weak self] in
            guard let self else { return }
            self.coordinator?.show(self.originalText, in: self.textView)
        }
    }

    private func animate(to target: CGFloat, velocity: CGFloat, then: (() -> Void)? = nil) {
        let remaining = abs(travel) * abs(target - progress)
        let relativeVelocity = remaining > 1
            ? min(20, max(0, velocity * direction * (target > progress ? 1 : -1) / remaining))
            : 0
        // The text view's own transform is reset whenever SwiftUI resizes the field, so its
        // contents move by sublayer transform on a spring matching the UIKit one below.
        let spring = CASpringAnimation(perceptualDuration: 0.34, bounce: 0.18)
        spring.keyPath = "sublayerTransform.translation.x"
        spring.fromValue = incomingOffset(at: progress)
        spring.toValue = incomingOffset(at: target)
        spring.initialVelocity = relativeVelocity
        spring.duration = spring.settlingDuration
        textView.layer.add(spring, forKey: "questionRecallSlide")
        UIView.animate(
            springDuration: 0.34,
            bounce: 0.18,
            initialSpringVelocity: relativeVelocity,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.apply(progress: target)
        } completion: { _ in
            then?()
            self.finish()
        }
    }

    private func incomingOffset(at progress: CGFloat) -> CGFloat {
        -travel * (1 - progress)
    }

    private func apply(progress: CGFloat) {
        self.progress = progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textView.layer.sublayerTransform = CATransform3DMakeTranslation(incomingOffset(at: progress), 0, 0)
        CATransaction.commit()
        textView.alpha = progress
        outgoing?.transform = CGAffineTransform(translationX: travel * progress, y: 0)
        outgoing?.alpha = 1 - progress
    }

    private func clearFade() {
        guard let containerFade else { return }
        fadeTracker?.isClearing = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        containerFade.locations = ListAwareTextField.Coordinator.edgeFadeLocations(for: 0, fraction: 0)
        CATransaction.commit()
    }

    private func finish() {
        textView.layer.removeAnimation(forKey: "questionRecallSlide")
        textView.layer.sublayerTransform = CATransform3DIdentity
        textView.alpha = 1
        clip?.removeFromSuperview()
        incomingPlaceholder?.removeFromSuperview()
        fadeTracker?.stop()
        container?.layer.mask = previousMask
        coordinator?.parent.onRecallSlideChange?(false)
    }

    private func playHapticOnce() {
        guard !hasPlayedHaptic else { return }
        hasPlayedHaptic = true
        guard SettingsHaptics.isEnabled else { return }
        haptic.impactOccurred(intensity: 0.74)
    }

    private static func placeholderLabel(for parent: ListAwareTextField, in tv: UITextView) -> UILabel? {
        guard !parent.placeholder.isEmpty else { return nil }
        let label = UILabel()
        label.text = parent.placeholder
        label.font = parent.font
        label.textColor = parent.placeholderColor
        label.textAlignment = parent.textAlignment
        label.sizeToFit()
        let width = max(tv.bounds.width, label.bounds.width)
        let x: CGFloat = parent.textAlignment == .center ? (tv.bounds.width - width) / 2 : 0
        label.frame = CGRect(x: x, y: tv.bounds.height - label.bounds.height, width: width, height: label.bounds.height)
        label.autoresizingMask = [.flexibleTopMargin]
        tv.addSubview(label)
        return label
    }
}

/// Keeps a recall slide's edge fade matched to the field while SwiftUI resizes it.
private final class EdgeFadeTracker {
    private weak var container: UIView?
    private let fade: CAGradientLayer
    private var link: CADisplayLink?
    /// Once the fade is easing away, only its frame follows the field.
    var isClearing = false

    init(container: UIView, fade: CAGradientLayer) {
        self.container = container
        self.fade = fade
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        guard let container else { return stop() }
        guard fade.frame != container.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = container.bounds
        if !isClearing {
            fade.locations = ListAwareTextField.Coordinator.edgeFadeLocations(for: container.bounds.width)
        }
        CATransaction.commit()
    }

    func stop() {
        link?.invalidate()
        link = nil
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
    /// Finds recognized `#title` Insight mentions in the draft (see `InsightMention`).
    var mentionRanges: (String) -> [NSRange] = { _ in [] }
    /// When each mention, keyed by title and occurrence, was recognized; each sweeps once.
    private var mentionWaveStarts: [String: CFTimeInterval] = [:]
    private var currentMentions: [(key: String, range: NSRange)] = []
    private var mentionLink: CADisplayLink?

    /// Recognized mentions sweep green like a command, then stay green until the question is
    /// sent, when they become quotes.
    private func updateMentions(in draft: String) {
        let source = draft as NSString
        var occurrences: [String: Int] = [:]
        currentMentions = mentionRanges(draft).map { range in
            let title = source.substring(with: range).lowercased()
            occurrences[title, default: 0] += 1
            return ("\(title)#\(occurrences[title]!)", range)
        }
        let now = CACurrentMediaTime()
        let keys = Set(currentMentions.map(\.key))
        mentionWaveStarts = mentionWaveStarts.filter { keys.contains($0.key) }
        for mention in currentMentions where mentionWaveStarts[mention.key] == nil {
            mentionWaveStarts[mention.key] = UIAccessibility.isReduceMotionEnabled ? 0 : now
        }
        if mentionLink == nil, mentionWaveStarts.values.contains(where: { now - $0 < waveDuration }) {
            let link = CADisplayLink(target: WaveTarget(self), selector: #selector(WaveTarget.tickMention(_:)))
            link.add(to: .main, forMode: .common)
            mentionLink = link
        }
    }

    fileprivate func advanceMentions() {
        let now = CACurrentMediaTime()
        if !mentionWaveStarts.values.contains(where: { now - $0 < waveDuration }) {
            mentionLink?.invalidate()
            mentionLink = nil
        }
        applyCommandColor(progress: waveProgress)
    }

    private final class WaveTarget: NSObject {
        weak var textView: CommandHighlightTextView?
        init(_ textView: CommandHighlightTextView) { self.textView = textView }
        @objc func tick(_ link: CADisplayLink) { textView?.advanceCommandWave() }
        @objc func tickMention(_ link: CADisplayLink) {
            guard let textView else { return link.invalidate() }
            textView.advanceMentions()
        }
    }

    func updateCommandHighlight(baseColor: UIColor) {
        self.baseColor = baseColor
        guard !isPresentationSuspended else { return }
        // Leave marked text alone while an input method is composing it.
        guard markedTextRange == nil else { return }
        let draft = text ?? ""
        updateMentions(in: draft)
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
            let color = sweepColor(over: commandRange, progress: progress)
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
        applyMentionColor()
        // New keystrokes, including /rename arguments, begin in the normal color.
        var attributes = typingAttributes
        attributes[.foregroundColor] = baseColor
        typingAttributes = attributes
    }
}

private extension CommandHighlightTextView {
    /// Green trailing a moving front across `range`, with the normal text color ahead of it.
    func sweepColor(over range: NSRange, progress: CGFloat) -> UIColor {
        let green = UIColor(AngroveTheme.Colors.lightGreen).resolvedColor(with: traitCollection)
        guard progress < 1, bounds.width > 0, bounds.height > 0 else { return green }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
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
        return UIColor(patternImage: image)
    }

    func applyMentionColor() {
        let now = CACurrentMediaTime()
        for mention in currentMentions where NSMaxRange(mention.range) <= textStorage.length {
            let elapsed = now - (mentionWaveStarts[mention.key] ?? 0)
            let progress = CGFloat(min(1, elapsed / waveDuration))
            textStorage.addAttribute(
                .foregroundColor,
                value: sweepColor(over: mention.range, progress: progress),
                range: mention.range
            )
        }
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
final class TextFieldContactRecognizer: UIGestureRecognizer {
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
