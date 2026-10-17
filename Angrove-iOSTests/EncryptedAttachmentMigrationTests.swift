import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Encrypted attachment migration", .serialized)
@MainActor struct EncryptedAttachmentMigrationTests {
    private struct Interrupted: Error {}

    @Test("Local saves hold references, deduplicate originals and do not rewrite blobs on small edits")
    func compactLocalSaves() throws {
        try fixture { f in
            let bytes = Data(repeating: 0x65, count: 1_048_576)
            let first = UploadedFile(name: "Photo", imageData: bytes, rotationDegrees: -3)
            let second = UploadedFile(name: "Another copy", imageData: bytes, rotationDegrees: 2)
            var snapshot = snapshot([first, second])
            try f.conversations.save(snapshot)
            let source = f.conversationRoot.appending(path: "conversations-v1.json")
            let plain = try EncryptedPersonalFile.read(source)
            #expect(plain.count < 4096)
            #expect(!String(decoding: plain, as: UTF8.self).contains("imageData"))
            let blobs = try f.blobs(f.conversations.attachmentStore)
            #expect(blobs.count == 1)
            let blob = try #require(blobs.first)
            let originalCiphertext = try Data(contentsOf: blob)
            #expect(LocalDataCipher.isEncrypted(originalCiphertext))
            #expect(originalCiphertext != bytes)
            for index in 0..<12 {
                snapshot.conversations[0].title = "Edit \(index)"
                try f.conversations.save(snapshot)
            }
            #expect(try Data(contentsOf: blob) == originalCiphertext)
            let loaded = try #require(f.conversations.load())
            #expect(files(loaded).map(\.id) == [first.id, second.id])
            #expect(files(loaded).map(\.name) == [first.name, second.name])
            #expect(files(loaded).map(\.imageData) == [bytes, bytes])
            #expect(files(loaded).map(\.rotationDegrees) == [-3, 2])
        }
    }

    @Test("Exports are portable inline JSON and importing writes a fresh store's own blobs")
    func portableRoundTrip() throws {
        try fixture { f in
            let upload = UploadedFile(name: "Original", imageData: Data("exact original bytes".utf8), rotationDegrees: 4)
            try f.conversations.save(snapshot([upload]))
            let exported = try f.conversations.exportData()
            #expect(String(decoding: exported, as: UTF8.self).contains("imageData"))
            #expect(!String(decoding: exported, as: UTF8.self).contains("\"attachment\""))
            let portable = try InquirySnapshotFileStore.decodeImport(exported)
            #expect(files(portable).first?.imageData == upload.imageData)
            let destination = InquirySnapshotFileStore(rootDirectory: f.root.appending(path: "Fresh/ConversationStore"), defaults: f.defaults)
            try destination.importData(exported)
            #expect(files(try #require(destination.load())).first?.imageData == upload.imageData)
            #expect(try f.blobs(destination.attachmentStore).count == 1)
            let localJSON = try EncryptedPersonalFile.read(f.conversationRoot.appending(path: "conversations-v1.json"))
            #expect(throws: InquiryPersistenceError.self) { try InquirySnapshotFileStore.decodeImport(localJSON) }
        }
    }

    @Test("Interruption before parent commit preserves exact original; retry is idempotent")
    func interruptedMigration() throws {
        try fixture { f in
            let source = f.conversationRoot.appending(path: "conversations-v1.json")
            let upload = UploadedFile(name: "Old photo", imageData: Data(repeating: 42, count: 4096), rotationDegrees: 1)
            let legacy = try JSONEncoder().encode(snapshot([upload]))
            try EncryptedPersonalFile.write(legacy, to: source)
            let originalCiphertext = try Data(contentsOf: source)
            #expect(throws: Interrupted.self) {
                try AttachmentMigration.migrateFile(source, store: f.conversations.attachmentStore) { throw Interrupted() }
            }
            #expect(try Data(contentsOf: source) == originalCiphertext)
            let recovery = f.conversationRoot.appending(path: "AttachmentMigrationOriginals/conversations-v1.json")
            #expect(try Data(contentsOf: recovery) == originalCiphertext)
            try AttachmentMigration.migrateFile(source, store: f.conversations.attachmentStore)
            #expect(files(try #require(f.conversations.load())).first?.imageData == upload.imageData)
            let migratedCiphertext = try Data(contentsOf: source)
            try AttachmentMigration.migrateFile(source, store: f.conversations.attachmentStore)
            #expect(try Data(contentsOf: source) == migratedCiphertext)
            #expect(try f.blobs(f.conversations.attachmentStore).count == 1)
            #expect(try EncryptedPersonalFile.read(recovery) == legacy)
        }
    }

    @Test("A failed image write leaves the legacy parent intact for a later retry")
    func failedBlobWrite() throws {
        try fixture { f in
            let source = f.conversationRoot.appending(path: "conversations-v1.json")
            let legacy = try JSONEncoder().encode(snapshot([UploadedFile(name: "Keep", imageData: Data([8, 1]), rotationDegrees: 0)]))
            try EncryptedPersonalFile.write(legacy, to: source)
            let original = try Data(contentsOf: source)
            let unavailable = EncryptedAttachmentStore(directory: f.conversations.attachmentStore.directory,
                cipher: LocalDataCipher { _ in throw LocalDataEncryptionError.keychain(errSecInteractionNotAllowed) })
            #expect(throws: (any Error).self) { try AttachmentMigration.migrateFile(source, store: unavailable) }
            #expect(try Data(contentsOf: source) == original)
            try AttachmentMigration.migrateFile(source, store: f.conversations.attachmentStore)
            #expect(files(try #require(f.conversations.load())).first?.imageData == Data([8, 1]))
        }
    }

    @Test("Repeated schema validation does not decrypt unchanged images again")
    func validationReusesVerifiedBlob() throws {
        try fixture { f in
            let calls = KeyCalls()
            let key = SymmetricKey(size: .bits256)
            let store = EncryptedAttachmentStore(directory: f.root.appending(path: "Counted/Attachments"),
                cipher: LocalDataCipher { _ in calls.record(); return key })
            let value = [UploadedFile(name: "Photo", imageData: Data(repeating: 3, count: 4096), rotationDegrees: 0)]
            let encoded = try store.encoder().encode(value)
            let before = calls.count
            for _ in 0..<20 { try store.validate([UploadedFile].self, json: encoded) }
            #expect(calls.count == before)
            let reopened = EncryptedAttachmentStore(directory: store.directory, cipher: LocalDataCipher { _ in key })
            #expect(try reopened.decoder().decode([UploadedFile].self, from: encoded).first?.imageData == value.first?.imageData)
        }
    }

    @Test("Startup migrates live snapshots, backups and Boards, preserving unknown schema fields")
    func startupMigration() throws {
        try fixture { f in
            let upload = UploadedFile(name: "Shared", imageData: Data([1, 2, 3, 4]), rotationDegrees: 0)
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot([upload]))) as? [String: Any])
            object["futureField"] = ["preserve": "yes"]
            let old = try JSONSerialization.data(withJSONObject: object)
            let backup = f.conversationRoot.appending(path: "Backups/conversations-legacy.json")
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EncryptedPersonalFile.write(old, to: backup)
            try EncryptedPersonalFile.write(old, to: f.conversationRoot.appending(path: "conversations-v1.json"))
            let boardRoot = f.root.appending(path: "Worktree")
            try FileManager.default.createDirectory(at: boardRoot, withIntermediateDirectories: true)
            let board = boardRoot.appending(path: "boards.json")
            try EncryptedPersonalFile.write(JSONEncoder().encode([upload]), to: board)
            try PersonalDataProtection.prepare(preferences: f.preferences, rootDirectory: f.root, migrateWidget: {})
            let migrated = try #require(JSONSerialization.jsonObject(with: EncryptedPersonalFile.read(backup)) as? [String: Any])
            #expect((migrated["futureField"] as? [String: String])?["preserve"] == "yes")
            #expect(!String(decoding: try EncryptedPersonalFile.read(backup), as: UTF8.self).contains("imageData"))
            #expect(try f.conversations.attachmentStore.decoder().decode(InquiryPersistenceSnapshot.self,
                from: EncryptedPersonalFile.read(backup)).conversations[0].id == snapshotID(old))
            let loadedBoard = try EncryptedAttachmentStore.scoped(to: boardRoot).decoder().decode([UploadedFile].self, from: EncryptedPersonalFile.read(board))
            #expect(loadedBoard.first?.imageData == upload.imageData)
        }
    }

    @Test("Legacy file-backed preferences preserve an encrypted original before removing their key")
    func legacyBoardPreference() throws {
        try fixture { f in
            let key = "angrove.worktrees.v1"
            let file = UploadedFile(name: "Legacy", imageData: Data([3, 2, 1]), rotationDegrees: 0)
            let legacy = try JSONEncoder().encode([file])
            try f.preferences.write(legacy, key: key)
            let store = InsightTreeLocalStateFileStore(rootDirectory: f.root.appending(path: "Worktree"), defaults: f.defaults)
            let restored = try #require(store.load([UploadedFile].self, key: key))
            #expect(restored.first?.imageData == file.imageData)
            #expect(f.defaults.object(forKey: key) == nil)
            let original = store.rootDirectory.appending(path: "AttachmentMigrationOriginals").appending(path: store.url(for: key).lastPathComponent)
            #expect(try EncryptedPersonalFile.read(original) == legacy)
            #expect(try store.attachmentStore.decoder().decode([UploadedFile].self,
                from: EncryptedPersonalFile.read(store.url(for: key))).first?.imageData == file.imageData)
        }
    }

    @Test("Topics migrate their preference value and preserve an encrypted recovery original")
    func topicPreferences() throws {
        try fixture { f in
            let key = "aquinas.study-topics.v1"
            let file = UploadedFile(name: "Topic photo", imageData: Data(repeating: 7, count: 512), rotationDegrees: -1)
            let topic = StudyTopic(title: "Virtue", description: "Practice", files: [file])
            let legacy = try JSONEncoder().encode([topic])
            try f.preferences.write(legacy, key: key)
            try PersonalDataProtection.prepare(preferences: f.preferences, rootDirectory: f.root, migrateWidget: {})
            let stored = try #require(try f.preferences.read(key) as? Data)
            #expect(!String(decoding: stored, as: UTF8.self).contains("imageData"))
            let loaded = try f.preferences.decoder(for: key).decode([StudyTopic].self, from: stored)
            #expect(loaded.first?.files.first?.imageData == file.imageData)
            #expect(loaded.first?.createdAt == topic.createdAt)
            let original = f.root.appending(path: "StudyTopics/AttachmentMigrationOriginals/study-topics-v1.json")
            #expect(try EncryptedPersonalFile.read(original) == legacy)
            try f.preferences.writeEncoded(loaded, key: key)
            #expect(try f.blobs(try #require(f.preferences.attachmentStore)).count == 1)
            try f.preferences.writeEncoded([String: String](), key: "aquinas.glossed-terms.v1")
            #expect(try f.blobs(try #require(f.preferences.attachmentStore)).count == 1)
        }
    }

    @Test("Missing, altered, swapped and wrong-key blobs fail explicitly without replacing parents")
    func integrityFailures() throws {
        try fixture { f in
            let store = f.conversations.attachmentStore
            let first = AttachmentPayload(Data([3, 4, 5]))
            let second = AttachmentPayload(Data([6, 7, 8]))
            let ref = try store.put(first), other = try store.put(second)
            let source = try store.url(for: ref), otherURL = try store.url(for: other)
            let original = try Data(contentsOf: source)
            let wrongKey = SymmetricKey(size: .bits256)
            let wrong = EncryptedAttachmentStore(directory: store.directory, cipher: LocalDataCipher { _ in wrongKey })
            #expect(throws: (any Error).self) { try wrong.read(ref) }
            #expect(throws: AttachmentStorageError.self) {
                try store.read(AttachmentReference(version: 1, sha256: ref.sha256, byteCount: 4))
            }
            try Data(contentsOf: otherURL).write(to: source, options: .atomic)
            #expect(throws: (any Error).self) { try store.read(ref) }
            #expect(throws: (any Error).self) { try store.put(first) }
            try original.write(to: source, options: .atomic)
            try FileManager.default.removeItem(at: source)
            #expect(throws: AttachmentStorageError.self) { try store.read(ref) }
            #expect(throws: AttachmentStorageError.self) {
                try store.url(for: AttachmentReference(version: 1, sha256: "../../escape", byteCount: 1))
            }
            #expect(throws: AttachmentStorageError.self) {
                try store.url(for: AttachmentReference(version: 9, sha256: ref.sha256, byteCount: 3))
            }
        }
    }

    @Test("A missing referenced image blocks storage without replacing the saved conversation")
    func missingReferenceBlocksOverwrite() throws {
        try fixture { f in
            try f.conversations.save(snapshot([UploadedFile(name: "Keep", imageData: Data([2, 4, 6]), rotationDegrees: 0)]))
            let source = f.conversationRoot.appending(path: "conversations-v1.json")
            let original = try Data(contentsOf: source)
            let blob = try #require(f.blobs(f.conversations.attachmentStore).first)
            try FileManager.default.removeItem(at: blob)
            #expect(f.conversations.load() == nil)
            #expect(PersonalDataProtection.isBlocked)
            #expect(throws: (any Error).self) { try f.conversations.save(snapshot([])) }
            #expect(try Data(contentsOf: source) == original)
        }
    }

    @Test("Backup-only references survive cleanup; unused blobs do not cross owner boundaries")
    func backupOwnershipAndCleanup() throws {
        try fixture { f in
            let upload = UploadedFile(name: "Keep in backup", imageData: Data([9, 8, 7]), rotationDegrees: 0)
            try f.conversations.save(snapshot([upload]))
            let store = f.conversations.attachmentStore
            let blob = try #require(f.blobs(store).first)
            let boardStore = EncryptedAttachmentStore.scoped(to: f.root.appending(path: "Worktree"))
            let boardRef = try boardStore.put(AttachmentPayload(try #require(upload.imageData)))
            try f.conversations.save(snapshot([]))
            #expect(FileManager.default.fileExists(atPath: blob.path))
            let backupRoot = f.conversationRoot.appending(path: "Backups")
            let backup = try #require(try AttachmentJSON.jsonFiles(in: backupRoot).first)
            #expect(files(try store.decoder().decode(InquiryPersistenceSnapshot.self, from: EncryptedPersonalFile.read(backup))).first?.imageData == upload.imageData)
            try FileManager.default.removeItem(at: backupRoot)
            store.prune(ownerDirectory: f.conversationRoot)
            #expect(!FileManager.default.fileExists(atPath: blob.path))
            #expect(try boardStore.read(boardRef).data == upload.imageData)
        }
    }

    @Test("An unreadable reference inventory cancels cleanup rather than deleting an image")
    func unreadableInventoryKeepsBlobs() throws {
        try fixture { f in
            let store = f.conversations.attachmentStore
            let ref = try store.put(AttachmentPayload(Data([1, 0, 1])))
            try Data([0xff, 0xfe]).write(to: f.conversationRoot.appending(path: "unreadable.json"))
            store.prune(ownerDirectory: f.conversationRoot)
            #expect(FileManager.default.fileExists(atPath: try store.url(for: ref).path))
        }
    }

    @Test("Unknown future reference versions cancel cleanup even in unknown schema fields")
    func futureInventoryKeepsBlobs() throws {
        try fixture { f in
            let store = f.conversations.attachmentStore
            let reference = try store.put(AttachmentPayload(Data([9, 0, 9])))
            let future: [String: Any] = ["futureField": ["attachment": ["version": 2, "sha256": reference.sha256, "byteCount": 3]]]
            try EncryptedPersonalFile.write(JSONSerialization.data(withJSONObject: future), to: f.conversationRoot.appending(path: "future.json"))
            store.prune(ownerDirectory: f.conversationRoot)
            #expect(FileManager.default.fileExists(atPath: try store.url(for: reference).path))
            #expect(!PersonalDataProtection.isBlocked)
        }
    }

    @Test("Deleting conversations erases their attachments without deleting Topic files")
    func deletionOwnership() throws {
        try fixture { f in
            let data = Data([5, 5])
            try f.conversations.save(snapshot([UploadedFile(name: "Photo", imageData: data, rotationDegrees: 0)]))
            let topics = try #require(f.preferences.attachmentStore)
            let topicRef = try topics.put(AttachmentPayload(data))
            try f.conversations.deleteAllConversations()
            #expect(try f.blobs(f.conversations.attachmentStore).isEmpty)
            #expect(try topics.read(topicRef).data == data)
        }
    }

    #if os(macOS)
    @Test("Real Board photos and trash use the same reference codec")
    func boardPersistence() throws {
        try fixture { f in
            let file = UploadedFile(name: "Board photo", imageData: Data([6, 5, 4]), rotationDegrees: 2)
            var branch = ChatBranch(startingConcept: nil)
            branch.activeChatBlocks = [.user("Nested window photo", nil, [file])]
            let item = WorktreeStoredItem(id: UUID(), origin: .zero, text: "", isHeading: false, image: file, branches: [branch])
            let store = InsightTreeLocalStateFileStore(rootDirectory: f.root.appending(path: "Worktree"), defaults: f.defaults)
            let documents = [WorktreeDocument(items: [item], trash: [item])]
            try store.save(documents, key: "test-boards")
            let restored = try #require(store.load([WorktreeDocument].self, key: "test-boards"))
            #expect(restored.first?.items.first?.image?.imageData == file.imageData)
            #expect(restored.first?.trash?.first?.image?.imageData == file.imageData)
            #expect(restored.first?.items.first?.branches?.first?.activeChatBlocks == branch.activeChatBlocks)
            #expect(!String(decoding: try EncryptedPersonalFile.read(store.url(for: "test-boards")), as: UTF8.self).contains("imageData"))
        }
    }
    #endif

    private func snapshot(_ files: [UploadedFile]) -> InquiryPersistenceSnapshot {
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.user("Question", nil, files), .text("Answer")]
        return InquiryPersistenceSnapshot(conversations: [InquiryConversation(title: "Saved", branches: [branch])], activeConversationID: nil)
    }
    private func files(_ value: InquiryPersistenceSnapshot) -> [UploadedFile] {
        if case .user(_, _, let files) = value.conversations[0].branches[0].activeChatBlocks[0] { return files }
        return []
    }
    private func snapshotID(_ data: Data) throws -> UUID {
        try JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: data).conversations[0].id
    }
    private func fixture(_ body: (Fixture) throws -> Void) throws {
        let key = SymmetricKey(size: .bits256)
        let cipher = LocalDataCipher { _ in key }
        let f = try Fixture(cipher: cipher)
        let previouslyBlocked = PersonalDataProtection.isBlocked
        PersonalDataProtection.finishValidatedRecovery()
        defer {
            try? FileManager.default.removeItem(at: f.root)
            f.defaults.removePersistentDomain(forName: f.suite)
            if previouslyBlocked { PersonalDataProtection.block() } else { PersonalDataProtection.finishValidatedRecovery() }
        }
        try EncryptedPersonalFile.$scopedCipher.withValue(cipher) { try body(f) }
    }
    private nonisolated final class KeyCalls: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func record() { lock.withLock { value += 1 } }
    }
    private struct Fixture {
        let root: URL
        let defaults: UserDefaults
        let suite = "AttachmentFixtures.\(UUID())"
        let cipher: LocalDataCipher
        var conversationRoot: URL { root.appending(path: "ConversationStore") }
        var conversations: InquirySnapshotFileStore { InquirySnapshotFileStore(rootDirectory: conversationRoot, defaults: defaults) }
        var preferences: PrivatePreferences {
            PrivatePreferences(defaults: defaults, cipher: cipher,
                attachmentStore: .scoped(to: root.appending(path: "StudyTopics")))
        }
        init(cipher: LocalDataCipher) throws {
            self.cipher = cipher
            root = FileManager.default.temporaryDirectory.appending(path: "AttachmentFixture-\(UUID())")
            defaults = try #require(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: conversationRoot, withIntermediateDirectories: true)
        }
        func blobs(_ store: EncryptedAttachmentStore) throws -> [URL] {
            guard FileManager.default.fileExists(atPath: store.directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "attachment" }
        }
    }
}
