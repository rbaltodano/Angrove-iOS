import AppKit
import SwiftUI

/// Keeps a page's scroller in the thin, auto-hiding overlay style even when a mouse is attached.
/// The legacy scroller draws a light track that stands out against the dark canvas.
struct MacOverlayScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            apply()
            // AppKit resets the style when the system scroller preference changes.
            observer = observer ?? NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.apply() }
        }

        private func apply() {
            DispatchQueue.main.async { [weak self] in
                self?.enclosingScrollView?.scrollerStyle = .overlay
            }
        }

        deinit { observer.map(NotificationCenter.default.removeObserver) }
    }
}

extension View {
    /// Place inside a ScrollView's content.
    func macOverlayScroller() -> some View { background(MacOverlayScroller()) }
}
