import CryptoKit
import Foundation
import UIKit

/// Keeps existing property-list types at the call sites while storing authenticated ciphertext.
/// Ordinary UI preferences remain compatible with AppStorage. All personal keys are encrypted.
nonisolated struct PrivatePreferences {
    static let standard = PrivatePreferences(defaults: .standard)
    let defaults: UserDefaults
    var cipher: LocalDataCipher = .personal

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
        data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// Stores `value` JSON-encoded. A value that fails to encode leaves the stored one in place.
    func setEncoded<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }
}

nonisolated enum PersonalDataProtection {
    static let failureNotification = Notification.Name("angroveEncryptedStorageFailed")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var blocked = false
    static var isBlocked: Bool { lock.withLock { blocked } }

    static func block() { lock.withLock { blocked = true } }

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

    static func prepare(
        preferences: PrivatePreferences = .standard,
        rootDirectory: URL? = nil,
        migrateWidget: () throws -> Void = { try DailyQuestionWidgetStore.migrate() },
        discardWidget: () -> Void = { DailyQuestionWidgetStore.discard() }
    ) throws {
        if rootDirectory == nil { _ = keyPurgeObserver }
        // Check ALL existing ciphertext before creating any key or migrating any plaintext.
        let keys = preferences.defaults.dictionaryRepresentation().keys.filter(PrivatePreferences.protects)
        // Set once any stored ciphertext opens, proving the current key is the one that wrote it.
        var keyVerified = false
        for key in keys {
            if let data = preferences.defaults.data(forKey: key), LocalDataCipher.isEncrypted(data) {
                _ = try preferences.cipher.open(data, context: "preferences:" + key)
                keyVerified = true
            }
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        let root = rootDirectory ?? base.appending(path: "Aquinas")
        var files: [URL] = []
        for directory in ["ConversationStore", "InsightTree"] {
            if let enumerator = FileManager.default.enumerator(at: root.appending(path: directory), includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let url as URL in enumerator where url.pathExtension == "json" {
                    files.append(url)
                }
            }
        }
        if rootDirectory == nil, let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let log = documents.appending(path: "litert-generations.jsonl")
            if FileManager.default.fileExists(atPath: log.path) { files.append(log) }
        }
        var damaged: [(url: URL, error: Error, encrypted: Bool)] = []
        for url in files {
            let data = try Data(contentsOf: url)
            if LocalDataCipher.isEncrypted(data) {
                do {
                    _ = try LocalDataCipher.personal.open(data, context: EncryptedPersonalFile.context(for: url))
                    keyVerified = true
                } catch where isDamage(error) {
                    damaged.append((url, error, true))
                }
            } else if !EncryptedPersonalFile.isValidLegacy(data, url: url) {
                // Damaged plaintext predates encryption; no key is involved in judging it.
                damaged.append((url, LocalDataEncryptionError.invalidEnvelope, false))
            }
        }
        // Set damaged files aside, never delete them, so the conversation store falls back to its
        // newest good backup. When no ciphertext opens at all, the key may be the problem, so
        // nothing is moved and startup stops instead.
        if !keyVerified, let unopened = damaged.first(where: \.encrypted) {
            throw unopened.error
        }
        let stamp = Self.quarantineStamp()
        for item in damaged {
            try FileManager.default.moveItem(at: item.url, to: item.url.appendingPathExtension("damaged-" + stamp))
        }
        let readable = files.filter { url in !damaged.contains { $0.url == url } }
        lock.withLock { blocked = false }
        for key in keys { _ = try preferences.read(key) }
        for url in readable { _ = try EncryptedPersonalFile.read(url) }
        do {
            try migrateWidget()
        } catch where isIntegrityFailure(error) {
            // The widget only mirrors today's question, which the app regenerates. It must never
            // keep the person out of their own conversations.
            discardWidget()
        } catch {
            // Temporarily unavailable; the widget keeps its value and the app opens normally.
        }
        lock.withLock { blocked = false }
        if rootDirectory == nil {
            SerializedPersonalStore.shared.preload(root: root.appending(path: "InsightTree/CanvasState"))
            LocalInsightTreeSeedStore.preload()
            SerializedPersonalStore.shared.preloadPreferences()
            InquiryPersistenceStore.preload()
        }
    }

    /// The personal key is cached in memory only while protected data is available.
    nonisolated(unsafe) private static let keyPurgeObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
        object: nil,
        queue: nil
    ) { _ in LocalDataKeychain.purgeCachedKeys() }

    private static func quarantineStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    /// Sets every unreadable personal store aside, unmodified, and clears the encrypted
    /// preferences that cannot be opened, so the app can start with a new key. Nothing is erased:
    /// files move to `Application Support/Angrove Unreadable Data <date>/`.
    static func startFresh(
        preferences: PrivatePreferences = .standard,
        rootDirectory: URL? = nil,
        removeUnusableKey: Bool
    ) throws {
        SerializedPersonalStore.shared.invalidate()
        if rootDirectory == nil { InquiryPersistenceStore.invalidate() }
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        let root = rootDirectory ?? base.appending(path: "Aquinas")
        let archive = root.deletingLastPathComponent()
            .appending(path: "Angrove Unreadable Data \(quarantineStamp())", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        for directory in ["ConversationStore", "InsightTree"] {
            let source = root.appending(path: directory)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: archive.appending(path: directory))
            }
        }
        // Keep the unreadable preference ciphertext beside the files instead of discarding it.
        var saved: [String: Data] = [:]
        for key in preferences.defaults.dictionaryRepresentation().keys where PrivatePreferences.protects(key) {
            if let data = preferences.defaults.data(forKey: key), LocalDataCipher.isEncrypted(data) {
                saved[key] = data
            }
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: saved, format: .binary, options: 0)
        try plist.write(to: archive.appending(path: "preferences.plist"), options: [.atomic, .completeFileProtection])
        for key in saved.keys { preferences.defaults.removeObject(forKey: key) }
        if removeUnusableKey { try LocalDataKeychain.remove(service: LocalDataCipher.personalService) }
        lock.withLock { blocked = false }
    }
}

nonisolated enum EncryptedPersonalFile {
    static func context(for url: URL) -> String {
        // Rotating conversation backups must remain readable at the live location.
        url.path.contains("ConversationStore/") || url.lastPathComponent.hasPrefix("conversations-")
            ? "conversation-snapshot-v1" : "personal-file:" + url.lastPathComponent
    }

    static func read(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        if LocalDataCipher.isEncrypted(data) {
            do { return try LocalDataCipher.personal.open(data, context: context(for: url)) }
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
            _ = try LocalDataCipher.personal.open(existing, context: context(for: url))
        }
        let encrypted = try LocalDataCipher.personal.seal(data, context: context(for: url))
        guard try LocalDataCipher.personal.open(encrypted, context: context(for: url)) == data else {
            throw LocalDataEncryptionError.invalidEnvelope
        }
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
