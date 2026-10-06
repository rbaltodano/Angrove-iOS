import SwiftUI

/// Insight chip content and chrome, independent of gesture and camera orchestration.
struct InsightTreeCanvasChip: View {
    let title: String
    let isLoading: Bool
    let isRevealed: Bool
    let isVisible: Bool
    let isSelected: Bool
    let isUndiscovered: Bool
    let loadingFlashOpacity: Double
    let labelOpacity: Double
    let selectionStudyAmount: Double
    let backgroundColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            // While generating: the hollow loading bubble, flashing. On completion it fades
            // out and blurs as the solid content cross-fades in.
            if isLoading {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .opacity(loadingFlashOpacity)
                    .transition(.fadeBlur)
            }
            // Icon + title appear together as one unit (fade + transform + blur), like a
            // streamed model response. The icon stays full opacity; only the title fades with zoom.
            if isRevealed {
                RevealedInsightLabel(title: title, labelOpacity: labelOpacity)
                    .transition(.glideFadeUp)
            }
        }
        .modifier(InsightTreeChipChrome(labelOpacity: labelOpacity))
        .overlay {
            if isSelected {
                SelectedCanvasInsightBorder()
                    .opacity(labelOpacity * (1 - selectionStudyAmount))
            }
        }
        // Blue "new / undiscovered" dot — disappears the first time the insight is hovered.
        .overlay(alignment: .topLeading) {
            if isVisible, isUndiscovered {
                Circle()
                    .fill(AngroveTheme.Colors.unreadDot)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(backgroundColor, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }
}
