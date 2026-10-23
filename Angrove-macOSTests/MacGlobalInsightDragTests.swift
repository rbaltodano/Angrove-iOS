import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacGlobalInsightDragTests {
    @Test func springNavigationWaitsHalfASecondAndOpensOnce() async throws {
        let hover = MacInsightSpringLoad()
        var count = 0
        hover.enter { count += 1 }
        try await Task.sleep(for: .milliseconds(250))
        #expect(count == 0)
        hover.enter { count += 100 }
        try await Task.sleep(for: .milliseconds(350))
        #expect(count == 1)
        try await Task.sleep(for: .milliseconds(150))
        #expect(count == 1)
        hover.cancel()
    }

    @Test func leavingOrDroppingCancelsSpringNavigationAndReentryRestartsIt() async throws {
        let hover = MacInsightSpringLoad()
        var count = 0
        hover.enter { count += 1 }
        try await Task.sleep(for: .milliseconds(250))
        hover.cancel()
        try await Task.sleep(for: .milliseconds(350))
        #expect(count == 0)
        #expect(!hover.isTargeted)
        hover.enter { count += 1 }
        for _ in 0..<20 {
            if count == 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(count == 1)
        hover.cancel()
    }

    @Test func payloadKeepsInsightAndCardIdentityWithoutOfferingEncodedTextToEditors() async throws {
        let concept = definition()
        let drop = WorktreeInsightDrop(concept: concept, presentationID: UUID())
        let provider = drop.itemProvider
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.angroveInsight.identifier))
        #expect(!provider.canLoadObject(ofClass: NSString.self))
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.angroveInsight.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        let decoded = try JSONDecoder().decode(WorktreeInsightDrop.self, from: #require(data))
        #expect(decoded.concept == concept)
        #expect(decoded.presentationID == drop.presentationID)
    }

    @Test func quoteAttachesToDestinationOnlyWithoutSendingOrChangingTheSource() throws {
        let source = MacConversationState()
        let destination = MacConversationState()
        source.savesConversation = false
        destination.savesConversation = false
        source.configure(preview: true)
        destination.configure(preview: true)
        let concept = definition()
        source.selectedDefinition = concept
        let center = ModelCompletionNotificationCenter()
        center.presentInsight(concept, conversationID: source.id)
        let drop = WorktreeInsightDrop(concept: concept, presentationID: try #require(center.presentedInsight).id)
        destination.attachQuote(drop.concept)
        drop.complete(in: center)
        #expect(source.quote == nil)
        #expect(source.selectedDefinition == concept)
        #expect(destination.quote == concept)
        #expect(destination.activeBranch?.branchContextConcept == concept)
        #expect(destination.transcript.isEmpty)
        #expect(center.presentedInsight == nil)
    }

    @Test func conversationDefinitionMovesIntoPersistentDockAndRendersAcrossPageChanges() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let session = MacConversationState()
            session.savesConversation = false
            session.configure(preview: true)
            session.selectedDefinition = definition()
            let center = ModelCompletionNotificationCenter()
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let host = NSHostingView(rootView: MacWorkspaceControlSlot(session: session, tree: MacTreeControls(),
                runtime: runtime, isCanvasMode: false, isVisible: true, hasQuestion: false, treeCard: nil,
                onOpenTree: {}, onCloseTree: {}, onSend: {}, onClearDraft: {})
                .environment(\.modelCompletionNotifications, center))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            try await Task.sleep(for: .milliseconds(250))
            #expect(center.presentedInsight?.concept == definition())
            #expect(session.selectedDefinition == nil)
            // Replace the entire page, keeping only the workspace's notification center.
            let next = NSHostingView(rootView: MacGlobalModelControlsDock(published: nil,
                modelTasks: runtime.modelTasks, queuePopup: ModelTasksPopupState())
                .environment(\.modelCompletionNotifications, center).environment(\.colorScheme, scheme))
            window.contentView = next
            try await Task.sleep(for: .milliseconds(400))
            next.layoutSubtreeIfNeeded()
            #expect(center.presentedInsight?.conversationID == session.id)
            let bitmap = try #require(next.bitmapImageRepForCachingDisplay(in: next.bounds))
            next.cacheDisplay(in: next.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-global-insight-\(scheme == .light ? "light" : "dark").png"))
            window.contentView = nil
            window.close()
        }
    }

    private func definition() -> ConceptDefinition {
        ConceptDefinition(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                          meaning: "Practical wisdom that guides sound judgment.", example: "")
    }
}
