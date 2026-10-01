import SwiftUI

/// Keeps outgoing titles out of layout while the new title's measured height animates.
/// Observing the displayed title here makes every rename use the same motion, regardless of
/// whether the change came from the model, a command, an editor, or another page.
struct ConversationHeading<Content: View>: View {
    let title: String
    /// A live editor can borrow the same container without unmounting the displayed heading.
    var layoutTitle: String? = nil
    @ViewBuilder let content: (String) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headingHeight: CGFloat?

    var body: some View {
        content(layoutTitle ?? title)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                guard headingHeight != height else { return }
                // First layout adopts its natural size immediately; subsequent changes move
                // the question and transcript together with the heading's container.
                withAnimation(headingHeight == nil || reduceMotion ? nil : .springStandard) {
                    headingHeight = height
                }
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    content(title)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(title)
                        .transition(reduceMotion ? .opacity : .blurFade)
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: title)
            }
            .frame(height: headingHeight, alignment: .top)
            .clipped()
    }
}
