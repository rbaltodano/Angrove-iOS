import SwiftUI

enum WorktreeBoxSelection {
    /// Normalized for drags in any direction, in either screen or canvas coordinates.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

struct WorktreeSelectionRectangle: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(AngroveTheme.Colors.lightGreen.opacity(0.15))
            .overlay(Rectangle().strokeBorder(AngroveTheme.Colors.lightGreen, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { $0.animation = nil }
    }
}

extension WorktreeBoard {
    /// Items touched by the rectangle are selected together. The seed is captured at mouse-down
    /// for additive selection, so shrinking the box removes items that have left it.
    func select(in rect: CGRect, addingTo seed: [UUID] = []) {
        let existing = Set(items.map(\.id))
        var next = seed.filter { existing.contains($0) }
        for item in items where !next.contains(item.id) {
            if let bounds = frame(of: item.id), rect.intersects(bounds) {
                next.append(item.id)
            }
        }
        selection = next
    }
}
