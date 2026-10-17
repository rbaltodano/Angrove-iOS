import CryptoKit
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

nonisolated extension PersonalDataProtection {
    static func prepare(
        preferences: PrivatePreferences = .standard,
        rootDirectory: URL? = nil,
        diagnosticLogURL: URL? = nil,
        migrateWidget: () throws -> Void = { try DailyQuestionWidgetStore.migrate() },
        discardWidget: () -> Void = { DailyQuestionWidgetStore.discard() }
    ) throws {
        if rootDirectory == nil { _ = keyPurgeObservers }
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
        let root = rootDirectory ?? base.appending(path: ModelPlatformPolicy.current.storagePath("Aquinas"))
        var files: [URL] = []
        for directory in ["ConversationStore", "InsightTree", "Worktree", "StudyTopics"] {
            if let enumerator = FileManager.default.enumerator(at: root.appending(path: directory), includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let url as URL in enumerator where url.pathExtension == "json"
                    && !url.pathComponents.contains("AttachmentMigrationOriginals") {
                    files.append(url)
                }
            }
        }
        if let log = diagnosticLogURL ?? generationLogURL(rootDirectory: rootDirectory) {
            if FileManager.default.fileExists(atPath: log.path) { files.append(log) }
        }
        var damaged: [(url: URL, error: Error, encrypted: Bool)] = []
        var legacyFiles: [URL] = []
        for url in files {
            let data = try Data(contentsOf: url)
            if LocalDataCipher.isEncrypted(data) {
                do {
                    _ = try EncryptedPersonalFile.cipher.open(data, context: EncryptedPersonalFile.context(for: url))
                    keyVerified = true
                } catch where isDamage(error) {
                    damaged.append((url, error, true))
                }
            } else if !EncryptedPersonalFile.isValidLegacy(data, url: url) {
                // Damaged plaintext predates encryption; no key is involved in judging it.
                damaged.append((url, LocalDataEncryptionError.invalidEnvelope, false))
            } else {
                legacyFiles.append(url)
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
        finishValidatedRecovery()
        for key in keys { _ = try preferences.read(key) }
        for url in legacyFiles { _ = try EncryptedPersonalFile.read(url) }
        try AttachmentMigration.prepare(root: root, preferences: preferences)
        do {
            try migrateWidget()
        } catch where isIntegrityFailure(error) {
            // The widget only mirrors today's question, which the app regenerates. It must never
            // keep the person out of their own conversations.
            discardWidget()
        } catch {
            // Temporarily unavailable; the widget keeps its value and the app opens normally.
        }
        finishValidatedRecovery()
        if rootDirectory == nil {
            SerializedPersonalStore.shared.preload(root: root.appending(path: "InsightTree/CanvasState"))
            LocalInsightTreeSeedStore.preload()
            SerializedPersonalStore.shared.preloadPreferences()
            InquiryPersistenceStore.preload()
        }
    }

    /// The personal key is cached in memory only while protected data is available.
    nonisolated(unsafe) private static let keyPurgeObservers: [NSObjectProtocol] = {
        #if os(iOS)
        return [NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: nil
        ) { _ in LocalDataKeychain.purgeCachedKeys() }]
        #else
        let center = NSWorkspace.shared.notificationCenter
        return [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in LocalDataKeychain.purgeCachedKeys() }
        }
        #endif
    }()

    private static func quarantineStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    private static func generationLogURL(rootDirectory: URL?) -> URL? {
        guard rootDirectory == nil else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appending(path: "litert-generations.jsonl")
    }

    /// Sets every unreadable personal store aside, unmodified, and clears the encrypted
    /// preferences that cannot be opened, so the app can start with a new key. Nothing is erased:
    /// files move to `Application Support/Angrove Unreadable Data <date>/`.
    static func startFresh(
        preferences: PrivatePreferences = .standard,
        rootDirectory: URL? = nil,
        diagnosticLogURL: URL? = nil,
        removeUnusableKey: Bool
    ) throws {
        SerializedPersonalStore.shared.invalidate()
        if rootDirectory == nil { InquiryPersistenceStore.invalidate() }
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        let root = rootDirectory ?? base.appending(path: ModelPlatformPolicy.current.storagePath("Aquinas"))
        let archive = root.deletingLastPathComponent()
            .appending(path: "Angrove Unreadable Data \(quarantineStamp())", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        for directory in ["ConversationStore", "InsightTree", "Worktree", "StudyTopics"] {
            let source = root.appending(path: directory)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: archive.appending(path: directory))
            }
        }
        // Startup validates diagnostic ciphertext too. Preserve it with the other unreadable
        // data, or a fresh start would encounter the same missing key on its next preparation.
        if let log = diagnosticLogURL ?? generationLogURL(rootDirectory: rootDirectory),
           fileManager.fileExists(atPath: log.path) {
            try fileManager.moveItem(at: log, to: archive.appending(path: log.lastPathComponent))
        }
        // Keep the unreadable preference ciphertext beside the files instead of discarding it.
        var saved: [String: Data] = [:]
        for key in preferences.defaults.dictionaryRepresentation().keys where PrivatePreferences.protects(key) {
            if let data = preferences.defaults.data(forKey: key), LocalDataCipher.isEncrypted(data) {
                saved[key] = data
            }
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: saved, format: .binary, options: 0)
        #if os(iOS)
        try plist.write(to: archive.appending(path: "preferences.plist"), options: [.atomic, .completeFileProtection])
        #else
        try plist.write(to: archive.appending(path: "preferences.plist"), options: .atomic)
        #endif
        for key in saved.keys { preferences.defaults.removeObject(forKey: key) }
        if removeUnusableKey { try LocalDataKeychain.remove(service: LocalDataCipher.personalService) }
        finishValidatedRecovery()
    }
}
