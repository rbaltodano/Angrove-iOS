import SwiftUI

struct TravelingCanvasPulse: View {
    let start: CGPoint
    let end: CGPoint
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        let segmentWidth = 0.22
        let segmentStart = max(0, progress - segmentWidth)
        let segmentEnd = min(progress, 1)

        if segmentEnd > segmentStart {
            CanvasPulseSegment(start: start, end: end, from: segmentStart, to: segmentEnd, lineWidth: lineWidth)
        }
    }
}

struct CanvasPulseSegment: View {
    let start: CGPoint
    let end: CGPoint
    let from: Double
    let to: Double
    let lineWidth: CGFloat
    var color: Color = AngroveTheme.Colors.pulse
    var opacity: Double = 0.5

    var body: some View {
        let segmentStart = from
        let segmentEnd = to
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let centerProgress = (segmentStart + segmentEnd) / 2
        let segmentLength = max(distance * CGFloat(segmentEnd - segmentStart), 1)
        let center = CGPoint(
            x: start.x + dx * CGFloat(centerProgress),
            y: start.y + dy * CGFloat(centerProgress)
        )
        let angle = Angle(radians: Double(atan2(dy, dx)))

        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: color.opacity(0), location: 0.00),
                        Gradient.Stop(color: color, location: 0.50),
                        Gradient.Stop(color: color.opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
            .frame(width: segmentLength, height: lineWidth)
            .rotationEffect(angle)
            .opacity(opacity)
            .position(center)
    }
}
