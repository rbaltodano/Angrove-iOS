//
//  HomeVineWind.swift
//  Angrove-iOS
//

import SwiftUI

/// The home scroll position, shared with the vine for its parallax. The dashboard only writes
/// it, so a scroll updates the vine alone and never re-evaluates the dashboard.
@Observable
final class HomeVineParallax {
    var scrollOffset: CGFloat = 0
}

/// Which of the website's two painted vines to draw.
enum HomeVineSide {
    /// Hangs from the right edge behind the greeting.
    case right
    /// Hangs from the left edge below the Question of the Day.
    case left

    var assetPrefix: String {
        switch self {
        case .right: "HomeVine"
        case .left: "HomeVineLeft"
        }
    }

    /// The website frame size: the right vine is square, the left one a little taller.
    var aspectRatio: CGFloat {
        switch self {
        case .right: 1
        case .left: 352.0 / 362.0
        }
    }

    /// How far the vine hangs past its screen edge, hiding the stem the artwork is cut on.
    var edgeOverhang: CGFloat {
        switch self {
        case .right: 40
        case .left: -40
        }
    }
}

/// Painted ivy hanging from an edge of the home screen, blowing in the wind.
///
/// With a `parallax` source the vine also falls behind the content as it scrolls, by `depth`
/// of the scroll distance, so it reads as farther back than the text. It stops drifting after
/// `maxDrift` points of scroll, and Reduce Motion keeps it fixed to the content.
///
/// The website's 24 paint-on sprites play once at 6 fps (four seconds), followed by its
/// four final painted sprites at 4 fps (one second per loop). The final entrance and first idle
/// share the same artwork. Leaving the screen or backgrounding pauses playback;
/// Reduce Motion skips the entrance and shows the first idle frame. `delay` holds the entrance
/// back, and `returnDelay` the return fade, so a second vine follows the first.
///
/// Once the entrance has played, returning to the screen fades the vine in from blurred instead.
struct HomeVineWind: View {
    var side: HomeVineSide = .right
    var width: CGFloat = 176
    var parallax: HomeVineParallax? = nil
    var depth: CGFloat = 0.15
    var maxDrift: CGFloat = 700
    var delay: TimeInterval = 0
    var returnDelay: TimeInterval = 0

    @State private var localPlayback = HomeVinePlaybackController()
    @State private var isShown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isBootRevealComplete) private var isBootRevealComplete
    @Environment(\.homeVinePlayback) private var sharedPlayback

    private var controller: HomeVinePlaybackController { sharedPlayback ?? localPlayback }
    private var playbackPath: ReferenceWritableKeyPath<HomeVinePlaybackController, HomeVinePlayback> {
        side == .left ? \.leftPlayback : \.playback
    }

    private var shouldAnimate: Bool {
        !reduceMotion && scenePhase == .active && isBootRevealComplete
    }

    var body: some View {
        sprite(name: reduceMotion ? "\(side.assetPrefix)Wind01" : controller[keyPath: playbackPath].assetName)
        // The complete website frames leave room below the bottom leaf.
        .frame(width: width, height: width / side.aspectRatio)
        .offset(x: side.edgeOverhang, y: driftOffset)
        // Hidden only on a return visit, until the fade starts; the first visit paints on.
        .animation(returnAnimation(duration: 0.6)) {
            $0.opacity(isVisible ? 1 : 0)
                .blur(radius: isVisible || reduceMotion ? 0 : 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard controller[keyPath: playbackPath].isIdle else {
                isShown = true
                return
            }
            isShown = true
        }
        .onDisappear { isShown = false }
        .task(id: shouldAnimate) {
            let controller = controller
            let path = playbackPath
            if reduceMotion {
                controller[keyPath: path].finishEntrance()
                return
            }
            guard shouldAnimate else { return }
            do {
                if controller[keyPath: path] == HomeVinePlayback(side: side) {
                    try await Task.sleep(for: .seconds(delay))
                }
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(controller[keyPath: path].frameDuration))
                    try Task.checkCancellation()
                    controller[keyPath: path].advance()
                }
            } catch is CancellationError {
                // Keep the current frame for the next appearance or foreground scene.
            } catch {
                return
            }
        }
    }

    private func returnAnimation(duration: TimeInterval) -> Animation {
        .timingCurve(0.55, 0, 0.17, 1, duration: duration).delay(returnDelay)
    }

    private var isVisible: Bool {
        isShown || !controller[keyPath: playbackPath].isIdle
    }

    /// How far the vine has fallen behind the content: a share of the scroll distance. Pulling
    /// down past the top (a negative offset) does not move it.
    private var driftOffset: CGFloat {
        guard !reduceMotion, let parallax else { return 0 }
        return min(max(parallax.scrollOffset, 0), maxDrift) * depth
    }

    private func sprite(name: String) -> some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .transaction { $0.animation = nil }
    }

}

/// Owned by the app shell, outliving dashboard removal during navigation.
@MainActor
@Observable
final class HomeVinePlaybackController {
    var playback = HomeVinePlayback()
    var leftPlayback = HomeVinePlayback(side: .left)
}

/// Retained by the view so resuming the screen never replays a completed entrance.
struct HomeVinePlayback: Equatable {
    let side: HomeVineSide
    private(set) var isIdle = false
    private(set) var frame = 0

    init(side: HomeVineSide = .right) {
        self.side = side
    }

    var frameDuration: TimeInterval { isIdle ? 1.0 / 4 : 1.0 / 6 }
    var assetName: String {
        String(format: "%@%@%02d", side.assetPrefix, isIdle ? "Wind" : "Paint", frame + 1)
    }

    mutating func advance() {
        if isIdle {
            frame = (frame + 1) % 4
        } else if frame < 23 {
            frame += 1
        } else {
            finishEntrance()
        }
    }

    mutating func finishEntrance() {
        isIdle = true
        frame = 0
    }
}

#Preview {
    HomeVineWind()
        .padding()
        .background(AngroveTheme.Colors.canvas)
}
