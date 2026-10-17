import AppKit
import Observation
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacGlobalModelControlsTests {
    @Test func dockRemainsMountedDuringExitArrivalAndPageChanges() async throws {
        let state = DockFixtureState()
        let host = NSHostingView(rootView: PersistentDockFixture(state: state))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.mounts == 1)
        state.transition.navigate(to: MacWorkspacePage(destination: .settings)) { state.page = .settings }
        try await wait { !state.transition.showsControls }
        try await wait { !state.transition.isTransitioning }
        #expect(state.page == .settings)
        #expect(state.mounts == 1)
        #expect(state.removals == 0)
        state.transition.navigate(to: MacWorkspacePage(destination: .library)) { state.page = .library }
        try await wait { !state.transition.isTransitioning }
        #expect(state.mounts == 1)
        #expect(state.removals == 0)
    }

    @Test func completedInsightOpensInTheDockWithoutASheet() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let session = MacConversationState()
            session.configure(preview: true)
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let center = ModelCompletionNotificationCenter()
            let concept = ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                meaning: "Practical wisdom that guides sound judgment and action.", example: "")
            let host = NSHostingView(rootView: ConversationDockFixture(session: session, runtime: runtime)
                .environment(\.modelCompletionNotifications, center).environment(\.colorScheme, scheme))
            let window = makeWindow(host)
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(300))
            center.post(title: concept.word, kind: .insightDefinition, postsSystemNotification: false) {
                session.selectedDefinition = concept
            }
            center.open(id: try #require(center.notifications.first).id)
            try await Task.sleep(for: .milliseconds(500))
            #expect(session.selectedDefinition == concept)
            #expect(center.notifications.isEmpty)
            #expect(window.attachedSheet == nil)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-global-dock-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func wait(until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(predicate())
    }
}

@MainActor @Observable
private final class DockFixtureState {
    let transition = MacPageTransition(fadeDuration: 0.04, pauseDuration: 0.02)
    var page = MacDestination.home
    var mounts = 0
    var removals = 0
    let queue = ModelTaskQueue()
    let popup = ModelTasksPopupState()
}

private struct PersistentDockFixture: View {
    let state: DockFixtureState
    var body: some View {
        Text(state.page.headingTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                MacGlobalModelControlsDock(published: MacGlobalModelControls(configuration: configuration),
                    isVisible: state.transition.showsControls, modelTasks: state.queue, queuePopup: state.popup)
            }
    }
    private var configuration: ModelControlsConfiguration {
        var value = ModelControlsConfiguration(id: "stable")
        value.buttons = AnyView(Text("Model Tasks")
            .onAppear { state.mounts += 1 }.onDisappear { state.removals += 1 })
        return value
    }
}

private struct ConversationDockFixture: View {
    let session: MacConversationState
    let runtime: MacApplicationRuntime
    @State private var tree = MacTreeControls()
    @State private var popup = ModelTasksPopupState()
    var body: some View {
        MacWorkspaceControlSlot(session: session, tree: tree, runtime: runtime,
            isCanvasMode: false, isVisible: true, hasQuestion: false, treeCard: nil,
            onOpenTree: {}, onCloseTree: {}, onSend: {}, onClearDraft: {}, queuePopup: popup)
            .overlayPreferenceValue(MacGlobalModelControlsKey.self) { published in
                MacGlobalModelControlsDock(published: published, isVisible: true,
                    modelTasks: runtime.modelTasks, queuePopup: popup)
            }
            .background(AngroveTheme.Colors.canvas)
    }
}
