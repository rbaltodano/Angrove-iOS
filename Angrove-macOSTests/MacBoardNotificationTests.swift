import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
@Suite(.serialized)
struct MacBoardNotificationTests {
    @Test func completionWaitsForClickAndKeepsItsBoardAndSourceWindow() throws {
        let (board, session) = fixture()
        let center = ModelCompletionNotificationCenter()
        let concept = definition()
        let probe = BoardNotificationProbe()
        let token = NotificationCenter.default.addObserver(forName: .macOpenBoardDefinition, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let request = note.object as? WorktreeDefinitionRequest, request.boardID == board.documentID {
                    probe.request = request
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        board.postDefinition(concept, from: session, to: center)
        #expect(session.selectedDefinition == nil)
        #expect(board.dockedDefinition == nil)
        let notification = try #require(center.notifications.first)
        #expect(notification.kind == .insightDefinition)
        center.open(id: notification.id)
        let request = try #require(probe.request)
        #expect(request.boardID == board.documentID)
        #expect(request.sessionID == session.id)
        #expect(board.presentDefinition(request))
        #expect(board.dockedDefinition?.session === session)
        #expect(board.dockedDefinition?.concept == concept)
        #expect(session.transcript.isEmpty)
        #expect(!session.savesConversation)
        #expect(board.items.count == 1)
        session.selectedDefinition = nil
        let previousID = board.dockedDefinition?.id
        #expect(board.presentDefinition(request))
        #expect(board.dockedDefinition?.id != previousID)
    }

    @Test func dismissedCompletionDoesNotOpenAndRemovedWindowsAreNotRestored() throws {
        let (board, session) = fixture()
        let center = ModelCompletionNotificationCenter()
        board.postDefinition(definition(), from: session, to: center)
        center.dismiss(id: try #require(center.notifications.first).id)
        #expect(session.selectedDefinition == nil)
        #expect(board.dockedDefinition == nil)
        let request = WorktreeDefinitionRequest(boardID: board.documentID, sessionID: session.id, concept: definition())
        board.items = []
        #expect(!board.presentDefinition(request))
        #expect(board.items.isEmpty)
        #expect(board.dockedDefinition == nil)
    }

    @Test func boardDockRendersFullToolsLabelAndDockedDefinition() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let (board, session) = fixture()
            let popup = ModelTasksPopupState()
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            #expect(board.presentDefinition(WorktreeDefinitionRequest(boardID: board.documentID,
                sessionID: session.id, concept: definition())))
            let center = ModelCompletionNotificationCenter()
            center.post(title: "Another Insight", kind: .insightDefinition, postsSystemNotification: false) {}
            let host = NSHostingView(rootView: BoardDockFixture(board: board, runtime: runtime, popup: popup)
                .environment(\.modelCompletionNotifications, center).environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(600))
            host.layoutSubtreeIfNeeded()
            #expect(window.attachedSheet == nil)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-board-notification-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private func definition() -> ConceptDefinition {
        ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                          meaning: "Practical wisdom that guides sound judgment.", example: "")
    }
    private func fixture() -> (WorktreeBoard, MacConversationState) {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var item = WorktreeBoard.Item(origin: CGPoint(x: -180, y: -120))
        item.session = session
        board.items = [item]
        return (board, session)
    }
}

@MainActor private final class BoardNotificationProbe { var request: WorktreeDefinitionRequest? }

private struct BoardDockFixture: View {
    let board: WorktreeBoard
    let runtime: MacApplicationRuntime
    let popup: ModelTasksPopupState
    var body: some View {
        MacWorktreeView(board: board, queuePopup: popup, runtime: runtime)
            .overlayPreferenceValue(MacGlobalModelControlsKey.self) { published in
                MacGlobalModelControlsDock(published: published, modelTasks: runtime.modelTasks, queuePopup: popup)
            }
    }
}
