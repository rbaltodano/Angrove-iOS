import SwiftUI

/// The same growing logo used by Home's pull-to-refresh, centered in the available page.
struct LibraryLoadingView: View {
    var body: some View {
        VStack(spacing: AngroveTheme.Spacing.unit * 2) {
            LeafLoadingAnimation(size: 28)
            Text("Loading")
                .paragraphFont()
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}
