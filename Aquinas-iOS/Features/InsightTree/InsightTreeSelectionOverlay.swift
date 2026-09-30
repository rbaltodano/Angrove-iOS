import SwiftUI

/// Rendering depends on screen positions and selection effects, not the full graph or physics.
struct InsightTreeSelectionOverlay: View {
    let positions: [CGPoint?]
    let isMidpointMode: Bool
    let center: CGPoint
    let size: CGSize
    let restFade: Double
    let studyAmount: Double
    let selectionPulseStartTime: TimeInterval?

    var body: some View {
        let studied = studyAmount
        if !isMidpointMode,
           let activePosition = positions.last ?? nil {

            ZStack {
                ForEach(Array(positions.indices.dropFirst()), id: \.self) { index in
                    if let previousPosition = positions[index - 1],
                       let currentPosition = positions[index] {
                        AnimatableLine(start: previousPosition, end: currentPosition)
                        .stroke(
                            AquinasTheme.Colors.lightGreen.opacity(0.8 + 0.2 * studied),
                            style: StrokeStyle(lineWidth: 1.5 + 0.5 * CGFloat(studied), lineCap: .round)
                        )
                        .frame(width: size.width, height: size.height)
                        .opacity(max(restFade, studied))
                    }
                }

                Group {
                    AnimatableLine(start: activePosition, end: center)
                        .stroke(
                            AquinasTheme.Colors.lightGreen.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: size.width, height: size.height)

                    SelectionReticle()
                        .position(center)
                }
                .opacity(restFade)

                if let selectionPulseStartTime,
                   positions.count > 1,
                   let previousPosition = positions.dropLast().last ?? nil {
                    TimelineView(.animation) { timeline in
                        let progress = min(max((timeline.date.timeIntervalSinceReferenceDate - selectionPulseStartTime) / 0.8, 0), 1)
                        if progress < 1 {
                            TravelingCanvasPulse(start: previousPosition, end: activePosition, progress: progress, lineWidth: 2.4)
                                .frame(width: size.width, height: size.height)
                                .opacity(restFade)
                        }
                    }
                }

                // Fast repeating green pulses along all selection lines
                TimelineView(.animation) { fastTimeline in
                    let fastCycle = 0.55
                    let fastProgress = fastTimeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: fastCycle) / fastCycle
                    let segWidth = 0.38
                    let segStart = max(0, fastProgress - segWidth)
                    let segEnd = min(fastProgress, 1)

                    ZStack {
                        // Pulses between each pair of selected targets
                        ForEach(Array(positions.indices.dropFirst()), id: \.self) { index in
                            if let previousPosition = positions[index - 1],
                               let currentPosition = positions[index],
                               segEnd > segStart {
                                CanvasPulseSegment(
                                    start: previousPosition,
                                    end: currentPosition,
                                    from: segStart, to: segEnd,
                                    lineWidth: 4,
                                    color: AquinasTheme.Colors.lightGreen,
                                    opacity: 0.9
                                )
                                .frame(width: size.width, height: size.height)
                            }
                        }

                        // Pulse from most recent selection to center circle
                        if segEnd > segStart {
                            CanvasPulseSegment(
                                start: activePosition,
                                end: center,
                                from: segStart, to: segEnd,
                                lineWidth: 4,
                                color: AquinasTheme.Colors.lightGreen,
                                opacity: 0.9
                            )
                            .frame(width: size.width, height: size.height)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
                // The pulses stop as the lines solidify in Study.
                .opacity(restFade)
            }
            .allowsHitTesting(false)
        }
    }
}
