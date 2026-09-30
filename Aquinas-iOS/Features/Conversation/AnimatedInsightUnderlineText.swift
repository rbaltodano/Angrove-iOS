import SwiftUI

struct AnimatedInsightUnderlineText: View {
    let text: String
    let font: Font
    let color: Color
    let isVisible: Bool
    let animationDelay: Double
    let underlineOpacity: Double

    @State private var underlineProgress: CGFloat = 0

    var body: some View {
        Text(text)
            .bold()
            .font(font)
            .foregroundColor(color)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(color)
                    .frame(height: 1)
                    .scaleEffect(x: underlineProgress, y: 1, anchor: .leading)
                    .offset(y: 1.5)
                    .opacity(underlineOpacity)
                    .animation(
                        .easeInOut(duration: 0.3),
                        value: underlineOpacity
                    )
            }
            .onAppear {
                if isVisible {
                    animateUnderlineIn()
                }
            }
            .onChange(of: isVisible) { _, visible in
                if visible {
                    animateUnderlineIn()
                } else {
                    underlineProgress = 0
                }
            }
    }

    private func animateUnderlineIn() {
        guard underlineProgress < 1 else { return }
        underlineProgress = 0
        withAnimation(.easeOut(duration: 0.42).delay(animationDelay)) {
            underlineProgress = 1
        }
    }
}
