import Observation
import SwiftUI

/// Each conversation owns its own scroll state, even while the two workspace panes swap.
@MainActor @Observable final class MacConversationScrollState {
    var isAtBottom = true
    var bottomRequest = 0
}

struct MacConversationScrollTracking: ViewModifier {
    let state: MacConversationScrollState
    @Binding var position: ScrollPosition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let remaining = geometry.contentSize.height + geometry.contentInsets.bottom
                    - geometry.contentOffset.y - geometry.containerSize.height
                return remaining <= 80
            } action: { _, isAtBottom in
                state.isAtBottom = isAtBottom
            }
            .onChange(of: state.bottomRequest) { _, _ in
                withAnimation(reduceMotion ? nil : .springStandard) {
                    position.scrollTo(edge: .bottom)
                }
            }
    }
}
