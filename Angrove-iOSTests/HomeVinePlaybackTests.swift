import Testing
import SwiftUI
import UIKit
@testable import Angrove_iOS

@Suite("Home vine entrance and idle")
@MainActor
struct HomeVinePlaybackTests {
    @Test("All 24 entrance frames play before the one-second idle loop")
    func entranceThenIdle() {
        var playback = HomeVinePlayback()
        var entranceDuration = 0.0
        for frame in 1...24 {
            #expect(!playback.isIdle)
            #expect(playback.assetName == String(format: "HomeVinePaint%02d", frame))
            entranceDuration += playback.frameDuration
            playback.advance()
        }
        #expect(abs(entranceDuration - 4) < 0.000_001)
        #expect(playback.assetName == "HomeVineWind01")

        var idleDuration = 0.0
        for _ in 0..<4 {
            #expect(playback.isIdle)
            idleDuration += playback.frameDuration
            playback.advance()
        }
        #expect(idleDuration == 1)
        #expect(playback.assetName == "HomeVineWind01")
        for _ in 0..<24 { playback.advance() }
        #expect(playback.isIdle)
        #expect(playback.assetName == "HomeVineWind01")
    }

    @Test("Reduce Motion skips directly to the finished artwork")
    func skipEntrance() {
        var playback = HomeVinePlayback()
        playback.advance()
        playback.finishEntrance()
        #expect(playback.isIdle)
        #expect(playback.assetName == "HomeVineWind01")
        playback.advance()
        #expect(playback.assetName == "HomeVineWind02")
    }

    @Test("Every sprite is bundled and the handoff matches pixel for pixel")
    func bundledArtwork() throws {
        for (prefix, count) in [("HomeVinePaint", 24), ("HomeVineWind", 4)] {
            for index in 1...count {
                let image = try #require(UIImage(named: String(format: "%@%02d", prefix, index)))
                #expect(image.size.width == image.size.height)
            }
        }
        let end = try #require(UIImage(named: "HomeVinePaint24"))
        let start = try #require(UIImage(named: "HomeVineWind01"))
        #expect(end.pngData() == start.pngData())
    }

    @Test("The left vine plays its own bundled frames with the same timing")
    func leftVine() throws {
        var playback = HomeVinePlayback(side: .left)
        #expect(playback.assetName == "HomeVineLeftPaint01")
        for _ in 0..<24 { playback.advance() }
        #expect(playback.isIdle)
        #expect(playback.assetName == "HomeVineLeftWind01")

        for (prefix, count) in [("HomeVineLeftPaint", 24), ("HomeVineLeftWind", 4)] {
            for index in 1...count {
                let image = try #require(UIImage(named: String(format: "%@%02d", prefix, index)))
                #expect(abs(image.size.width / image.size.height - HomeVineSide.left.aspectRatio) < 0.001)
            }
        }
        let end = try #require(UIImage(named: "HomeVineLeftPaint24"))
        let start = try #require(UIImage(named: "HomeVineLeftWind01"))
        #expect(end.pngData() == start.pngData())
    }

    @Test("The entrance waits for the boot reveal before painting")
    func waitsForBootReveal() async throws {
        let playback = HomeVinePlaybackController()
        func content(ready: Bool) -> some View {
            HomeVineWind(width: 120)
                .environment(\.scenePhase, .active)
                .environment(\.isBootRevealComplete, ready)
                .environment(\.homeVinePlayback, playback)
                .background(AngroveTheme.Colors.canvas)
        }
        let controller = UIHostingController(rootView: content(ready: false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }

        try await Task.sleep(for: .milliseconds(500))
        #expect(playback.playback.frame == 0)
        #expect(!playback.playback.isIdle)

        controller.rootView = content(ready: true)
        try await Task.sleep(for: .milliseconds(800))
        #expect(playback.playback.frame > 0)
        #expect(!playback.playback.isIdle)
    }
}
