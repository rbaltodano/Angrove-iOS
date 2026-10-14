import AppKit
import SwiftUI

/// Observe intentional input inside the page without intercepting its native controls.
/// Sidebar navigation and history shortcuts are handled by the workspace directly.
struct MacPageActivityObserver: NSViewRepresentable {
    let onActivity: () -> Void

    func makeNSView(context: Context) -> ActivityView { ActivityView(onActivity: onActivity) }
    func updateNSView(_ view: ActivityView, context: Context) { view.onActivity = onActivity }
    static func dismantleNSView(_ view: ActivityView, coordinator: ()) { view.stopMonitoring() }

    final class ActivityView: NSView {
        var onActivity: () -> Void
        private var monitor: Any?

        init(onActivity: @escaping () -> Void) {
            self.onActivity = onActivity
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self, self.isPageActivity(event) else { return event }
                self.onActivity()
                return event
            }
        }

        func isPageActivity(_ event: NSEvent) -> Bool {
            guard let window, event.window === window else { return false }
            if event.type == .keyDown {
                // Command actions have explicit routing; back/forward must not promote a page.
                guard !event.modifierFlags.contains(.command),
                      let responder = window.firstResponder as? NSView else { return false }
                let center = NSPoint(x: responder.bounds.midX, y: responder.bounds.midY)
                return bounds.contains(convert(center, from: responder))
            }
            return bounds.contains(convert(event.locationInWindow, from: nil))
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
