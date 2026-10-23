import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsInteractionTests {
    @Test func boardAnswersAreVisibleOnlyOnTheirOpenBoard() {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.configure(preview: true)
        session.savesConversation = false
        var item = WorktreeBoard.Item(origin: .zero)
        item.session = session
        board.items = [item]
        let other = UUID()
        #expect(MacCompletionNotifications.isViewing(session.id, destination: .worktree, conversationID: other, board: board))
        #expect(!MacCompletionNotifications.isViewing(other, destination: .worktree, conversationID: other, board: board))
        #expect(!MacCompletionNotifications.isViewing(session.id, destination: .home, conversationID: other, board: board))
        #expect(!MacCompletionNotifications.isViewing(session.id, destination: .worktree, conversationID: other, board: nil))
        #expect(MacCompletionNotifications.isViewing(other, destination: .conversations, conversationID: other, board: board))
        let center = ModelCompletionNotificationCenter()
        let task = ModelTaskSnapshot(id: UUID(), kind: .userQuestion(branchID: UUID(), responseIndex: 0),
            originPage: .conversation, conversationID: session.id, phase: .completed, funStatusText: nil, funLoadingStatusText: nil)
        for destination: MacDestination in [.worktree, .home] {
            MacCompletionNotifications.postQuestion(task, to: center, isViewing: {
                MacCompletionNotifications.isViewing($0, destination: destination, conversationID: other, board: board)
            }, isAppActive: true, conversation: nil) { _, _ in }
            #expect(center.notifications.count == (destination == .worktree ? 0 : 1))
        }
    }

    @Test func notificationAndExpandedCardDropsPlaceUndoablePersistentCopies() throws {
        for expanded in [false, true] {
            let board = WorktreeBoard()
            let center = ModelCompletionNotificationCenter()
            let concept = definition()
            center.postInsightDefinition(concept, conversationID: UUID(), postsSystemNotification: false)
            let notification = try #require(center.notifications.first)
            #expect(notification.insight == concept)
            var drop = WorktreeInsightDrop(concept: concept, notificationID: notification.id)
            if expanded {
                center.open(id: notification.id)
                drop = WorktreeInsightDrop(concept: concept, presentationID: try #require(center.presentedInsight).id)
            }
            let decoded = try #require(WorktreeInsightDrop.decode(drop.payload))
            #expect(board.items.isEmpty) // Starting or cancelling a drag does not place it.
            #expect(expanded ? center.presentedInsight != nil : !center.notifications.isEmpty)
            let point = CGPoint(x: -130, y: 240)
            board.placeInsight(decoded, at: point, center: center)
            #expect(board.items.count == 1)
            #expect(board.items.first?.insight == concept)
            #expect(board.items.first?.origin == point)
            #expect(center.notifications.isEmpty)
            #expect(center.presentedInsight == nil)
            let restored = WorktreeBoard(document: board.document(createdAt: Date()))
            #expect(restored.items.first?.insight == concept)
            #expect(restored.items.first?.origin == point)
            board.undo()
            #expect(board.items.isEmpty)
            board.redo()
            #expect(board.items.first?.insight == concept)
        }
        #expect(WorktreeInsightDrop.decode("ordinary text") == nil)
        #expect(WorktreeInsightDrop.decode("angrove-insight:invalid") == nil)
    }

    @Test func olderDragDoesNotDismissANewerExpandedCard() throws {
        let center = ModelCompletionNotificationCenter()
        center.presentInsight(definition(), conversationID: nil)
        let drop = WorktreeInsightDrop(concept: definition(), presentationID: try #require(center.presentedInsight).id)
        center.presentInsight(definition(), conversationID: nil)
        let latest = center.presentedInsight?.id
        WorktreeBoard().placeInsight(drop, at: .zero, center: center)
        #expect(center.presentedInsight?.id == latest)
    }

    @Test func headingCommandMakesExactlyOneArrivalRipple() async throws {
        let board = WorktreeBoard()
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        #expect(board.openCommand(freeOrigin: CGPoint(x: 100, y: 200)))
        board.commandText = "/heading A single ripple"
        board.commandFieldSize = CGSize(width: 250, height: 28)
        let before = board.ripples.count
        board.submitCommand(runtime: runtime)
        try await Task.sleep(for: .milliseconds(50))
        #expect(board.items.first?.isHeading == true)
        #expect(board.ripples.count == before + 1)
        #expect(!board.isCommandOpen)
    }

    @Test func insightDragSurfacesRenderOnTheBoardInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let board = WorktreeBoard()
            let center = ModelCompletionNotificationCenter()
            center.postInsightDefinition(definition(), conversationID: nil, postsSystemNotification: false)
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let host = NSHostingView(rootView: BoardsDragFixture(board: board, runtime: runtime)
                .environment(\.modelCompletionNotifications, center).environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            for expanded in [false, true] {
                if expanded { center.open(id: try #require(center.notifications.first).id) }
                try await Task.sleep(for: .milliseconds(650))
                host.layoutSubtreeIfNeeded()
                #expect(window.attachedSheet == nil)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-boards-drag-\(scheme == .light ? "light" : "dark")-\(expanded ? "card" : "pill").png"))
            }
        }
    }

    private func definition() -> ConceptDefinition {
        ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
            meaning: "Practical wisdom that guides sound judgment.", example: "")
    }
}

private struct BoardsDragFixture: View {
    let board: WorktreeBoard
    let runtime: MacApplicationRuntime
    @State private var popup = ModelTasksPopupState()

    var body: some View {
        MacWorktreeView(board: board, queuePopup: popup, runtime: runtime)
            .overlayPreferenceValue(MacGlobalModelControlsKey.self) { published in
                MacGlobalModelControlsDock(published: published, modelTasks: runtime.modelTasks, queuePopup: popup)
            }
    }
}
