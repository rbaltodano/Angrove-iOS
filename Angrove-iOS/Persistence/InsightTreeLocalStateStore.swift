//
//  InsightTreeLocalStateStore.swift
//  Angrove-iOS
//

import CryptoKit
import Foundation

/// Protected, atomic storage for on-device Insight Tree topology and presentation state. Each
/// logical legacy key maps to its own file so one corrupt canvas detail cannot invalidate the rest
/// of the tree. Existing `UserDefaults` values migrate on first read.
struct InsightTreeLocalStateFileStore {
    let rootDirectory: URL
    let defaults: UserDefaults
    let fileManager: FileManager

    init(
        rootDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        let fileURL = url(for: key)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try EncryptedPersonalFile.read(fileURL)
                return try JSONDecoder().decode(type, from: data)
            } catch {
                // A damaged current file must not fall through to an older value or be treated
                // as an empty collection. Keep the bytes in place for recovery.
                PersonalDataProtection.report(error)
                return nil
            }
        }
        guard let data = PrivatePreferences(defaults: defaults).data(forKey: key) else {
            return nil
        }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            PersonalDataProtection.report(LocalDataEncryptionError.invalidEnvelope)
            return nil
        }
        do {
            try save(value, key: key)
            PrivatePreferences(defaults: defaults).removeObject(forKey: key)
        } catch {
            // Retain the legacy copy until the protected file write succeeds.
        }
        return value
    }

    func save<Value: Codable>(_ value: Value, key: String) throws {
        let fileURL = url(for: key)
        if let legacy = PrivatePreferences(defaults: defaults).data(forKey: key),
           !fileManager.fileExists(atPath: fileURL.path),
           (try? JSONDecoder().decode(Value.self, from: legacy)) == nil {
            // Do not turn an undecodable legacy tree into a new, empty file. Keep the original
            // preference available for a future recovery or migration.
            PersonalDataProtection.report(LocalDataEncryptionError.invalidEnvelope, duringWrite: true)
            throw LocalDataEncryptionError.invalidEnvelope
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            // EncryptedPersonalFile validates the envelope, but the payload may still be
            // undecodable after a schema change or partial migration. Never replace it blindly.
            let existing = try EncryptedPersonalFile.read(fileURL)
            guard (try? JSONDecoder().decode(Value.self, from: existing)) != nil else {
                PersonalDataProtection.report(LocalDataEncryptionError.invalidEnvelope, duringWrite: true)
                throw LocalDataEncryptionError.invalidEnvelope
            }
        }
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        try EncryptedPersonalFile.write(data, to: fileURL)
    }

    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return rootDirectory.appending(path: "\(name).json")
    }
}

enum InsightTreeLocalStateStore {
    static func load<Value: Codable>(
        _ type: Value.Type,
        key: String,
        defaults: UserDefaults = .standard
    ) -> Value? {
        store(defaults: defaults)?.load(type, key: key)
    }

    static func save<Value: Codable>(_ value: Value, key: String, defaults: UserDefaults = .standard) {
        try? store(defaults: defaults)?.save(value, key: key)
    }

    private static func store(defaults: UserDefaults) -> InsightTreeLocalStateFileStore? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return InsightTreeLocalStateFileStore(
            rootDirectory: applicationSupport.appending(
                path: "Aquinas/InsightTree/CanvasState",
                directoryHint: .isDirectory
            ),
            defaults: defaults
        )
    }
}
