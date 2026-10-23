import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsFrameRateTests {
    @Test func measuresDeliveredFramesAndIncludesStalls() {
        for rate in [60, 120] {
            var sample = WorktreeFrameRateSample()
            #expect(sample.record(at: 0) == nil)
            for frame in 1..<(rate / 2) {
                #expect(sample.record(at: Double(frame) / Double(rate)) == nil)
            }
            #expect(sample.record(at: 0.5) == rate)
            // One delivered callback after a half-second stall reports 2 FPS, not refresh rate.
            #expect(sample.record(at: 1) == 2)
            for frame in 1..<(rate / 2) {
                #expect(sample.record(at: 1 + Double(frame) / Double(rate)) == nil)
            }
            #expect(sample.record(at: 1.5) == rate)
        }
    }

    @Test func ignoresInvalidAndRepeatedTimestamps() {
        var sample = WorktreeFrameRateSample()
        #expect(sample.record(at: .nan) == nil)
        #expect(sample.record(at: 0) == nil)
        #expect(sample.record(at: 0) == nil)
        #expect(sample.record(at: -1) == nil)
        #expect(sample.record(at: .infinity) == nil)
        #expect(sample.record(at: 0.5) == 2)
        sample = WorktreeFrameRateSample()
        #expect(sample.record(at: 100) == nil)
        #expect(sample.record(at: 100.5) == 2)
    }

    @Test func nativeDisplayLinkSamplesAndStopsWithTheView() async throws {
        let surface = WorktreeFrameRateInput.FrameRateSurface()
        var rates: [Int] = []
        surface.onSample = { rates.append($0) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        defer { surface.stop(); window.contentView = nil; window.close() }
        surface.setActive(true)
        window.orderFront(nil)
        for _ in 0..<30 {
            if !rates.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(rates.first.map { $0 > 0 } == true)
        surface.setActive(false)
        let count = rates.count
        try await Task.sleep(for: .milliseconds(600))
        #expect(rates.count == count)
    }

    @Test func labelRendersAtRequestedInsetsInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let root = AngroveTheme.Colors.canvas
                .overlay(alignment: .topTrailing) {
                    WorktreeFrameRateLabel(framesPerSecond: 60)
                        .padding([.top, .trailing], 24)
                }
                .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-boards-fps-\(scheme == .light ? "light" : "dark").png"))
        }
    }
}
