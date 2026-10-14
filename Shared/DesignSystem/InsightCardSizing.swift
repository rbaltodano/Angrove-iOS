import SwiftUI

extension View {
    /// Desktop cards share a remembered width and native side handles; mobile keeps its cap.
    func insightCardSizing(mobileMaxWidth: CGFloat? = AngroveTheme.Spacing.insightCardMaxWidth) -> some View {
        #if os(macOS)
        modifier(MacInsightCardSizing())
        #else
        frame(maxWidth: mobileMaxWidth)
        #endif
    }
}
