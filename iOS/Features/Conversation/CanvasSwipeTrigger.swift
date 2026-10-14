//
//  CanvasSwipeTrigger.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

final class CanvasSwipeView: UIView {
    var onTriggered: (() -> Void)?
    var excludedScrollRegions: AttachmentScrollRegions?
    fileprivate var windowPan: UIPanGestureRecognizer?
    /// A drag that scrubs read-aloud playback is not a swipe, even if it ends after the scrub does.
    private var isSuppressed = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowPan?.view?.removeGestureRecognizer(windowPan!)
        windowPan = nil
        guard let window else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        window.addGestureRecognizer(pan)
        windowPan = pan
    }

    deinit { windowPan?.view?.removeGestureRecognizer(windowPan!) }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        if ResponseSpeechPlayer.shared.isScrubbing { isSuppressed = true }
        guard pan.state == .ended || pan.state == .cancelled || pan.state == .failed else { return }
        let wasSuppressed = isSuppressed
        isSuppressed = false
        guard pan.state == .ended, !wasSuppressed else { return }
        let t = pan.translation(in: pan.view)
        let v = pan.velocity(in: pan.view)
        guard (t.x < -80 && abs(t.x) > abs(t.y) * 1.5) ||
              (v.x < -500 && abs(v.x) > abs(v.y) * 1.5) else { return }
        onTriggered?()
    }
}

extension CanvasSwipeView: UIGestureRecognizerDelegate {
    func acceptsSwipe(at point: CGPoint) -> Bool {
        excludedScrollRegions?.contains(point) != true
    }

    func gestureRecognizer(_ gr: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        acceptsSwipe(at: touch.location(in: nil))
    }

    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

struct RightEdgeCanvasSwipeTrigger: UIViewRepresentable {
    var excludedScrollRegions: AttachmentScrollRegions? = nil
    var onTriggered: () -> Void
    func makeUIView(context: Context) -> CanvasSwipeView {
        let v = CanvasSwipeView()
        v.backgroundColor = .clear
        v.onTriggered = onTriggered
        v.excludedScrollRegions = excludedScrollRegions
        return v
    }
    func updateUIView(_ uiView: CanvasSwipeView, context: Context) {
        uiView.onTriggered = onTriggered
        uiView.excludedScrollRegions = excludedScrollRegions
    }
    static func dismantleUIView(_ uiView: CanvasSwipeView, coordinator: ()) {
        uiView.windowPan?.view?.removeGestureRecognizer(uiView.windowPan!)
        uiView.windowPan = nil
    }
}
