import AppKit
import Combine
import SwiftUI

/// Keep native window controls, with an explicit inset inside the transparent title bar.
struct MacWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.configureWindow() }

    final class ChromeView: NSView {
        private var subscriptions: Set<AnyCancellable> = []
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            subscriptions.removeAll()
            guard let window else { return }
            NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
                .merge(with: NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification, object: window))
                .sink { [weak self] _ in self?.scheduleLayout() }
                .store(in: &subscriptions)
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "AngroveWindowControls")
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            scheduleLayout()
        }

        override func layout() {
            super.layout()
            positionControls()
        }

        private func scheduleLayout() {
            DispatchQueue.main.async { [weak self] in self?.positionControls() }
        }

        private func positionControls() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let frameView = window.contentView?.superview else { return }
            let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = kinds.compactMap { window.standardWindowButton($0) }
            guard buttons.count == kinds.count else { return }
            let frames = buttons.map { $0.convert($0.bounds, to: frameView) }
            // Preserve AppKit's spacing between the three controls.
            for (index, button) in buttons.enumerated() {
                guard let parent = button.superview else { continue }
                let origin = CGPoint(x: 24 + frames[index].minX - frames[0].minX,
                                     y: frameView.bounds.maxY - 24 - frames[index].height)
                let target = parent.convert(origin, from: frameView)
                if abs(button.frame.minX - target.x) > 0.1 || abs(button.frame.minY - target.y) > 0.1 {
                    button.setFrameOrigin(target)
                }
            }
        }
    }
}
