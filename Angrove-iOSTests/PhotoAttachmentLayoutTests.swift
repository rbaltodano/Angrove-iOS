import Observation
import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Photo attachment layout", .serialized)
@MainActor
struct PhotoAttachmentLayoutTests {
    @Observable
    final class Bounds {
        var frames: [CGRect] = []
    }

    private struct Sample: View {
        let files: [UploadedFile]
        let bounds: Bounds

        var body: some View {
            UploadedFileStrip(files: files, onRemove: { _ in })
                .onPreferenceChange(AttachmentScrollBoundsKey.self) { bounds.frames = $0 }
        }
    }

    @Test("Multiple attachments overflow into a protected horizontal scroll region",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func multiplePhotosScroll(style: UIUserInterfaceStyle) async throws {
        let bounds = Bounds()
        let files = (0..<6).map {
            UploadedFile(name: "Photo \($0)", imageData: nil, rotationDegrees: $0.isMultiple(of: 2) ? -4 : 4)
        }
        let window = host(files: files, bounds: bounds, style: style)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(250))
        let scroll = try #require(descendants(window).compactMap { $0 as? UIScrollView }.first)
        #expect(scroll.contentSize.width > scroll.bounds.width)
        #expect(scroll.contentSize.height <= scroll.bounds.height + 1)
        let region = try #require(bounds.frames.first)
        #expect(region.width <= 320)
        #expect(AttachmentScrollBoundsKey.contains(CGPoint(x: region.midX, y: region.midY), in: bounds.frames))
        #expect(!AttachmentScrollBoundsKey.contains(CGPoint(x: region.midX, y: region.maxY + 20), in: bounds.frames))
        scroll.setContentOffset(CGPoint(x: scroll.contentSize.width - scroll.bounds.width, y: 0), animated: false)
        #expect(scroll.contentOffset.x > 0)
    }

    @Test("Empty attachments reserve no scrolling exclusion region")
    func emptyStrip() async throws {
        let bounds = Bounds()
        let window = host(files: [], bounds: bounds, style: .dark)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        #expect(bounds.frames.isEmpty)
        #expect(!descendants(window).contains { $0 is UIScrollView })
    }

    @Test("Remove icon stays dark against its light photo badge in both appearances",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func removeIconContrast(style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let foreground = UIColor(AngroveTheme.Colors.deepSurface).resolvedColor(with: traits)
        let background = UIColor(AngroveTheme.Colors.uploadBorder).resolvedColor(with: traits)
        var foregroundRed: CGFloat = 0
        var backgroundRed: CGFloat = 0
        foreground.getRed(&foregroundRed, green: nil, blue: nil, alpha: nil)
        background.getRed(&backgroundRed, green: nil, blue: nil, alpha: nil)
        #expect(backgroundRed - foregroundRed > 0.7)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func host(files: [UploadedFile], bounds: Bounds, style: UIUserInterfaceStyle) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow()
        }
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        window.overrideUserInterfaceStyle = style
        let controller = UIHostingController(rootView: Sample(files: files, bounds: bounds))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return window
    }
}
