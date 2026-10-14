import SwiftUI

/// A revealed graph edge, preserving the animated and suggested-line treatments.
struct InsightTreeCanvasGraphEdge: View {
    let start: CGPoint
    let end: CGPoint
    let canvasSize: CGSize
    let color: Color
    let isAnimated: Bool
    let isSuggested: Bool

    var body: some View {
        Group {
            if isAnimated {
                InsightConnectorLine(
                    start: start,
                    end: end,
                    canvasSize: canvasSize,
                    color: color
                )
            } else {
                FadedCanvasLine(
                    start: start, end: end, canvasSize: canvasSize, color: color,
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: isSuggested ? [6, 4] : [])
                )
            }
        }
    }
}
