import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Settings text size layout", .serialized)
@MainActor
struct SettingsTypographyTests {
    private final class Measurements {
        var frames: [String: CGRect] = [:]
    }

    private struct ControlsSample: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let measurements: Measurements
        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings text")
                    .font(AngroveTheme.Typography.settingsBody)
                    .fixedSize()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controls")) }
                    action: { measurements.frames["text"] = $0 }
                SettingsLabeledControl(title: "Conversation Text Alignment") {
                    ConversationAlignmentSegmentedControl(selection: .constant(.left))
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controls")) }
                action: { measurements.frames["alignment"] = $0 }
                FontSizeSegmentedControl(selection: .constant(.medium))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controls")) }
                    action: { measurements.frames["size"] = $0 }
                FontSegmentedControl(selection: .constant(.serif))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controls")) }
                    action: { measurements.frames["font"] = $0 }
                PersonalitySegmentedControl(selection: .constant(.default))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controls")) }
                    action: { measurements.frames["personality"] = $0 }
                SettingsChoiceRow(title: "Conversation Titles",
                    detail: "Choose how your saved conversations are titled.",
                    selection: .constant(ConversationTitleOption.firstQuestion),
                    options: Array(ConversationTitleOption.allCases))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controls")) }
                    action: { measurements.frames["choice"] = $0 }
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 240 : 224, alignment: .leading)
            .padding(dynamicTypeSize.isAccessibilitySize ? 16 : 24)
            .coordinateSpace(name: "controls")
            .frame(width: 272)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @Test("Larger system text increases rendered text and controls without overlapping")
    func controlsScaleAndFit() async throws {
        var results: [[String: CGRect]] = []
        for size in [DynamicTypeSize.large, .accessibility3] {
            let measurements = Measurements()
            let window = try host(ControlsSample(measurements: measurements).dynamicTypeSize(size), width: 272, height: 1400)
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(250))
            let frames = measurements.frames
            var previous: CGRect?
            for name in ["text", "alignment", "size", "font", "personality", "choice"] {
                let frame = try #require(frames[name])
                #expect(frame.minX >= -1 && frame.maxX <= 273)
                if let previous { #expect(frame.minY >= previous.maxY + 23) }
                previous = frame
            }
            results.append(frames)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let sizeName = size == .large ? "large" : "accessibility3"
            try #require(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/angrove-settings-controls-272-\(sizeName).png"))
        }
        for name in ["text", "alignment", "size", "font", "personality", "choice"] {
            let regular = try #require(results[0][name])
            let accessible = try #require(results[1][name])
            #expect(accessible.height > regular.height)
        }
        let regularText = try #require(results[0]["text"])
        let accessibleText = try #require(results[1]["text"])
        #expect(accessibleText.width > regularText.width * 1.5)
    }

    @Test("Settings pages render with compact and accessibility system text",
          arguments: [DynamicTypeSize.large, .accessibility3], [ColorScheme.light, .dark])
    func pageSnapshots(size: DynamicTypeSize, scheme: ColorScheme) async throws {
        let textPage = TextAndDisplaySettingsView(
            conversationFontSize: .constant(.medium), conversationTextAlignment: .constant(.left),
            inputFont: .constant(.serif), responseFont: .constant(.serif))
        let appearancePage = AppearanceSettingsView(colorSchemeOverride: .constant(scheme))
        for (name, page) in [("text-display", AnyView(textPage)), ("appearance", AnyView(appearancePage))] {
            let window = try host(page.dynamicTypeSize(size).environment(\.colorScheme, scheme), width: 320, height: 1400)
            defer { window.isHidden = true }
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            try await Task.sleep(for: .milliseconds(250))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let sizeName = size == .large ? "large" : "accessibility3"
            let mode = scheme == .dark ? "dark" : "light"
            let path = "/tmp/angrove-settings-\(name)-320-\(sizeName)-\(mode).png"
            try #require(image.pngData()).write(to: URL(fileURLWithPath: path))
            print("Settings text size snapshot: \(path)")
        }
    }

    private func host<Content: View>(_ content: Content, width: Int, height: Int) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return window
    }
}
