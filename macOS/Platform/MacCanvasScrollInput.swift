#if os(macOS)
import AppKit
import SwiftUI

/// Uses native scroll deltas so trackpad momentum and the user's scrolling direction are kept.
/// Command wins over Shift. macOS sometimes moves Shift-wheel deltas onto the X axis.
struct CanvasScrollTransform {
    var scale: CGFloat
    var offset: CGSize

    mutating func apply(delta: CGSize, command: Bool, shift: Bool, anchor: CGPoint,
                        viewport: CGSize, limits: ClosedRange<CGFloat> = 0.28...2.6) {
        guard delta.width.isFinite, delta.height.isFinite else { return }
        let vertical = delta.height == 0 ? delta.width : delta.height
        if command {
            let next = min(max(scale * exp(vertical * 0.012), limits.lowerBound), limits.upperBound)
            let ratio = next / scale
            let centered = CGPoint(x: anchor.x - viewport.width / 2, y: anchor.y - viewport.height / 2)
            offset = CGSize(width: centered.x - (centered.x - offset.width) * ratio,
                            height: centered.y - (centered.y - offset.height) * ratio)
            scale = next
        } else if shift {
            offset.width += vertical
        } else {
            offset.width += delta.width
            offset.height += delta.height
        }
    }
}

struct MacCanvasScrollInput: NSViewRepresentable {
    var onScroll: (CGSize, NSEvent.ModifierFlags, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollSurface {
        let view = ScrollSurface()
        view.onScroll = onScroll
        return view
    }
    func updateNSView(_ view: ScrollSurface, context: Context) { view.onScroll = onScroll }
    static func dismantleNSView(_ view: ScrollSurface, coordinator: ()) { view.stopMonitoring() }

    final class ScrollSurface: NSView {
        var onScroll: ((CGSize, NSEvent.ModifierFlags, CGPoint) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point), self.visibleRect.contains(point) else { return event }
                // A docked definition's native ScrollView keeps its own scrolling.
                var hit = self.window?.contentView?.hitTest(event.locationInWindow)
                while let view = hit {
                    if view is NSScrollView { return event }
                    hit = view.superview
                }
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                self.onScroll?(CGSize(width: CGFloat(event.scrollingDeltaX) * multiplier,
                                      height: CGFloat(event.scrollingDeltaY) * multiplier),
                               event.modifierFlags, point)
                return nil
            }
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
