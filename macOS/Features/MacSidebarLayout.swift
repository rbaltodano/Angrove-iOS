import AppKit
import SwiftUI

struct MacSidebarLayout {
    static let minimumWidth: CGFloat = 280
    static let minimumPageWidth: CGFloat = 350
    static let collapseDistance: CGFloat = 84
    static let contentInset: CGFloat = 24
    static let compactWidth: CGFloat = 44 + contentInset * 2
    // Reserve the controls' 24-point top inset and 14-point height above the menu padding.
    static let contentTopInset: CGFloat = 38 + contentInset

    private(set) var expandedWidth: CGFloat = minimumWidth
    private(set) var isCompact = false

    func width(in windowWidth: CGFloat) -> CGFloat {
        isCompact ? Self.compactWidth : min(expandedWidth, Self.maximumWidth(in: windowWidth))
    }

    private static func maximumWidth(in windowWidth: CGFloat) -> CGFloat {
        max(minimumWidth, windowWidth - minimumPageWidth)
    }

    mutating func drag(from origin: Self, translation: CGFloat, windowWidth: CGFloat) {
        self = origin
        if origin.isCompact {
            guard translation >= Self.collapseDistance else { return }
            isCompact = false
            expandedWidth = min(origin.expandedWidth + translation - Self.collapseDistance,
                                Self.maximumWidth(in: windowWidth))
        } else {
            let proposed = origin.width(in: windowWidth) + translation
            isCompact = proposed <= Self.minimumWidth - Self.collapseDistance
            expandedWidth = min(max(Self.minimumWidth, proposed), Self.maximumWidth(in: windowWidth))
        }
    }

    mutating func toggleCompact() { isCompact.toggle() }
}

/// Share the native controls' row, with the toggle at the sidebar's trailing inset.
struct MacSidebarToggle: View {
    @Binding var layout: MacSidebarLayout
    let windowWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: MacSidebarTransition.widthDuration)) {
                    layout.toggleCompact()
                }
            } label: {
                Image(systemName: "inset.filled.leftthird.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layout.isCompact ? "Expand sidebar" : "Collapse sidebar")
            .help(layout.isCompact ? "Expand sidebar" : "Collapse sidebar")
        }
        .padding(.trailing, MacSidebarLayout.contentInset)
        // Leave room beside the three native buttons when the rail is compact.
        .frame(width: max(layout.width(in: windowWidth), 140))
        .padding(.top, 19) // 24-point button centered with the 14-point native controls at y=24.
    }
}

struct MacSidebarResizeHandle: View {
    @Binding var layout: MacSidebarLayout
    let windowWidth: CGFloat
    @State private var dragOrigin: MacSidebarLayout?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: 24)
            .contentShape(Rectangle())
            .background(MacSidebarResizeCursor())
            .onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.resizeLeftRight.set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .offset(x: 12)
            .help("Drag to resize or collapse the sidebar. Drag outward to expand it.")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("MacWorkspace"))
                .onChanged { value in
                    let origin = dragOrigin ?? layout
                    dragOrigin = origin
                    applyDrag(from: origin, translation: value.translation.width)
                }
                .onEnded { value in
                    if let origin = dragOrigin {
                        applyDrag(from: origin, translation: value.translation.width)
                    }
                    dragOrigin = nil
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sidebar resize handle")
            .accessibilityValue(layout.isCompact ? "Compact" : "\(Int(layout.width(in: windowWidth))) points")
            .accessibilityAdjustableAction { direction in
                let origin = layout
                let translation: CGFloat = direction == .increment ? 84 : -84
                applyDrag(from: origin, translation: translation)
            }
            .accessibilityAction(named: Text(layout.isCompact ? "Expand sidebar" : "Collapse sidebar")) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: MacSidebarTransition.widthDuration)) {
                    layout.toggleCompact()
                }
            }
    }

    private func applyDrag(from origin: MacSidebarLayout, translation: CGFloat) {
        var next = layout
        next.drag(from: origin, translation: translation, windowWidth: windowWidth)
        guard next.isCompact != layout.isCompact || next.expandedWidth != layout.expandedWidth else { return }
        // Animate the whole workspace transaction, including the adjacent page's width.
        // Outward drags from the rail keep retargeting smoothly as the pointer moves.
        let animatesWidth = origin.isCompact || next.isCompact != layout.isCompact
        withAnimation(animatesWidth && !reduceMotion ? .easeInOut(duration: MacSidebarTransition.widthDuration) : nil) {
            layout = next
        }
    }
}

private struct MacSidebarResizeCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {}

    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }
}
