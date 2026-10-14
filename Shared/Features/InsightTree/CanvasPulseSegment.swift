import SwiftUI

struct TravelingCanvasPulse: View {
    let start: CGPoint
    let end: CGPoint
    let progress: Double
    let lineWidth: CGFloat
    var control: CGPoint? = nil

    var body: some View {
        let segmentWidth = 0.22
        let segmentStart = max(0, progress - segmentWidth)
        let segmentEnd = min(progress, 1)

        if segmentEnd > segmentStart {
            CanvasPulseSegment(
                start: start,
                end: end,
                from: segmentStart,
                to: segmentEnd,
                lineWidth: lineWidth,
                control: control
            )
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
    var control: CGPoint? = nil

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

        if let control {
            let pulseStart = quadraticPoint(from: start, control: control, to: end, at: segmentStart)
            let pulseEnd = quadraticPoint(from: start, control: control, to: end, at: segmentEnd)
            GeometryReader { geometry in
                Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                }
                .trim(from: segmentStart, to: segmentEnd)
                .stroke(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: color.opacity(0), location: 0.00),
                            Gradient.Stop(color: color, location: 0.50),
                            Gradient.Stop(color: color.opacity(0), location: 1.00)
                        ],
                        startPoint: UnitPoint(
                            x: pulseStart.x / max(geometry.size.width, 1),
                            y: pulseStart.y / max(geometry.size.height, 1)
                        ),
                        endPoint: UnitPoint(
                            x: pulseEnd.x / max(geometry.size.width, 1),
                            y: pulseEnd.y / max(geometry.size.height, 1)
                        )
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
            .opacity(opacity)
        } else {
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

    private func quadraticPoint(from start: CGPoint, control: CGPoint, to end: CGPoint, at t: Double) -> CGPoint {
        let t = CGFloat(t)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }
}
