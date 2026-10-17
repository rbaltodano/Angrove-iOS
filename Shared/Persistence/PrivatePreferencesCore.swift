import CryptoKit
import Foundation

nonisolated struct PrivatePreferences {
    static let standard = PrivatePreferences(defaults: .standard, attachmentStore: .topics)
    let defaults: UserDefaults
    var cipher: LocalDataCipher = .personal
    var attachmentStore: EncryptedAttachmentStore? = nil

    func attachments(for key: String) -> EncryptedAttachmentStore? {
        key == "aquinas.study-topics.v1" ? attachmentStore : nil
    }

    func decoder(for key: String) -> JSONDecoder { attachments(for: key)?.decoder() ?? JSONDecoder() }

    func writeEncoded<Value: Encodable>(_ value: Value, key: String) throws {
        guard let store = attachments(for: key) else {
            try write(JSONEncoder().encode(value), key: key)
            return
        }
        try store.transaction {
            if let previous = try read(key) as? Data { try preserveAttachmentOriginal(previous, store: store) }
            let data = try store.encoder().encode(value)
            try write(data, key: key)
            guard try read(key) as? Data == data else { throw AttachmentStorageError.unavailable }
            store.prune(ownerDirectory: store.directory.deletingLastPathComponent(), additionalJSON: [data])
        }
    }

    func preserveAttachmentOriginal(_ data: Data, store: EncryptedAttachmentStore) throws {
        guard try AttachmentJSON.containsInlineImages(data) else { return }
        let folder = store.directory.deletingLastPathComponent().appending(path: "AttachmentMigrationOriginals", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appending(path: "study-topics-v1.json")
        if !FileManager.default.fileExists(atPath: source.path) { try EncryptedPersonalFile.write(data, to: source) }
    }

    static func protects(_ key: String) -> Bool {
        if key == "aquinas.settings.userName" || key == "aquinas.settings.customInstructions" { return true }
        if key.hasPrefix("aquinas.settings.") { return false }
        return key.lowercased().hasPrefix("aquinas") || key.lowercased().hasPrefix("angrove")
    }

    func read(_ key: String) throws -> Any? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard Self.protects(key) else { return stored }
        if let data = stored as? Data, LocalDataCipher.isEncrypted(data) {
            let decoded = try cipher.open(data, context: "preferences:" + key)
            let value = try PropertyListSerialization.propertyList(from: decoded, format: nil)
            guard let wrapper = value as? [String: Any], let value = wrapper["value"] else {
                throw LocalDataEncryptionError.invalidEnvelope
            }
            return value
        }
        // Personal legacy Data values are Codable JSON. Reject damage instead of wrapping it
        // as a new encrypted value and losing the original representation.
        if let data = stored as? Data {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        // Verify a replacement before deleting the only legacy representation.
        try write(stored, key: key)
        return stored
    }

    func write(_ value: Any, key: String) throws {
        guard Self.protects(key) else { defaults.set(value, forKey: key); return }
        guard !PersonalDataProtection.isBlocked else { throw LocalDataEncryptionError.storageClosed }
        if let existing = defaults.data(forKey: key), LocalDataCipher.isEncrypted(existing) {
            _ = try cipher.open(existing, context: "preferences:" + key)
        }
        let plain = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
        let encrypted = try cipher.seal(plain, context: "preferences:" + key)
        guard try cipher.open(encrypted, context: "preferences:" + key) == plain else {
            throw LocalDataEncryptionError.invalidEnvelope
        }
        defaults.set(encrypted, forKey: key)
    }

    func object(forKey key: String) -> Any? {
        do { return try read(key) }
        catch { PersonalDataProtection.report(error); return nil }
    }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    func set(_ value: Any?, forKey key: String) {
        do {
            guard let value else { removeObject(forKey: key); return }
            guard !PersonalDataProtection.isBlocked else { return }
            try write(value, key: key)
        } catch { PersonalDataProtection.report(error, duringWrite: true) }
    }
    func removeObject(forKey key: String) {
        guard !PersonalDataProtection.isBlocked else { return }
        defaults.removeObject(forKey: key)
    }

    /// A JSON-encoded value, or `nil` when it is missing or no longer decodes as `Value`.
    func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        data(forKey: key).flatMap { try? decoder(for: key).decode(type, from: $0) }
    }

    /// Stores `value` JSON-encoded. A value that fails to encode leaves the stored one in place.
    func setEncoded<Value: Encodable>(_ value: Value, forKey key: String) {
        do { try writeEncoded(value, key: key) }
        catch { PersonalDataProtection.report(error, duringWrite: true) }
    }
}

nonisolated enum PersonalDataProtection {
    static let failureNotification = Notification.Name("angroveEncryptedStorageFailed")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var blocked = false
    static var isBlocked: Bool { lock.withLock { blocked } }

    static func block() { lock.withLock { blocked = true } }

    /// Called only after startup validation or the person’s explicit recovery action.
    static func finishValidatedRecovery() { lock.withLock { blocked = false } }

    /// A failed read can leave a store looking empty, and saving that would overwrite real data,
    /// so every read failure closes storage. A failed write only loses that one save; it closes
    /// storage only when existing ciphertext or the key itself is in doubt.
    static func report(_ error: Error, duringWrite: Bool = false) {
        guard !duringWrite || isIntegrityFailure(error) else {
#if DEBUG
            print("Angrove encrypted save deferred: \(error.localizedDescription)")
#endif
            return
        }
        block()
        NotificationCenter.default.post(name: failureNotification, object: error)
    }

    /// The key is missing or wrong, or stored bytes are damaged. Locked-device Keychain and file
    /// protection errors are temporary and are not integrity failures.
    static func isIntegrityFailure(_ error: Error) -> Bool {
        if error is AttachmentStorageError { return true }
        if error is CryptoKitError { return true }
        guard let error = error as? LocalDataEncryptionError else { return false }
        switch error {
        case .keychain, .storageClosed: return false
        case .missingKey, .invalidKey, .invalidEnvelope: return true
        }
    }

    /// Bytes that cannot be what the current key wrote. Distinct from a missing or unusable key.
    static func isDamage(_ error: Error) -> Bool {
        if error is CryptoKitError { return true }
        if case .invalidEnvelope = error as? LocalDataEncryptionError { return true }
        return false
    }

    /// Whether the person can choose to set unreadable data aside and start over. Temporary
    /// Keychain unavailability (a locked phone) resolves by unlocking instead.
    static func offersFreshStart(_ error: Error) -> Bool { isIntegrityFailure(error) }
}

nonisolated enum EncryptedPersonalFile {
    /// Isolates file fixtures from the owner's Keychain. Production callers use the personal key.
    @TaskLocal static var scopedCipher: LocalDataCipher?
    static var cipher: LocalDataCipher { scopedCipher ?? .personal }

    static func context(for url: URL) -> String {
        // Rotating conversation backups must remain readable at the live location.
        url.path.contains("ConversationStore/") || url.lastPathComponent.hasPrefix("conversations-")
            ? "conversation-snapshot-v1" : "personal-file:" + url.lastPathComponent
    }

    static func read(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        if LocalDataCipher.isEncrypted(data) {
            do { return try cipher.open(data, context: context(for: url)) }
            catch { PersonalDataProtection.report(error); throw error }
        }
        // Legacy stores are JSON. Never interpret damaged ciphertext as a legacy value.
        guard isValidLegacy(data, url: url) else { throw LocalDataEncryptionError.invalidEnvelope }
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try write(data, to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return data
    }

    /// Plaintext written before encryption: JSON, or JSON Lines for the generation log.
    static func isValidLegacy(_ data: Data, url: URL) -> Bool {
        if url.pathExtension == "jsonl" {
            return data.split(separator: 0x0A).allSatisfy { line in
                (try? JSONSerialization.jsonObject(with: Data(line))) != nil
            }
        }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    /// `existingVerified` means the caller has just opened the current file with `read(_:)` on
    /// the same serial queue, so the check that it was written with the current key is done.
    static func write(_ data: Data, to url: URL, existingVerified: Bool = false) throws {
        do { try replace(data, at: url, existingVerified: existingVerified) }
        catch { PersonalDataProtection.report(error, duringWrite: true); throw error }
    }

    private static func replace(_ data: Data, at url: URL, existingVerified: Bool) throws {
        guard !PersonalDataProtection.isBlocked else { throw LocalDataEncryptionError.storageClosed }
        if !existingVerified, let existing = try? Data(contentsOf: url), LocalDataCipher.isEncrypted(existing) {
            _ = try cipher.open(existing, context: context(for: url))
        }
        let encrypted = try cipher.seal(data, context: context(for: url))
        guard try cipher.open(encrypted, context: context(for: url)) == data else {
            throw LocalDataEncryptionError.invalidEnvelope
        }
        #if os(iOS)
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try encrypted.write(to: url, options: .atomic)
        #endif
    }
}
