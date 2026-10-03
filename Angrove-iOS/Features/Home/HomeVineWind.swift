//
//  HomeVineWind.swift
//  Angrove-iOS
//

import SwiftUI

/// Painted ivy hanging from the right edge of the home screen, blowing in the wind.
///
/// Twelve sprites (`HomeVineWind01`…`HomeVineWind12`) play in order, one every 0.2s, so the loop
/// takes 2.4s, the same sheet and timing as the website's masthead vine. Reduce Motion, and a
/// paused scene, leave the first sprite on screen.
///
/// `HomeVineGrow01`…`HomeVineGrow23` are the growth sprites, kept in the asset catalog for a
/// possible grow-in; nothing plays them now.
struct HomeVineWind: View {
    var width: CGFloat = 176

    private static let frameCount = 12
    private static let frameDuration: TimeInterval = 0.2
    /// Sprite aspect ratio (358 × 342 px).
    private static let aspectRatio: CGFloat = 358 / 342

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAnimate: Bool {
        !reduceMotion && scenePhase == .active
    }

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.periodic(from: .now, by: Self.frameDuration)) { context in
                    sprite(frame: Self.frame(at: context.date))
                }
            } else {
                sprite(frame: 0)
            }
        }
        .frame(width: width, height: width / Self.aspectRatio)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sprite(frame: Int) -> some View {
        Image(String(format: "HomeVineWind%02d", frame + 1))
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .transaction { $0.animation = nil }
    }

    /// The sprite index for a moment in time, counted from a fixed reference so the vine keeps
    /// its place in the loop when the view reappears.
    private static func frame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / frameDuration) % frameCount
    }
}

#Preview {
    HomeVineWind()
        .padding()
        .background(AngroveTheme.Colors.canvas)
}
