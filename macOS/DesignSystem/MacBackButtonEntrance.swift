import SwiftUI

/// A navigation button that arrives with the iPhone's scale, fade, and blur: it grows from
/// its leading edge as it sharpens. Works for buttons that arrive with their page, where a
/// removal-and-insertion transition has no parent to run on.
private struct MacBackButtonEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hasArrived || reduceMotion ? 1 : 0.4, anchor: .leading)
            .opacity(hasArrived ? 1 : 0)
            .blur(radius: hasArrived || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard) { hasArrived = true }
            }
    }
}

extension View {
    /// Use on "back to previous page" buttons.
    func macBackButtonEntrance() -> some View { modifier(MacBackButtonEntrance()) }
}
