import AppKit
import Observation
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacModelControlSizingTests {
    @Test func contextClickTargetDoesNotInflateTheIdlePill() async throws {
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let probe = PillProbe()
            let host = NSHostingView(rootView: PillFixture(probe: probe).environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            let deadline = ContinuousClock.now + .seconds(3)
            while probe.pill == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let pill = try #require(probe.pill)
            #expect(pill.height > 0 && pill.height <= 70)
            #expect(pill.width > 0 && pill.width < 190)
            try await Task.sleep(for: .milliseconds(650))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-model-control-sizing-\(name).png"))
        }
    }
}

@MainActor @Observable
private final class PillProbe { var pill: CGRect? }

private struct PillFixture: View {
    let probe: PillProbe
    @State private var context = ContextCardState()
    @State private var queue = ModelTaskQueue()

    var body: some View {
        Color.clear
            .background {
                InquiryControlDock(isCanvasMode: false,
                    showFilePicker: .constant(false), showPhotoPicker: .constant(false), showCamera: .constant(false),
                    selectedPersonality: .constant("default"), isPersonalityMenuOpen: .constant(false), isAtBottom: true,
                    onScrollToBottom: {}, onViewEntireCanvas: {}, onOpenInsights: {},
                    modelTasks: queue, keepsIdleModelStatus: true, contextCard: context)
            }
            .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { configuration in
                ModelControlsHost(configuration: configuration)
            }
            .overlayPreferenceValue(MacModelControlHoverKey.self) { preference in
                GeometryReader { geometry in
                    if let pill = preference.pill {
                        Color.clear.task(id: geometry[pill]) { probe.pill = geometry[pill] }
                    }
                }
            }
            .background(AngroveTheme.Colors.canvas)
    }
}
