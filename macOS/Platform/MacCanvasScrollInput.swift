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

/// The surface under the first event owns the complete gesture, including its momentum.
/// Wheel mice have no phases, so a short gap separates their scroll bursts.
struct CanvasScrollGestureRoute {
    private enum Owner { case canvas, native }
    private var owner: Owner?
    private var momentumOwner: Owner?
    private var lastTime: TimeInterval = -.infinity
    private var endedAt: TimeInterval = -.infinity

    mutating func reset() { self = Self() }

    mutating func takesCanvas(phase: NSEvent.Phase, momentum: NSEvent.Phase,
                             timestamp: TimeInterval, inside: Bool,
                             overNativeScroll: () -> Bool) -> Bool {
        if phase.contains(.mayBegin) { return false }
        if phase.contains(.began) {
            owner = nil
            momentumOwner = nil
        }
        let unphased = phase.isEmpty && momentum.isEmpty
        if unphased, timestamp - lastTime > 0.18 { owner = nil }
        if !momentum.isEmpty, owner == nil, timestamp - endedAt < 0.5 {
            owner = momentumOwner
        }
        if owner == nil { owner = inside && !overNativeScroll() ? .canvas : .native }
        lastTime = timestamp
        let takes = owner == .canvas
        if phase.contains(.cancelled) || momentum.contains(.ended) || momentum.contains(.cancelled) {
            reset()
        } else if phase.contains(.ended) {
            momentumOwner = owner
            endedAt = timestamp
            owner = nil
        }
        return takes
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
        private var gestureRoute = CanvasScrollGestureRoute()
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handleScroll(event)
            }
        }

        /// Keep routing testable with actual native scroll events and nested scroll views.
        func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, !isHiddenOrHasHiddenAncestor else {
                gestureRoute.reset()
                return event
            }
            let point = convert(event.locationInWindow, from: nil)
            let inside = bounds.contains(point) && visibleRect.contains(point)
            let takesCanvas = gestureRoute.takesCanvas(phase: event.phase, momentum: event.momentumPhase,
                timestamp: event.timestamp, inside: inside) {
                // Hit testing may activate a cached card. Only do it at gesture start;
                // crossing a conversation during a pan must not transfer ownership.
                var hit = window?.contentView?.hitTest(event.locationInWindow)
                while let view = hit {
                    if view is NSScrollView { return true }
                    hit = view.superview
                }
                return false
            }
            guard takesCanvas else { return event }
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            onScroll?(CGSize(width: CGFloat(event.scrollingDeltaX) * multiplier,
                                  height: CGFloat(event.scrollingDeltaY) * multiplier),
                           event.modifierFlags, point)
            return nil
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            gestureRoute.reset()
        }
    }
}
#endif
