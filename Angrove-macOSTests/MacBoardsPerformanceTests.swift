import AppKit
import Observation
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsPerformanceTests {
    @Test func cameraAndChromeChangesKeepConversationContentEqual() {
        let (board, item, session, runtime) = fixture()
        let original = WorktreeQuestionCard(board: board, item: item, session: session, runtime: runtime, isOpen: true)
        var moved = item
        moved.origin = CGPoint(x: 820, y: -400)
        moved.label = "Renamed window"
        moved.labelRevision += 1
        for scale: CGFloat in [0.28, 0.5, 1, 1.8, 2.6] {
            board.viewport = WorktreeViewport(scale: scale, offset: CGSize(width: 200, height: -100))
            board.select(item.id)
            #expect(original == WorktreeQuestionCard(board: board, item: moved, session: session, runtime: runtime, isOpen: true))
        }
        for change: (inout WorktreeBoard.Item) -> Void in [
            { $0.followUp = "A follow-up" },
            { $0.followUpID = UUID() },
            { $0.size = CGSize(width: 600, height: 480) },
            { $0.visibleTurnLimit = 10 },
            { $0.id = UUID() }
        ] {
            var edited = item
            change(&edited)
            #expect(original != WorktreeQuestionCard(board: board, item: edited, session: session, runtime: runtime, isOpen: true))
        }
        #expect(original != WorktreeQuestionCard(board: board, item: item, session: session, runtime: runtime, isOpen: false))
        #expect(original != WorktreeQuestionCard(board: WorktreeBoard(), item: item, session: session, runtime: runtime, isOpen: true))
        #expect(original != WorktreeQuestionCard(board: board, item: item, session: MacConversationState(), runtime: runtime, isOpen: true))
    }

    @Test func liveResponsesStillInvalidateTheEquatableCard() {
        let (board, item, session, runtime) = fixture()
        let card = WorktreeQuestionCard(board: board, item: item, session: session, runtime: runtime, isOpen: true)
        let cameraChange = ChangeFlag()
        withObservationTracking { _ = card.body } onChange: { cameraChange.mark() }
        board.viewport = WorktreeViewport(scale: 0.5, offset: .zero)
        #expect(!cameraChange.changed)
        let responseChange = ChangeFlag()
        withObservationTracking { _ = card.body } onChange: { responseChange.mark() }
        session.branches[0].activeChatBlocks[0] = .text("The live response changed.")
        #expect(responseChange.changed)
    }

    @Test func conversationWindowsRenderAcrossZoomAndLiveUpdates() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let (board, item, session, runtime) = fixture()
            let driver = ZoomDriver()
            let host = NSHostingView(rootView: ZoomFixture(board: board, item: item, runtime: runtime, driver: driver)
                .environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(750))
            for scale: CGFloat in [0.5, 1, 2.6, 1] {
                driver.scale = scale
                try await Task.sleep(for: .milliseconds(50))
                host.layoutSubtreeIfNeeded()
            }
            let before = try bitmap(host)
            session.branches[0].activeChatBlocks[0] = .text("A changed answer remains visible after zooming.")
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let after = try bitmap(host)
            #expect(before != after)
            try after.write(to: URL(filePath: "/tmp/angrove-boards-performance-\(scheme == .light ? "light" : "dark").png"))
            #expect(board.items.count == 1)
            #expect(board.items[0].session === session)
        }
    }

    private func bitmap(_ host: NSView) throws -> Data {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func fixture() -> (WorktreeBoard, WorktreeBoard.Item, MacConversationState, MacApplicationRuntime) {
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is practical wisdom?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("Practical wisdom guides sound judgment in daily life.")]
        for turn in 1...30 {
            branch.activeChatBlocks.append(.user("Question \(turn)", [], []))
            branch.activeChatBlocks.append(.text(String(repeating: "A thoughtful answer. ", count: 60)))
        }
        session.branches = [branch]
        session.selectedBranch = branch.id
        let board = WorktreeBoard()
        var item = WorktreeBoard.Item(origin: CGPoint(x: 80, y: 100))
        item.session = session
        item.size = CGSize(width: 400, height: 420)
        board.items = [item]
        return (board, item, session, runtime)
    }
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var changed: Bool { lock.withLock { value } }
    func mark() { lock.withLock { value = true } }
}

@MainActor @Observable private final class ZoomDriver {
    var scale: CGFloat = 1
}

private struct ZoomFixture: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let runtime: MacApplicationRuntime
    let driver: ZoomDriver

    var body: some View {
        WorktreeItemView(board: board, item: item, scale: driver.scale, runtime: runtime)
            .equatable()
            .fixedSize()
            .scaleEffect(driver.scale, anchor: .topLeading)
            .frame(width: 1000, height: 760, alignment: .topLeading)
            .padding(60)
            .background(AngroveTheme.Colors.canvas)
    }
}
