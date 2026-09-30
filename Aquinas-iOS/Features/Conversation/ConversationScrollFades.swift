import SwiftUI

struct ConversationScrollFades: View {
    let topHeight: CGFloat
    let bottomHeight: CGFloat
    let topOpacity: Double
    let showsBottomFade: Bool

    static func topFadeHeight(compact: Bool) -> CGFloat {
        compact ? 96 : 150
    }

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: AquinasTheme.Colors.canvas.opacity(0.97), location: 0),
                .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0.33),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .frame(height: topHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(topOpacity)
        .animation(.easeInOut(duration: 0.28), value: topOpacity)
        .allowsHitTesting(false)

        if showsBottomFade {
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 0),
                    .init(color: AquinasTheme.Colors.canvas, location: 1)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 0.84)
            )
            .frame(height: bottomHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
