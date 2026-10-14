import SwiftUI

// MARK: - Thinking shimmer

/// Sweeps a bright wave left-to-right across text while the model is thinking.
/// Uses TimelineView(.animation) so phase is derived from wall-clock time —
/// guaranteed per-frame updates, no @State animation batching issues.
struct ThinkingShimmer: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let t  = context.date.timeIntervalSinceReferenceDate
                // Total cycle: 1.0 s sweep + 1.0 s pause = 2.0 s.
                // `phase` only reaches 1.0 at the sweep midpoint; after that it
                // clamps at 1.0 so the band sits off the right edge (invisible)
                // for the pause portion before the next sweep begins. The sweep
                // range clears the band (half-width 0.4) fully past x = 1.0 by
                // the time phase reaches 1.0, so the fade-out happens gradually
                // as part of the sweep itself instead of leaving a bright tail
                // resting on the last character that then snaps away when the
                // next cycle starts.
                let cycle: Double  = 2.0
                let sweepSpan: Double = 1.0
                let tMod  = t.truncatingRemainder(dividingBy: cycle)
                let phase = CGFloat(min(tMod / sweepSpan, 1.0))
                let sweep = phase * 1.9 - 0.4
                content
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                color.opacity(0.25),
                                color.opacity(0.95),
                                color.opacity(0.25),
                            ],
                            startPoint: UnitPoint(x: sweep - 0.4, y: 0.5),
                            endPoint:   UnitPoint(x: sweep + 0.4, y: 0.5)
                        )
                    )
            }
        } else {
            content.foregroundColor(color.opacity(0.5))
        }
    }
}
