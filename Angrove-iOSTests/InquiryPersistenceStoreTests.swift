import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Inquiry persistence")
struct InquiryPersistenceStoreTests {
    @MainActor
    @Test("Three queued questions complete in their own conversations after navigation")
    func threeConversationsKeepTheirAnswers() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let serialized = SerializedInquiryStore(makeStore: { fixture.store })
        let queue = ModelTaskQueue()
        let conversations = (0..<3).map { index in
            var branch = ChatBranch(startingConcept: nil)
            branch.activeChatBlocks = [.user("Question \(index)", nil, []), .text("")]
            return InquiryConversation(branches: [branch])
        }
        // The user has already navigated to another empty composer when results arrive.
        let emptyConversation = InquiryConversation(branches: [ChatBranch(startingConcept: nil)])
        serialized.save(InquiryPersistenceSnapshot(
            conversations: conversations + [emptyConversation], activeConversationID: emptyConversation.id
        ))
        var completed: [Int] = []
        var cancellations = 0
        for (index, conversation) in conversations.enumerated() {
            let branch = try #require(conversation.branches.first)
            queue.enqueue(
                kind: .userQuestion(branchID: branch.id, responseIndex: 1),
                conversationID: conversation.id,
                onCancel: { cancellations += 1 }
            ) {
                let destination = ConversationResponseStatePolicy.completionDestination(
                    isCancelled: Task.isCancelled, isViewVisible: false,
                    originalBranchID: branch.id,
                    displayedBranchID: emptyConversation.branches[0].id,
                    responseIndex: 1, displayedBlockCount: 0
                )
                #expect(destination == .detached)
                if destination == .detached {
                    serialized.completeDetachedResponse(
                        branchID: branch.id, conversationID: conversation.id,
                        responseIndex: 1, annotatedText: "Answer \(index)",
                        presentation: ResponsePresentationMetadata(
                            responseIndex: 1, showsThinking: false, thinkingSummary: []
                        )
                    )
                }
                completed.append(index)
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while queue.isBusy, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!queue.isBusy)
        #expect(completed == [0, 1, 2])
        #expect(cancellations == 0)
        let restored = try #require(serialized.load())
        #expect(restored.activeConversationID == emptyConversation.id)
        #expect(restored.conversations.last == emptyConversation)
        for index in 0..<3 {
            #expect(restored.conversations[index].branches[0].activeChatBlocks == [
                .user("Question \(index)", nil, []), .text("Answer \(index)")
            ])
            #expect(restored.conversations[index].branches[0].showBottomInput)
        }
    }

    @Test("A stale page save keeps completed answers and the user's newer composer draft")
    func stalePageSaveDoesNotEraseDetachedAnswer() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let serialized = SerializedInquiryStore(makeStore: { fixture.store })
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.user("Question", nil, []), .text("")]
        let conversation = InquiryConversation(branches: [branch])
        var staleSnapshot = InquiryPersistenceSnapshot(
            conversations: [conversation], activeConversationID: conversation.id
        )
        serialized.save(staleSnapshot)
        serialized.completeDetachedResponse(
            branchID: branch.id, conversationID: conversation.id,
            responseIndex: 1, annotatedText: "Completed answer",
            presentation: ResponsePresentationMetadata(
                responseIndex: 1, showsThinking: false, thinkingSummary: []
            )
        )
        staleSnapshot.conversations[0].branches[0].bottomQuestionText = "My next question"
        serialized.save(staleSnapshot)
        let restored = try #require(serialized.load()?.conversations.first?.branches.first)
        #expect(restored.activeChatBlocks[1] == .text("Completed answer"))
        #expect(restored.bottomQuestionText == "My next question")
        #expect(restored.showBottomInput)

        // A different question at the same position must not inherit the previous answer.
        staleSnapshot.conversations[0].branches[0].activeChatBlocks[0] = .user("Different", nil, [])
        serialized.save(staleSnapshot)
        #expect(serialized.load()?.conversations[0].branches[0].activeChatBlocks[1] == .text(""))
    }

    @Test("A detached completion does not recreate a cleared response slot")
    func detachedCompletionDoesNotResurrectClearedQuestion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let branch = ChatBranch(startingConcept: nil)
        let conversation = InquiryConversation(branches: [branch])
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [conversation], activeConversationID: conversation.id
        )
        try fixture.store.save(snapshot)
        try fixture.store.completeDetachedResponse(
            branchID: branch.id, conversationID: conversation.id,
            responseIndex: 1, annotatedText: "Late answer",
            presentation: ResponsePresentationMetadata(
                responseIndex: 1, showsThinking: false, thinkingSummary: []
            )
        )
        #expect(fixture.store.load() == snapshot)
    }

    @Test("A file-backed snapshot round-trips with stable identifiers")
    func snapshotRoundTrip() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let conversation = InquiryConversation(title: "Grace and Nature")
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [conversation],
            activeConversationID: conversation.id
        )

        try fixture.store.save(snapshot)

        #expect(fixture.store.load() == snapshot)
    }

    @Test("Queued saves are visible to the next load, in order")
    func queuedSavesAreReadInOrder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let serialized = SerializedInquiryStore(makeStore: { fixture.store })
        let conversations = (0..<20).map { InquiryConversation(title: "Draft \($0)") }

        for conversation in conversations {
            serialized.save(
                InquiryPersistenceSnapshot(
                    conversations: [conversation],
                    activeConversationID: conversation.id
                )
            )
        }

        #expect(serialized.load()?.conversations.map(\.title) == ["Draft 19"])
    }

    @Test("A queued completed response lands after the snapshot queued before it")
    func queuedCompletedResponseFollowsSnapshot() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let serialized = SerializedInquiryStore(makeStore: { fixture.store })
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.user("What is prudence?", nil, []), .text("")]
        let conversation = InquiryConversation(branches: [branch])

        serialized.save(
            InquiryPersistenceSnapshot(
                conversations: [conversation],
                activeConversationID: conversation.id
            )
        )
        branch.activeChatBlocks[1] = .text("Prudence is practical wisdom.")
        serialized.saveCompletedBranch(branch, conversationID: conversation.id)
        serialized.flush()

        #expect(fixture.store.load()?.conversations.first?.branches.first == branch)
    }

    @Test("A completed response replaces its persisted placeholder by stable IDs")
    func completedResponseReplacesPlaceholder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [
            .user("What is prudence?", nil, []),
            .text("")
        ]
        let conversation = InquiryConversation(branches: [branch])
        try fixture.store.save(
            InquiryPersistenceSnapshot(
                conversations: [conversation],
                activeConversationID: conversation.id
            )
        )

        branch.activeChatBlocks[1] = .text("Prudence is practical wisdom.")
        branch.showBottomInput = true
        try fixture.store.saveCompletedBranch(
            branch,
            conversationID: conversation.id
        )

        let restoredBranch = fixture.store.load()?.conversations.first?.branches.first
        #expect(restoredBranch?.activeChatBlocks[1] == .text("Prudence is practical wisdom."))
        #expect(restoredBranch?.showBottomInput == true)
    }

    @Test("The current UserDefaults prototype migrates once to the file store")
    func legacyMigration() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let conversation = InquiryConversation(title: "Migrated Inquiry")
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [conversation],
            activeConversationID: conversation.id
        )
        fixture.defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: InquirySnapshotFileStore.currentLegacyKey
        )

        #expect(fixture.store.load() == snapshot)
        #expect(
            fixture.defaults.object(
                forKey: InquirySnapshotFileStore.currentLegacyKey
            ) == nil
        )
        #expect(fixture.store.load() == snapshot)
    }

    @Test("A corrupt live snapshot recovers from the newest valid backup")
    func backupRecovery() throws {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try Fixture(now: { clock })
        defer { fixture.cleanup() }
        let first = InquiryPersistenceSnapshot(
            conversations: [InquiryConversation(title: "Known Good")],
            activeConversationID: nil
        )
        let second = InquiryPersistenceSnapshot(
            conversations: [InquiryConversation(title: "Current")],
            activeConversationID: nil
        )

        try fixture.store.save(first)
        clock.addTimeInterval(7 * 60 * 60)
        try fixture.store.save(second)
        try Data("not json".utf8).write(
            to: fixture.root.appending(path: "conversations-v1.json"),
            options: .atomic
        )

        #expect(fixture.store.load() == first)
    }

    @Test("Imports are validated before replacing live conversations")
    func invalidImportIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = InquiryPersistenceSnapshot(
            conversations: [InquiryConversation(title: "Keep Me")],
            activeConversationID: nil
        )
        try fixture.store.save(original)

        #expect(throws: InquiryPersistenceError.self) {
            try fixture.store.importData(Data("invalid".utf8))
        }
        #expect(fixture.store.load() == original)
    }
}

@Suite("Local Insight Tree persistence")
struct LocalInsightTreePersistenceTests {
    @Test("Canvas state migrates from UserDefaults into protected files")
    func canvasStateMigration() throws {
        let fixture = try LocalTreeFixture()
        defer { fixture.cleanup() }
        let key = "canvas.\(UUID().uuidString)"
        let expected = ["node-a": StoredPoint(x: 42, y: -18)]
        fixture.defaults.set(try JSONEncoder().encode(expected), forKey: key)
        let store = InsightTreeLocalStateFileStore(
            rootDirectory: fixture.root.appending(path: "canvas"),
            defaults: fixture.defaults
        )

        #expect(store.load([String: StoredPoint].self, key: key) == expected)
        #expect(fixture.defaults.object(forKey: key) == nil)
        #expect(store.load([String: StoredPoint].self, key: key) == expected)
    }

    @Test("Local semantic seeds preserve embedding provenance")
    func seedRoundTrip() throws {
        let fixture = try LocalTreeFixture()
        defer { fixture.cleanup() }
        let seed = LocalInsightTreeSeed(
            id: UUID(),
            label: "Natural law",
            summary: "A principle grounded in human nature.",
            embedding: [0.1, 0.2, 0.3],
            embeddingVersion: "minilm.test.v1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = LocalInsightTreeSeedFileStore(
            fileURL: fixture.root.appending(path: "seeds.json"),
            defaults: fixture.defaults
        )

        try store.save(["conversation": [seed]])

        #expect(store.load() == ["conversation": [seed]])
    }
}

private struct StoredPoint: Codable, Equatable {
    let x: Double
    let y: Double
}

private struct LocalTreeFixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "AquinasLocalTreePersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        suiteName = "AquinasLocalTreePersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        self.defaults = defaults
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct Fixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: InquirySnapshotFileStore

    init(now: @escaping () -> Date = Date.init) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "AquinasInquiryPersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        suiteName = "AquinasInquiryPersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        self.defaults = defaults
        store = InquirySnapshotFileStore(
            rootDirectory: root,
            defaults: defaults,
            now: now
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
