import AppKit
import Testing
@testable import AngroveMac

@MainActor
struct MacDisplayLinkDriverTests {
    @Test func nativeDisplayLinkTicksAndStopsWithoutDuplicatingStarts() async throws {
        _ = try #require(NSScreen.main)
        let driver = DisplayLinkDriver()
        defer { driver.stop() }
        var timestamps: [CFTimeInterval] = []
        driver.onTick = { timestamps.append($0) }
        driver.start()
        driver.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while timestamps.count < 3 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(timestamps.count >= 3)
        #expect(Set(timestamps).count == timestamps.count)
        driver.stop()
        let stoppedCount = timestamps.count
        try await Task.sleep(for: .milliseconds(100))
        #expect(timestamps.count == stoppedCount)
    }
}
