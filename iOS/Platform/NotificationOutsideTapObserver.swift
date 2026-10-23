import SwiftUI
import UIKit

/// Watches a window's taps alongside its normal recognizers, without cancelling control touches.
struct NotificationOutsideTapObserver: UIViewRepresentable {
    let center: ModelCompletionNotificationCenter
    let stackBounds: [CGRect]

    func makeUIView(context: Context) -> ObserverView { ObserverView() }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.notificationCenter = center
        view.stackBounds = stackBounds
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.stopObserving() }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        weak var notificationCenter: ModelCompletionNotificationCenter?
        var stackBounds: [CGRect] = []
        private weak var observedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped))

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stopObserving()
            guard let window else { return }
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            observedWindow = window
        }

        func stopObserving() {
            observedWindow?.removeGestureRecognizer(tap)
            observedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let point = touch.location(in: self)
            return notificationCenter?.isStackExpanded == true && !stackBounds.isEmpty
                && bounds.contains(point) && !stackBounds.contains { $0.contains(point) }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func tapped() {
            guard tap.state == .ended else { return }
            notificationCenter?.collapseStack()
        }
    }
}
