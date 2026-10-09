import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Library listening ring entrance", .serialized)
@MainActor
struct LibraryListeningRingTests {
    @Test("A newly displayed ring fills to the current work position")
    func animatedEntrance() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        let ring = LibraryListeningProgressRing(progress: 0.75)
            .scaleEffect(5)
            .frame(width: 120, height: 120)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.colorScheme, .light)
            .ignoresSafeArea()
        let controller = UIHostingController(rootView: ring)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil }
        func snapshot() throws -> Data {
            controller.view.layoutIfNeeded()
            return try #require(UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }.pngData())
        }
        try await Task.sleep(for: .milliseconds(100))
        let early = try snapshot()
        try await Task.sleep(for: .milliseconds(220))
        let middle = try snapshot()
        try await Task.sleep(for: .milliseconds(650))
        let filled = try snapshot()
        if !UIAccessibility.isReduceMotionEnabled {
            #expect(early != middle)
            #expect(middle != filled)
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(try snapshot() == filled)
        Attachment.record(early, named: "listening-ring-early.png")
        Attachment.record(middle, named: "listening-ring-middle.png")
        Attachment.record(filled, named: "listening-ring-filled.png")
    }
}
