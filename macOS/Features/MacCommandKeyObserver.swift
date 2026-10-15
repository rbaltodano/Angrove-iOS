import AppKit
import SwiftUI

/// Tracks the modifier without consuming keyboard events or taking focus from editors.
struct MacCommandKeyObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ModifierView { ModifierView(onChange: onChange) }
    func updateNSView(_ view: ModifierView, context: Context) { view.onChange = onChange }
    static func dismantleNSView(_ view: ModifierView, coordinator: ()) { view.stopMonitoring() }

    final class ModifierView: NSView {
        var onChange: (Bool) -> Void
        private var eventMonitor: Any?
        private var notifications: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard let window else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.updateCommandState(event.modifierFlags)
                return event
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                notifications.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateCommandState(NSEvent.modifierFlags) }
                })
            }
            notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange(false) }
            })
            DispatchQueue.main.async { [weak self] in self?.updateCommandState(NSEvent.modifierFlags) }
        }

        private func updateCommandState(_ flags: NSEvent.ModifierFlags) {
            onChange(NSApp.isActive && window?.isKeyWindow == true && flags.contains(.command))
        }

        func stopMonitoring() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            notifications.forEach(NotificationCenter.default.removeObserver)
            notifications.removeAll()
        }
    }
}
