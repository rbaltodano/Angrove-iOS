import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("App icon selector layout", .serialized)
@MainActor
struct AppIconSelectionCardTests {
    @Test("Both alternate icons and preview assets are bundled")
    func bundledIcons() throws {
        let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        for option in AppIconOption.allCases {
            #expect(alternates[option.rawValue] != nil)
            #expect(UIImage(named: option.previewAsset) != nil)
        }
    }

    @Test("Preview images remain distinct and inside compact and standard cards",
          arguments: [272, 342], [UIUserInterfaceStyle.light, .dark])
    func previewsFit(width: Int, style: UIUserInterfaceStyle) async throws {
        let card = AppIconSelectionCard(selectedIcon: .light, onSelect: { _ in })
            .environment(\.colorScheme, style == .dark ? .dark : .light)
            .frame(width: CGFloat(width))
            .frame(maxHeight: .infinity, alignment: .top)
        let controller = UIHostingController(rootView: card)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 280)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let appearance = style == .dark ? "dark" : "light"
        let path = "/tmp/angrove-icon-selector-\(width)-\(appearance).png"
        try #require(snapshot.pngData()).write(to: URL(fileURLWithPath: path))
        print("App icon layout snapshot: \(path)")

        // Locate each actual rendered preview using its interior pixels rather than
        // assuming that the HStack placed its children at their requested positions.
        let pixels = try rgba(snapshot)
        var frames: [CGRect] = []
        for option in AppIconOption.allCases {
            let preview = try #require(UIImage(named: option.previewAsset))
            let template = UIGraphicsImageRenderer(size: CGSize(width: 84, height: 84), format: format)
                .image { _ in preview.draw(in: CGRect(x: 0, y: 0, width: 84, height: 84)) }
            let reference = try rgba(template)
            let match = bestMatch(pixels: pixels, width: width, reference: reference)
            #expect(match.error < 22, "The bundled 84-point preview must match the rendered image")
            frames.append(CGRect(x: match.x, y: match.y, width: 84, height: 84))
        }
        let light = frames[0]
        let dark = frames[1]
        #expect(!light.intersects(dark))
        #expect(light.minX >= 23 && dark.maxX <= CGFloat(width - 23))
        #expect(abs(light.minY - dark.minY) <= 1)
        #expect(light.maxY < 230 && dark.maxY < 230)
        #expect(abs(light.midX - CGFloat(width) / 2 + (dark.midX - CGFloat(width) / 2)) <= 2)
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cgImage.width,
                height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        try #require(rendered)
        return bytes
    }

    @Test("Appearance page keeps both icon choices aligned below its background controls",
          arguments: [320, 390], [UIUserInterfaceStyle.light, .dark])
    func appearancePage(width: Int, style: UIUserInterfaceStyle) async throws {
        let page = AppearanceSettingsView(colorSchemeOverride: .constant(style == .dark ? .dark : .light))
            .environment(\.colorScheme, style == .dark ? .dark : .light)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        // Render the scrollable content: background cards now precede the icon card.
        let contentHeight = 1600
        window.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        window.overrideUserInterfaceStyle = style
        let controller = UIHostingController(rootView: page)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let appearance = style == .dark ? "dark" : "light"
        let path = "/tmp/angrove-icon-appearance-\(width)-\(appearance).png"
        try #require(snapshot.pngData()).write(to: URL(fileURLWithPath: path))
        print("Appearance page snapshot: \(path)")
        let pixels = try rgba(snapshot)
        var frames: [CGRect] = []
        for option in AppIconOption.allCases {
            let preview = try #require(UIImage(named: option.previewAsset))
            let template = UIGraphicsImageRenderer(size: CGSize(width: 84, height: 84), format: format)
                .image { _ in preview.draw(in: CGRect(x: 0, y: 0, width: 84, height: 84)) }
            let reference = try rgba(template)
            let match = bestMatch(pixels: pixels, width: width, reference: reference, maximumY: contentHeight - 84)
            #expect(match.error < 22)
            frames.append(CGRect(x: match.x, y: match.y, width: 84, height: 84))
        }
        #expect(!frames[0].intersects(frames[1]))
        #expect(frames[0].minX >= 47 && frames[1].maxX <= CGFloat(width - 47))
        #expect(frames.allSatisfy { $0.minY > 150 && $0.maxY < CGFloat(contentHeight) })
        #expect(abs(frames[0].minY - frames[1].minY) <= 1)
    }

    private func bestMatch(pixels: [UInt8], width: Int, reference: [UInt8], maximumY: Int = 150) -> (x: Int, y: Int, error: Double) {
        var best = (x: 0, y: 0, error: Double.infinity)
        for y in 40...maximumY {
            for x in 20...(width - 104) {
                var difference = 0
                for sampleY in stride(from: 10, through: 74, by: 8) {
                    for sampleX in stride(from: 10, through: 74, by: 8) {
                        let actual = ((y + sampleY) * width + x + sampleX) * 4
                        let expected = (sampleY * 84 + sampleX) * 4
                        for channel in 0..<3 {
                            difference += abs(Int(pixels[actual + channel]) - Int(reference[expected + channel]))
                        }
                    }
                }
                let error = Double(difference) / (81 * 3)
                if error < best.error { best = (x, y, error) }
            }
        }
        return best
    }
}
