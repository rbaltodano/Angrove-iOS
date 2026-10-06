import SwiftUI

/// Node Concept appearance and hit area; camera and discovery actions stay with the canvas.
struct InsightTreeCanvasConceptNode: View {
    let title: String
    let isSuggested: Bool
    let isUndiscovered: Bool
    let hasAppeared: Bool
    let labelOpacity: Double
    let backgroundColor: Color
    let scale: CGFloat
    let opacity: Double
    let position: CGPoint
    let zOrder: Double
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 18) {
                // Shares the label's own blur+animation treatment (instead of relying only on
                // the outer ZStack's transition) so the icon and label always move together —
                // previously the icon had no entrance treatment of its own and stayed static
                // while the label blurred/faded in.
                Image(systemName: isSuggested ? "sparkles" : "brain.head.profile")
                    .font(.system(size: isSuggested ? 20 : 24, weight: .semibold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .blur(radius: hasAppeared ? 0 : 8)
                    .animation(.springRelaxed.delay(0.1), value: hasAppeared)

                ConversationHeading(title: title) { label in
                    Text(label)
                        .font(.custom("Figtree-Bold", size: 18))
                        .lineSpacing(8)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                    .opacity(labelOpacity)
                    .blur(radius: hasAppeared ? 0 : 8)
                    .animation(.springRelaxed.delay(0.1), value: hasAppeared)
            }
            .padding(8)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: backgroundColor, radius: 36, x: 0, y: 0)
            .frame(width: isSuggested ? 220 : 260)
            .overlay(alignment: .topLeading) {
                if isUndiscovered {
                    Circle()
                        .fill(AngroveTheme.Colors.unreadDot)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(backgroundColor, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)


            if isSuggested {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 20, y: -10)
            }
        }
        .offset(y: hasAppeared ? 0 : 24)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.springRelaxed.delay(0.1), value: hasAppeared)
        .transition(.glideFadeUp)
        // 2.5D depth: farther nodes render smaller, dimmer, and behind nearer ones.
        .scaleEffect(scale)
        // While rotate-dragging a chip, every Node recedes so the dragged chip alone stands out.
        // No `.animation(_, value:)` here — see the matching note in `insightLabel`; a placed
        // Midpoint's `.position()` below needs to ride whatever ambient animation is active
        // (its live drag-follow), not get locked to a spring keyed only to `draggingChipID`.
        .opacity(opacity)
        .position(position)
        .zIndex(zOrder)
    }
}
