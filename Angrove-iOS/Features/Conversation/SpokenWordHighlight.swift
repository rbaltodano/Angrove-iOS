//
//  SpokenWordHighlight.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

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
                        .init(color: .black, location: start),
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
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isScaled)
            .background {
                SpeechScrubRecognizer(isEnabled: isReadingThis && speech.phase == .speaking)
            }
    }
}

/// A UIKit long press on the enclosing scroll view, limited to the modified view's frame. SwiftUI
/// gestures cannot hand a still finger to scrubbing while still yielding to scrolling the moment
/// the finger moves; the system recognizer does both, and once it begins the scroll view's pan
/// cannot.
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
