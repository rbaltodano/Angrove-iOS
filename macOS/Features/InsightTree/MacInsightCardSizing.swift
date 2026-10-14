import AppKit
import SwiftUI

/// One preference for every desktop Insight card, independent of card identity.
enum MacInsightCardWidth {
    static let storageKey = "macInsightCardWidth"
    static let minimum: CGFloat = 400
    static let maximum: CGFloat = 600

    static func clamped(_ width: CGFloat) -> CGFloat {
        width.isFinite ? min(maximum, max(minimum, width)) : minimum
    }

    static func visible(_ preferred: CGFloat, available: CGFloat?) -> CGFloat {
        guard let available, available.isFinite else { return clamped(preferred) }
        return max(minimum, min(clamped(preferred), available))
    }

    // Cards stay centered above their controls, so both edges move by half the width delta.
    static func resized(from width: CGFloat, translation: CGFloat, isLeftEdge: Bool) -> CGFloat {
        clamped(width + translation * (isLeftEdge ? -2 : 2))
    }
}

struct MacInsightCardSizing: ViewModifier {
    @AppStorage(MacInsightCardWidth.storageKey) private var preferredWidth = Double(MacInsightCardWidth.minimum)
    @State private var visibleWidth = MacInsightCardWidth.minimum

    func body(content: Content) -> some View {
        CardLayout(preferredWidth: CGFloat(preferredWidth)) { content }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            .overlay(alignment: .leading) { handle(isLeftEdge: true) }
            .overlay(alignment: .trailing) { handle(isLeftEdge: false) }
            .transaction { $0.animation = nil }
    }

    private func handle(isLeftEdge: Bool) -> some View {
        MacInsightCardResizeEdge(width: visibleWidth, isLeftEdge: isLeftEdge) {
            preferredWidth = Double($0)
        }
        .frame(width: 12)
        .frame(maxHeight: .infinity)
        .padding(.vertical, AngroveTheme.Spacing.cardRadius)
        .accessibilityLabel(isLeftEdge ? "Resize Insight card from left edge" : "Resize Insight card from right edge")
        .accessibilityValue("\(Int(visibleWidth)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: preferredWidth = Double(MacInsightCardWidth.clamped(CGFloat(preferredWidth) + 20))
            case .decrement: preferredWidth = Double(MacInsightCardWidth.clamped(CGFloat(preferredWidth) - 20))
            @unknown default: break
            }
        }
    }

    private struct CardLayout: Layout {
        let preferredWidth: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let width = MacInsightCardWidth.visible(preferredWidth, available: proposal.width)
            let height = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height ?? 0
            return CGSize(width: width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

private struct MacInsightCardResizeEdge: NSViewRepresentable {
    let width: CGFloat
    let isLeftEdge: Bool
    let onResize: (CGFloat) -> Void

    func makeNSView(context: Context) -> EdgeView { EdgeView() }

    func updateNSView(_ view: EdgeView, context: Context) {
        view.cardWidth = width
        view.isLeftEdge = isLeftEdge
        view.onResize = onResize
    }

    final class EdgeView: NSView {
        var cardWidth: CGFloat = MacInsightCardWidth.minimum
        var isLeftEdge = false
        var onResize: ((CGFloat) -> Void)?
        private var startWidth: CGFloat = 0
        private var startX: CGFloat = 0

        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

        override func mouseDown(with event: NSEvent) {
            startWidth = cardWidth
            startX = event.locationInWindow.x
        }

        override func mouseDragged(with event: NSEvent) {
            NSCursor.resizeLeftRight.set()
            onResize?(MacInsightCardWidth.resized(from: startWidth,
                translation: event.locationInWindow.x - startX, isLeftEdge: isLeftEdge))
        }
    }
}
