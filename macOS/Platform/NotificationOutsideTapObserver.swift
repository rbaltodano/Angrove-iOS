import AppKit
import SwiftUI

/// Observe the click before normal dispatch, then return the same event to the clicked control.
struct NotificationOutsideTapObserver: NSViewRepresentable {
    let center: ModelCompletionNotificationCenter
    let stackBounds: [CGRect]

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.notificationCenter = center
        view.stackBounds = stackBounds
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stopObserving() }

    final class ObserverView: NSView {
        weak var notificationCenter: ModelCompletionNotificationCenter?
        var stackBounds: [CGRect] = []
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.notificationCenter?.isStackExpanded == true, !self.stackBounds.isEmpty else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point), !self.stackBounds.contains(where: { $0.contains(point) }) {
                    self.notificationCenter?.collapseStack()
                }
                return event
            }
        }

        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
