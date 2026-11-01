//
//  SpokenWordHighlight.swift
//  Angrove-iOS
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension View {
    /// Fills the word in accent green, left to right, while it is being read aloud. `fill` is the
    /// same text as the word, drawn in green over it.
    func spokenWordFill(index: Int, speechText: String, fill: Text) -> some View {
        modifier(SpokenWordFill(index: index, speechText: speechText, fill: fill))
    }

    /// Raises a word 2pt once it has been, or is being, read aloud.
    func spokenWordLift(index: Int, speechText: String) -> some View {
        modifier(SpokenWordLift(index: index, speechText: speechText))
    }

    /// While the response is read aloud, pressing and holding the whole response grows it slightly
    /// and dragging scrubs playback. Resumes from the start of the word the fill is on.
    func speechScrubbable(speechText: String) -> some View {
        modifier(SpeechScrubGesture(speechText: speechText))
    }
}

/// Words behind the cursor stay green when true, like the played part of a progress bar.
private let retainsReadWords = true

/// An 8pt blur (a SwiftUI radius of 4) in the accent green, centered on the text.
private struct GreenGlow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: AngroveTheme.Colors.lightGreen.opacity(0.5), radius: 4, x: 0, y: 0)
    }
}

private struct SpokenWordFill: ViewModifier {
    let index: Int
    let speechText: String
    let fill: Text

    private var speech = ResponseSpeechPlayer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(index: Int, speechText: String, fill: Text) {
        self.index = index
        self.speechText = speechText
        self.fill = fill
    }

    /// A word already read, shown in solid green.
    private var isRetained: Bool {
        guard retainsReadWords, !speechText.isEmpty, speech.activeText == speechText,
              let active = speech.activeWord else { return false }
        return index < active
    }

    func body(content: Content) -> some View {
        // The word's own brown is hidden once it is green, so its edges don't tint the green.
        content
            .opacity(isRetained ? 0 : 1)
            .overlay { overlay }
    }

    @ViewBuilder
    private var overlay: some View {
        if !speechText.isEmpty, speech.activeText == speechText, let active = speech.activeWord {
            if index == active {
                TimelineView(.animation) { _ in
                    wipe(progress: reduceMotion ? 1 : speech.progress(ofWord: index) ?? 0)
                }
            } else if isRetained {
                fill.foregroundColor(AngroveTheme.Colors.lightGreen).modifier(GreenGlow())
            }
        }
    }

    /// A soft green front sweeping left to right, with solid green behind it.
    private func wipe(progress: Double) -> some View {
        let soft = 0.3
        let front = progress * (1 + soft) - soft
        let start = min(max(front, 0), 1)
        let end = max(min(front + soft, 1), start + 0.0001)
        return fill
            .foregroundColor(AngroveTheme.Colors.lightGreen)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: AngroveTheme.Colors.mask, location: start),
                        .init(color: .clear, location: end),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .modifier(GreenGlow())
            .opacity(progress > 0 ? 1 : 0)
    }
}

private struct SpeechScrubGesture: ViewModifier {
    let speechText: String

    private var speech = ResponseSpeechPlayer.shared

    init(speechText: String) {
        self.speechText = speechText
    }

    private var isReadingThis: Bool {
        !speechText.isEmpty && speech.activeText == speechText
    }

    func body(content: Content) -> some View {
        let isScaled = isReadingThis && speech.isScrubbing
        content
            .scaleEffect(isScaled ? 1.05 : 1)
            .animation(.springLively, value: isScaled)
            .background {
                SpeechScrubRecognizer(isEnabled: isReadingThis && speech.phase == .speaking)
            }
    }
}

/// A UIKit long press on the enclosing scroll view, limited to the modified view's frame. SwiftUI
/// gestures cannot hand a still finger to scrubbing while still yielding to scrolling the moment
/// the finger moves; the system recognizer does both, and once it begins the scroll view's pan
/// cannot.
#if os(iOS)
private struct SpeechScrubRecognizer: UIViewRepresentable {
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.host = view
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: HostView, coordinator: Coordinator) {
        view.detach()
    }

    final class HostView: UIView {
        weak var coordinator: Coordinator?
        private weak var attachedTo: UIView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard window != nil, let coordinator else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            let target = ancestor ?? window
            target?.addGestureRecognizer(coordinator.recognizer)
            attachedTo = target
        }

        func detach() {
            if let coordinator { attachedTo?.removeGestureRecognizer(coordinator.recognizer) }
            attachedTo = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var host: HostView?
        var isEnabled = false
        private var startX: CGFloat = 0
        private let speech = ResponseSpeechPlayer.shared
        lazy var recognizer: UILongPressGestureRecognizer = {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.minimumPressDuration = 0.3
            recognizer.allowableMovement = 10
            recognizer.delegate = self
            return recognizer
        }()

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let host, host.window != nil else { return false }
            return host.bounds.contains(gestureRecognizer.location(in: host))
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            let x = recognizer.location(in: nil).x
            switch recognizer.state {
            case .began:
                startX = x
                speech.beginScrub()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .changed:
                speech.updateScrub(translation: x - startX)
            case .ended, .cancelled, .failed:
                speech.endScrub()
            default:
                break
            }
        }
    }
}

#else
private struct SpeechScrubRecognizer: NSViewRepresentable {
    let isEnabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.coordinator = context.coordinator
        context.coordinator.host = view
        return view
    }
    func updateNSView(_ view: HostView, context: Context) { context.coordinator.isEnabled = isEnabled }
    static func dismantleNSView(_ view: HostView, coordinator: Coordinator) { view.detach() }
    final class HostView: NSView {
        weak var coordinator: Coordinator?
        private weak var attachedTo: NSView?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil, let coordinator else { return }
            var ancestor = superview
            while let view = ancestor, !(view is NSScrollView) { ancestor = view.superview }
            let target = ancestor ?? window?.contentView
            target?.addGestureRecognizer(coordinator.recognizer)
            attachedTo = target
        }
        func detach() {
            if let coordinator { attachedTo?.removeGestureRecognizer(coordinator.recognizer) }
            attachedTo = nil
        }
    }
    @MainActor final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        weak var host: HostView?
        var isEnabled = false
        private var startX: CGFloat = 0
        private let speech = ResponseSpeechPlayer.shared
        lazy var recognizer: NSPressGestureRecognizer = {
            let recognizer = NSPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.minimumPressDuration = 0.3
            recognizer.allowableMovement = 10
            recognizer.delegate = self
            return recognizer
        }()
        func gestureRecognizerShouldBegin(_ recognizer: NSGestureRecognizer) -> Bool {
            guard isEnabled, let host, host.window != nil else { return false }
            return host.bounds.contains(recognizer.location(in: host))
        }
        @objc private func handle(_ recognizer: NSPressGestureRecognizer) {
            let x = recognizer.location(in: nil).x
            switch recognizer.state {
            case .began: startX = x; speech.beginScrub(); CanvasImpactFeedback(style: .light).impactOccurred()
            case .changed: speech.updateScrub(translation: x - startX)
            case .ended, .cancelled, .failed: speech.endScrub()
            default: break
            }
        }
    }
}
#endif

private struct SpokenWordLift: ViewModifier {
    let index: Int
    let speechText: String

    private var speech = ResponseSpeechPlayer.shared

    init(index: Int, speechText: String) {
        self.index = index
        self.speechText = speechText
    }

    func body(content: Content) -> some View {
        let isLifted = !speechText.isEmpty && speech.activeText == speechText
            && speech.activeWord.map { index <= $0 } == true
        content
            .offset(y: isLifted ? -2 : 0)
            .animation(.timingCurve(0.55, 0, 0.17, 1, duration: 0.4), value: isLifted)
            .background {
                // A scroll view can be sent to the word being read through this marker.
                if !speechText.isEmpty, speech.activeText == speechText, speech.activeWord == index {
                    Color.clear.id(ReadingScroll.activeWordID)
                }
            }
    }
}


/// Keeps the card's visible words and the speech timeline on the same whitespace-token indices.
enum CardSpeech {
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func units(for text: String) -> [SpokenUnit] {
        let words = words(in: text).enumerated().map { SpokenUnit.Word(index: $0.offset, token: $0.element) }
        return words.isEmpty ? [] : [SpokenUnit(words: words)]
    }

    static func text(for concept: ConceptDefinition) -> String {
        concept.isLibraryQuote ? concept.semanticDefinition : text(for: concept.contextualDefinitions)
    }

    static func heading(for definition: InsightDefinition, count: Int) -> String {
        count > 1 && !definition.context.isEmpty ? "In regards to \(definition.context)" : ""
    }

    static func wordStart(for index: Int, in definitions: [InsightDefinition]) -> Int {
        definitions.prefix(index).reduce(0) { offset, definition in
            offset + words(in: heading(for: definition, count: definitions.count)).count
                + words(in: definition.meaning).count
        }
    }

    static func text(for definitions: [InsightDefinition]) -> String {
        definitions.map { definition in
            [heading(for: definition, count: definitions.count), definition.meaning]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

/// Uses the response's exact green wipe, glow, lift, and hold-to-scrub behavior.
/// Reading displays every word so the cursor cannot disappear behind truncation.
struct CardSpeechText: View {
    let text: String
    let speechText: String
    var wordStart = 0
    var fontName: String? = nil
    var fontSize: CGFloat = 14
    var color: Color = AngroveTheme.Colors.paragraphText
    var isItalic = false
    var isBold = false
    var isQuoted = false
    var lineLimit: Int? = nil

    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var responseSize: ConversationFontSizeOption = .small
    private var speech: ResponseSpeechPlayer { .shared }
    private var isReading: Bool { !speechText.isEmpty && speech.activeText == speechText }

    private var font: Font {
        var result = fontName.map { BrandTypography.font($0, size: fontSize) }
            ?? responseFont.textFont(size: responseSize)
        if isItalic { result = result.italic() }
        if isBold { result = result.bold() }
        return result
    }

    var body: some View {
        Group {
            if isReading {
                readingText
            } else {
                Text(verbatim: isQuoted ? "“\(text)”" : text)
                    .font(font)
                    .lineSpacing(FlowLayout.rowSpacing)
                    .foregroundColor(color)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.springQuick, value: isReading)
    }

    private var readingText: some View {
        let lines = text.components(separatedBy: .newlines)
        let totalWords = CardSpeech.words(in: text).count
        return VStack(alignment: .leading, spacing: FlowLayout.rowSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                let start = CardSpeech.words(in: lines.prefix(lineIndex).joined(separator: "\n")).count
                let words = CardSpeech.words(in: line)
                if words.isEmpty {
                    Color.clear.frame(height: FlowLayout.rowSpacing)
                } else {
                    FlowLayout(alignment: .leading) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            let position = start + index
                            let visible = (isQuoted && position == 0 ? "“" : "") + word
                                + (isQuoted && position == totalWords - 1 ? "”" : "")
                            let label = Text(verbatim: visible).font(font)
                            label
                                .foregroundColor(color)
                                .spokenWordFill(index: wordStart + position, speechText: speechText, fill: label)
                                .spokenWordLift(index: wordStart + position, speechText: speechText)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .speechScrubbable(speechText: speechText)
    }
}
