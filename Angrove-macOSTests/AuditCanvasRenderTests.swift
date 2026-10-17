import Foundation
import SwiftUI
import AppKit
import Testing
@testable import AngroveMac

@Suite("Canvas zoom appearance")
@MainActor struct AuditCanvasRenderTests {
    @Test("Small-screen light and dark dot fields render at full, fading and hidden zoom")
    func dotFieldSnapshots() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("angrove-audit-canvas-AngroveMac")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            for scale in [1.0, 0.5, 0.28] {
                let content = AnimatedDotGridBackground(settledOffset: .zero, settledScale: scale)
                    .frame(width: 375, height: 667)
                    .background(AngroveTheme.Colors.insightTreeCanvas)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let data = try #require(renderer.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
                let file = output.appendingPathComponent("grid-\(dark ? "dark" : "light")-\(scale).png")
                try data.write(to: file)
                print("CANVAS_RENDER \(file.path)")
            }
        }
    }
}
