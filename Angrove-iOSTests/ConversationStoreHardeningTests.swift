import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Conversation store hardening", .serialized)
struct ConversationStoreHardeningTests {
    @Test("Saves after a long idle period create one backup, and same-second saves both persist")
    func idleSavesKeepBackupRotation() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let fixture = try StoreFixture(now: { clock.now })
        defer { fixture.cleanup() }

        try fixture.store.save(snapshot(titled: "A"))
        clock.now += 7 * 60 * 60
        try fixture.store.save(snapshot(titled: "B"))
        try fixture.store.save(snapshot(titled: "C"))
        try fixture.store.save(snapshot(titled: "D"))

        #expect(fixture.store.load()?.conversations.first?.title == "D")
        #expect(fixture.backupCount() == 1)
    }

    @Test("Import always backs up the conversations it replaces")
    func importBacksUpCurrentSnapshot() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let fixture = try StoreFixture(now: { clock.now })
        defer { fixture.cleanup() }

        try fixture.store.save(snapshot(titled: "A"))
        clock.now += 7 * 60 * 60
        try fixture.store.save(snapshot(titled: "B"))   // backs up A
        clock.now += 60
        try fixture.store.save(snapshot(titled: "Newest"))
        clock.now += 60
        let incoming = try JSONEncoder().encode(snapshot(titled: "Imported"))
        try fixture.store.importData(incoming)

        #expect(fixture.store.load()?.conversations.first?.title == "Imported")
        let backedUpTitles = try fixture.backupTitles()
        #expect(backedUpTitles.contains("Newest"))
    }

    @Test("Conversations saved before newer fields existed still decode")
    func legacyConversationDecodes() throws {
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.user("What is prudence?", nil, []), .text("Right reason in action.")]
        let conversation = InquiryConversation(title: "Prudence", isPinned: true, branches: [branch])
        var json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(conversation)) as? [String: Any]
        )
        json.removeValue(forKey: "createdAt")
        json.removeValue(forKey: "isPinned")
        json.removeValue(forKey: "isStudyTopic")
        json.removeValue(forKey: "promotedInsightIDs")
        var legacyBranch = try #require((json["branches"] as? [[String: Any]])?.first)
        for key in ["yOffset", "topQuestionUploads", "showBottomInput", "bottomQuestionText"] {
            legacyBranch.removeValue(forKey: key)
        }
        json["branches"] = [legacyBranch]

        let decoded = try JSONDecoder().decode(
            InquiryConversation.self, from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded.title == "Prudence")
        #expect(!decoded.isPinned)
        #expect(decoded.branches.first?.activeChatBlocks == branch.activeChatBlocks)
    }

    @Test("Every populated conversation field survives a save round trip")
    func populatedRoundTrip() throws {
        let concept = ConceptDefinition(word: "Virtue", partOfSpeech: "", pronunciation: "", meaning: "A settled habit", example: "")
        var branch = ChatBranch(
            startingConcept: concept, parentBranchID: UUID(), parentResponseIndex: 1,
            duplicatedResponse: "Copied", yOffset: 12, hiddenPromptContext: "Hidden"
        )
        branch.activeChatBlocks = [.user("Q", nil, []), .text("A")]
        branch.topQuestionText = "Top"
        branch.topQuestionUploads = [UploadedFile(name: "note.txt", imageData: nil, rotationDegrees: 2)]
        branch.topQuestionSubmitted = true
        branch.bottomQuestionText = "Bottom"
        branch.showBottomInput = true
        branch.attachedConcept = concept
        branch.branchContextConcept = concept
        branch.generatedBranchTitle = "Title"
        branch.compactedContext = "Summary"
        branch.compactedThroughBlockCount = 2
        branch.pinnedHeaderQuestion = "Pinned"
        branch.setResponsePresentation(ResponsePresentationMetadata(
            responseIndex: 1, showsThinking: true, thinkingSummary: ["Approach"], thinkingDurationSeconds: 3
        ))
        let conversation = InquiryConversation(
            title: "Virtue", isStudyTopic: true, studyTopicID: UUID(), isPinned: true,
            branches: [branch], promotedInsightIDs: [UUID()],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try JSONDecoder().decode(
            InquiryConversation.self, from: JSONEncoder().encode(conversation)
        )
        #expect(decoded == conversation)
    }

    private func snapshot(titled title: String) -> InquiryPersistenceSnapshot {
        let conversation = InquiryConversation(title: title)
        return InquiryPersistenceSnapshot(conversations: [conversation], activeConversationID: conversation.id)
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private struct StoreFixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: InquirySnapshotFileStore

    init(now: @escaping () -> Date) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "AngroveStoreHardening-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        suiteName = "AngroveStoreHardening.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        store = InquirySnapshotFileStore(rootDirectory: root, defaults: defaults, now: now)
    }

    var backups: [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root.appending(path: "Backups"), includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "json" } ?? []
    }

    func backupCount() -> Int { backups.count }

    func backupTitles() throws -> [String] {
        try backups.flatMap { url in
            let data = try EncryptedPersonalFile.read(url)
            return try JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: data).conversations.map(\.title)
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
