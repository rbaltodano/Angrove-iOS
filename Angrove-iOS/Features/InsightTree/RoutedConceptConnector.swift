import SwiftUI

/// Curve, reveal and crossing gaps share live endpoints during camera animations.
struct RoutedConceptConnector: View {
    let route: InsightTreeConnectorRouting.Route
    let canvasSize: CGSize
    let color: Color
    let isSuggested: Bool
    @State private var drawn: CGFloat

    init(route: InsightTreeConnectorRouting.Route, canvasSize: CGSize, color: Color, isAnimated: Bool, isSuggested: Bool,
         screenPerWorld: CGFloat = 1) {
        self.route = route; self.canvasSize = canvasSize; self.color = color; self.isSuggested = isSuggested
        self.screenPerWorld = screenPerWorld
        _drawn = State(initialValue: isAnimated ? 0 : 1)
    }

    /// Screen points per world unit along a bend (negative: the screen flips world y).
    var screenPerWorld: CGFloat = 1
    /// The world-space bend actually drawn. A new route bends the line smoothly into place
    /// instead of swapping curves, while the endpoints keep following the camera live.
    @State private var shownWorldBend: CGFloat?

    static let rebendAnimation = Animation.smooth(duration: 0.45)

    private var worldBend: CGFloat { screenPerWorld == 0 ? route.bend : route.bend / screenPerWorld }

    var body: some View {
        stroke(bend: (shownWorldBend ?? worldBend) * screenPerWorld)
            .onChange(of: (worldBend * 2).rounded()) { _, _ in
                // Only the bend animates; endpoint changes in later frames still apply directly.
                withAnimation(Self.rebendAnimation) { shownWorldBend = worldBend }
            }
            .onAppear {
                shownWorldBend = worldBend
                if drawn < 1 { withAnimation(InsightConnectorLine.growAnimation) { drawn = 1 } }
            }
    }

    private func stroke(bend: CGFloat) -> some View {
        RoutedConceptConnectorShape(start: route.connector.start, end: route.connector.end, bend: bend,
            gaps: route.gaps, drawn: drawn)
        .stroke(LinearGradient(stops: [
            .init(color: color.opacity(0), location: 0), .init(color: color, location: 0.2),
            .init(color: color, location: 0.8), .init(color: color.opacity(0), location: 1)
        ], startPoint: UnitPoint(x: route.connector.start.x / max(canvasSize.width, 1), y: route.connector.start.y / max(canvasSize.height, 1)),
           endPoint: UnitPoint(x: route.connector.end.x / max(canvasSize.width, 1), y: route.connector.end.y / max(canvasSize.height, 1))),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: isSuggested ? [6, 4] : []))
    }
}

struct RoutedConceptConnectorShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var bend: CGFloat
    var gaps: [ClosedRange<CGFloat>]
    var drawn: CGFloat

    var animatableData: AnimatablePair<AnimatableLine.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(AnimatableLine(start: start, end: end).animatableData, .init(bend, drawn)) }
        set {
            var line = AnimatableLine(start: start, end: end)
            line.animatableData = newValue.first; start = line.start; end = line.end
            bend = newValue.second.first; drawn = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let dx = end.x - start.x, dy = end.y - start.y, length = max(hypot(dx, dy), 1)
        let control = CGPoint(x: (start.x + end.x) / 2 - dy / length * bend,
                              y: (start.y + end.y) / 2 + dx / length * bend)
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                           y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
        }
        var path = Path()
        for range in InsightTreeConnectorRouting.visibleRanges(gaps: gaps, drawn: drawn) {
            let t = range.lowerBound, span = range.upperBound - t, origin = point(t)
            // The exact quadratic subcurve: gaps keep a fixed screen width even on long lines.
            let c = CGPoint(x: origin.x + span * ((1 - t) * (control.x - start.x) + t * (end.x - control.x)),
                            y: origin.y + span * ((1 - t) * (control.y - start.y) + t * (end.y - control.y)))
            path.move(to: origin)
            path.addQuadCurve(to: point(range.upperBound), control: c)
        }
        return path
    }
}
