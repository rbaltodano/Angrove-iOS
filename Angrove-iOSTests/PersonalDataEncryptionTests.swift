import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Personal data encryption", .serialized)
struct PersonalDataEncryptionTests {
    @Test("Rejects tampering, wrong keys, and swapped stores; uses fresh nonces")
    func authentication() throws {
        let key = SymmetricKey(size: .bits256)
        let cipher = LocalDataCipher { _ in key }
        let otherKey = SymmetricKey(size: .bits256)
        let wrong = LocalDataCipher { _ in otherKey }
        let plain = Data("Private question and attached photograph".utf8)
        let sealed = try cipher.seal(plain, context: "conversations")
        #expect(try cipher.open(sealed, context: "conversations") == plain)
        #expect(!String(decoding: sealed, as: UTF8.self).contains("Private question"))
        #expect(try cipher.seal(plain, context: "conversations") != sealed)
        #expect(throws: (any Error).self) { try cipher.open(sealed, context: "insights") }
        #expect(throws: (any Error).self) { try wrong.open(sealed, context: "conversations") }
        var unknownVersion = sealed
        unknownVersion[LocalDataCipher.family.count] = 0x32
        #expect(LocalDataCipher.isEncrypted(unknownVersion))
        #expect(throws: LocalDataEncryptionError.self) { try cipher.open(unknownVersion, context: "conversations") }
        var tampered = sealed
        tampered[tampered.count - 1] ^= 1
        #expect(throws: (any Error).self) { try cipher.open(tampered, context: "conversations") }
    }

    @Test("Migrates legacy property-list types without exposing content on disk")
    func preferencesMigration() throws {
        let suite = "AngroveEncryptionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)
        let store = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in key })
        let values: [String: Any] = [
            "aquinas.saved.insights.v1": Data("\"personal insight\"".utf8),
            "aquinas.settings.userName": "Ryan",
            "aquinas.settings.customInstructions": "My personal context",
            "AquinasSeenInsightIDs": ["one", "two"],
            "aquinas.home.monthly-usage.counts.v1": ["2026-10-05": 5],
            "aquinas.home.monthly-usage.last-recorded-at.v1": Date(timeIntervalSince1970: 100),
        ]
        for (key, value) in values { defaults.set(value, forKey: key) }
        for key in values.keys {
            let restored = try #require(try store.read(key))
            #expect(NSDictionary(dictionary: ["value": restored]).isEqual(to: ["value": values[key]!]))
            #expect(LocalDataCipher.isEncrypted(try #require(defaults.data(forKey: key))))
        }
        try store.write("Updated", key: "aquinas.settings.userName")
        #expect(try store.read("aquinas.settings.userName") as? String == "Updated")
        try store.write("Dark", key: "aquinas.settings.appearance")
        #expect(defaults.string(forKey: "aquinas.settings.appearance") == "Dark")
    }

    @Test("A missing key cannot replace or erase encrypted preferences")
    func missingKeyPreservesData() throws {
        let suite = "AngroveMissingKeyTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)
        let good = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in key })
        try good.write("Keep this", key: "aquinas.settings.userName")
        let original = defaults.data(forKey: "aquinas.settings.userName")
        let missing = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in throw LocalDataEncryptionError.missingKey })
        #expect(throws: LocalDataEncryptionError.self) { try missing.read("aquinas.settings.userName") }
        #expect(throws: LocalDataEncryptionError.self) { try missing.write("Erase this", key: "aquinas.settings.userName") }
        #expect(defaults.data(forKey: "aquinas.settings.userName") == original)
        let malformed = Data("ANGROVE-ENC\u{0}2\u{0}damaged".utf8)
        defaults.set(malformed, forKey: "aquinas.saved.insights.v1")
        #expect(throws: LocalDataEncryptionError.self) { try good.read("aquinas.saved.insights.v1") }
        #expect(defaults.data(forKey: "aquinas.saved.insights.v1") == malformed)
    }

    @Test("Conversation files and rotating backups are encrypted and round-trip")
    func conversationFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AngroveEncryption-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InquirySnapshotFileStore(rootDirectory: root)
        let snapshot = InquiryPersistenceSnapshot(conversations: [InquiryConversation(title: "Private thoughts")], activeConversationID: nil)
        try store.save(snapshot)
        try store.save(snapshot)
        #expect(LocalDataCipher.isEncrypted(try Data(contentsOf: root.appending(path: "conversations-v1.json"))))
        let backup = try #require(FileManager.default.contentsOfDirectory(at: root.appending(path: "Backups"), includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: backup)
        #expect(LocalDataCipher.isEncrypted(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Private thoughts"))
        #expect(store.load() == snapshot)
        #expect(try JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: store.exportData()) == snapshot)
    }

    @Test("The real widget App Group Keychain is accessible and separate from personal storage")
    func sharedKeychain() throws {
        let plain = Data("Keychain integration fixture".utf8)
        let encrypted = try LocalDataCipher.widget.seal(plain, context: "widget-test")
        #expect(try LocalDataCipher.widget.open(encrypted, context: "widget-test") == plain)
        #expect(throws: (any Error).self) {
            try LocalDataCipher.personal.open(encrypted, context: "widget-test")
        }
    }

    @Test("Startup validates existing ciphertext before migrating any legacy data")
    func migrationPreflight() throws {
        let suite = "AngrovePreflightTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)
        let good = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in key })
        try good.write("Keep this", key: "aquinas.settings.userName")
        defaults.set("Legacy instructions", forKey: "aquinas.settings.customInstructions")
        let original = defaults.data(forKey: "aquinas.settings.userName")
        let missing = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in throw LocalDataEncryptionError.missingKey })
        #expect(throws: LocalDataEncryptionError.self) {
            try PersonalDataProtection.prepare(preferences: missing, rootDirectory: URL(filePath: "/nonexistent-preflight-fixture"), migrateWidget: {})
        }
        #expect(defaults.data(forKey: "aquinas.settings.userName") == original)
        #expect(defaults.string(forKey: "aquinas.settings.customInstructions") == "Legacy instructions")
    }

    @Test("Legacy JSON migration preserves content and backup timestamps")
    func legacyFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AngroveLegacyEncryption-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "conversations-v1.json")
        let snapshot = InquiryPersistenceSnapshot(conversations: [InquiryConversation(title: "Legacy private thoughts")], activeConversationID: nil)
        let plain = try JSONEncoder().encode(snapshot)
        try plain.write(to: url)
        let date = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        #expect(try EncryptedPersonalFile.read(url) == plain)
        #expect(LocalDataCipher.isEncrypted(try Data(contentsOf: url)))
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == date)
    }

    @Test("A damaged conversation file is set aside so startup falls back to its newest backup")
    func damagedSnapshotFallsBackToBackup() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let store = InquirySnapshotFileStore(rootDirectory: fixture.conversations)
        let snapshot = InquiryPersistenceSnapshot(conversations: [InquiryConversation(title: "Kept in backup")], activeConversationID: nil)
        try store.save(snapshot)
        try store.save(snapshot)
        let live = fixture.conversations.appending(path: "conversations-v1.json")
        var damaged = try Data(contentsOf: live)
        damaged[damaged.count - 1] ^= 0xFF
        try damaged.write(to: live)

        try PersonalDataProtection.prepare(preferences: fixture.preferences, rootDirectory: fixture.root, migrateWidget: {})
        #expect(!FileManager.default.fileExists(atPath: live.path))
        let setAside = try FileManager.default.contentsOfDirectory(atPath: fixture.conversations.path)
            .filter { $0.hasPrefix("conversations-v1.json.damaged-") }
        #expect(setAside.count == 1)
        #expect(store.load() == snapshot)
    }

    @Test("When no stored ciphertext opens, nothing is moved and startup stops")
    func unverifiableKeyMovesNothing() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let store = InquirySnapshotFileStore(rootDirectory: fixture.conversations)
        try store.save(InquiryPersistenceSnapshot(conversations: [InquiryConversation(title: "Only copy")], activeConversationID: nil))
        let live = fixture.conversations.appending(path: "conversations-v1.json")
        var damaged = try Data(contentsOf: live)
        damaged[damaged.count - 1] ^= 0xFF
        try damaged.write(to: live)

        #expect(throws: (any Error).self) {
            try PersonalDataProtection.prepare(preferences: fixture.preferences, rootDirectory: fixture.root, migrateWidget: {})
        }
        #expect(try Data(contentsOf: live) == damaged)
        try PersonalDataProtection.prepare(preferences: fixture.preferences, rootDirectory: fixture.emptyRoot, migrateWidget: {})
    }

    @Test("An unreadable widget question is discarded instead of keeping the app closed")
    func widgetFailureDoesNotBlockStartup() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        var discarded = false
        try PersonalDataProtection.prepare(
            preferences: fixture.preferences, rootDirectory: fixture.emptyRoot,
            migrateWidget: { throw LocalDataEncryptionError.missingKey },
            discardWidget: { discarded = true })
        #expect(discarded)
        #expect(!PersonalDataProtection.isBlocked)
        discarded = false
        try PersonalDataProtection.prepare(
            preferences: fixture.preferences, rootDirectory: fixture.emptyRoot,
            migrateWidget: { throw LocalDataEncryptionError.keychain(errSecInteractionNotAllowed) },
            discardWidget: { discarded = true })
        #expect(!discarded)
    }

    @Test("Temporary save failures keep storage open; integrity failures close it")
    func writeFailureClassification() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        #expect(!PersonalDataProtection.isIntegrityFailure(LocalDataEncryptionError.keychain(errSecInteractionNotAllowed)))
        #expect(!PersonalDataProtection.isIntegrityFailure(CocoaError(.fileWriteNoPermission)))
        #expect(PersonalDataProtection.isIntegrityFailure(LocalDataEncryptionError.missingKey))
        #expect(PersonalDataProtection.isIntegrityFailure(CryptoKitError.authenticationFailure))
        #expect(PersonalDataProtection.offersFreshStart(LocalDataEncryptionError.missingKey))
        #expect(!PersonalDataProtection.offersFreshStart(LocalDataEncryptionError.keychain(errSecInteractionNotAllowed)))
    }

    @Test("Starting fresh sets unreadable data aside without deleting it")
    func startFreshPreservesData() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let store = InquirySnapshotFileStore(rootDirectory: fixture.conversations)
        try store.save(InquiryPersistenceSnapshot(conversations: [InquiryConversation(title: "Set aside")], activeConversationID: nil))
        let ciphertext = try fixture.goodPreferences().cipher.seal(Data("x".utf8), context: "preferences:aquinas.saved.insights.v1")
        fixture.defaults.set(ciphertext, forKey: "aquinas.saved.insights.v1")

        try PersonalDataProtection.startFresh(preferences: fixture.preferences, rootDirectory: fixture.root, removeUnusableKey: false)
        #expect(!FileManager.default.fileExists(atPath: fixture.conversations.path))
        #expect(fixture.defaults.object(forKey: "aquinas.saved.insights.v1") == nil)
        let archive = try #require(try FileManager.default.contentsOfDirectory(at: fixture.base, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("Angrove Unreadable Data") })
        #expect(FileManager.default.fileExists(atPath: archive.appending(path: "ConversationStore/conversations-v1.json").path))
        let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: archive.appending(path: "preferences.plist")), format: nil) as? [String: Data]
        #expect(saved?["aquinas.saved.insights.v1"] == ciphertext)
    }
}

/// Isolated Application Support-style tree and preferences for startup recovery tests.
private struct RecoveryFixture {
    let base: URL
    let root: URL
    let emptyRoot: URL
    let defaults: UserDefaults
    let suite: String
    let key = SymmetricKey(size: .bits256)
    var conversations: URL { root.appending(path: "ConversationStore") }
    var preferences: PrivatePreferences { PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { [key] _ in key }) }
    func goodPreferences() -> PrivatePreferences { preferences }

    init() throws {
        base = FileManager.default.temporaryDirectory.appending(path: "AngroveRecovery-\(UUID())")
        root = base.appending(path: "Aquinas")
        emptyRoot = base.appending(path: "Empty")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        suite = "AngroveRecoveryTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
        defaults.removePersistentDomain(forName: suite)
    }
}
