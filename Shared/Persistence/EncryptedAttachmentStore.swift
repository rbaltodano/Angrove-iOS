import CryptoKit
import Foundation

/// Content identity is independent of the visible UploadedFile UUID. The latter stays stable
/// through migration; identical originals within one owner share a single encrypted blob.
nonisolated struct AttachmentReference: Codable, Equatable, Sendable {
    let version: Int
    let sha256: String
    let byteCount: Int

    func validate() throws {
        guard version == 1, byteCount >= 0, sha256.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw AttachmentStorageError.invalidReference
        }
    }
}

nonisolated enum AttachmentStorageError: LocalizedError {
    case invalidReference, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidReference: "A saved attachment reference is invalid. Your saved data has been preserved."
        case .unavailable: "A saved attachment could not be opened. Your saved data has been preserved."
        }
    }
}

/// Immutable image bytes are shared by struct copies. Digest calculation happens once, off the
/// main actor on the persistence worker, instead of hashing every image on every small edit.
nonisolated final class AttachmentPayload: @unchecked Sendable {
    let data: Data
    private let lock = NSLock()
    private var identity: AttachmentReference?
    init(_ data: Data, reference: AttachmentReference? = nil) {
        self.data = data
        identity = reference
    }
    var reference: AttachmentReference {
        lock.withLock {
            if let identity { return identity }
            let value = AttachmentReference(version: 1,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), byteCount: data.count)
            identity = value
            return value
        }
    }
}

nonisolated extension CodingUserInfoKey {
    static let attachmentStore = CodingUserInfoKey(rawValue: "com.angrove.encrypted-attachment-store.v1")!
    static let validatesAttachmentReferencesOnly = CodingUserInfoKey(rawValue: "com.angrove.attachment-validation-only.v1")!
}

/// Scoped to one owner's directory: conversations (including backups), Boards, or Topics.
/// Registry identity makes the transaction lock cover every codec instance for that owner.
nonisolated final class EncryptedAttachmentStore: @unchecked Sendable {
    let directory: URL
    private let cipher: LocalDataCipher
    private let lock = NSRecursiveLock()
    private struct Stamp: Equatable { let size: Int; let modified: Date? }
    private var verified: [String: (stamp: Stamp, byteCount: Int)] = [:]
    private var inventories: [URL: (stamp: Stamp, references: Set<String>)] = [:]
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: EncryptedAttachmentStore] = [:]

    init(directory: URL, cipher: LocalDataCipher = .personal) {
        self.directory = directory
        self.cipher = cipher
    }

    static func scoped(to owner: URL) -> EncryptedAttachmentStore {
        let directory = owner.standardizedFileURL.appending(path: "Attachments", directoryHint: .isDirectory)
        return registryLock.withLock {
            if let store = registry[directory.path] { return store }
            let store = EncryptedAttachmentStore(directory: directory, cipher: EncryptedPersonalFile.cipher)
            registry[directory.path] = store
            return store
        }
    }

    static var topics: EncryptedAttachmentStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return scoped(to: base.appending(path: ModelPlatformPolicy.current.storagePath("Aquinas/StudyTopics")))
    }

    func transaction<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.userInfo[.attachmentStore] = self
        return encoder
    }
    func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.attachmentStore] = self
        return decoder
    }

    /// Validates a stored parent's schema before replacement without materializing all of its
    /// images again. The decoded value is deliberately discarded inside this boundary.
    func validate<Value: Decodable>(_ type: Value.Type, json: Data) throws {
        let decoder = decoder()
        decoder.userInfo[.validatesAttachmentReferencesOnly] = true
        _ = try decoder.decode(type, from: json)
    }

    func validate(_ reference: AttachmentReference) throws {
        try transaction {
            let source = try url(for: reference)
            let current = try stamp(source)
            if verified[reference.sha256]?.stamp != current || verified[reference.sha256]?.byteCount != reference.byteCount { _ = try read(reference) }
        }
    }

    func url(for reference: AttachmentReference) throws -> URL {
        try reference.validate()
        return directory.appending(path: reference.sha256 + ".attachment")
    }
    private func context(_ reference: AttachmentReference) -> String {
        "attachment-v1:" + reference.sha256
    }
    private func stamp(_ url: URL) throws -> Stamp {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Stamp(size: values.fileSize ?? -1, modified: values.contentModificationDate)
    }
    private func verify(_ data: Data, _ reference: AttachmentReference) throws {
        guard data.count == reference.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == reference.sha256 else {
            throw AttachmentStorageError.unavailable
        }
    }

    func put(_ payload: AttachmentPayload) throws -> AttachmentReference {
        try transaction {
            guard !PersonalDataProtection.isBlocked else { throw LocalDataEncryptionError.storageClosed }
            let reference = payload.reference
            let destination = try url(for: reference)
            if FileManager.default.fileExists(atPath: destination.path) {
                let current = try stamp(destination)
                if verified[reference.sha256]?.stamp != current || verified[reference.sha256]?.byteCount != reference.byteCount {
                    let plain = try cipher.open(Data(contentsOf: destination), context: context(reference))
                    try verify(plain, reference)
                    verified[reference.sha256] = (current, reference.byteCount)
                }
                return reference
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sealed = try cipher.seal(payload.data, context: context(reference))
            guard try cipher.open(sealed, context: context(reference)) == payload.data else {
                throw AttachmentStorageError.unavailable
            }
            #if os(iOS)
            try sealed.write(to: destination, options: [.atomic, .completeFileProtection])
            #else
            try sealed.write(to: destination, options: .atomic)
            #endif
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.synchronize()
            // Verify persisted bytes, not only the in-memory envelope, before publishing a reference.
            try verify(cipher.open(Data(contentsOf: destination), context: context(reference)), reference)
            verified[reference.sha256] = (try stamp(destination), reference.byteCount)
            return reference
        }
    }

    func read(_ reference: AttachmentReference) throws -> AttachmentPayload {
        try transaction {
            guard !PersonalDataProtection.isBlocked else { throw LocalDataEncryptionError.storageClosed }
            let source = try url(for: reference)
            guard FileManager.default.fileExists(atPath: source.path) else { throw AttachmentStorageError.unavailable }
            let plain = try cipher.open(Data(contentsOf: source), context: context(reference))
            try verify(plain, reference)
            verified[reference.sha256] = (try stamp(source), reference.byteCount)
            return AttachmentPayload(plain, reference: reference)
        }
    }

    /// Snapshot originals are ciphertext already. Copy them intact before the first reference
    /// replacement, and never replace an earlier migration recovery copy.
    func preserveOriginal(at source: URL, plaintext: Data) throws {
        guard try AttachmentJSON.containsInlineImages(plaintext) else { return }
        let recovery = source.deletingLastPathComponent().appending(path: "AttachmentMigrationOriginals", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let destination = recovery.appending(path: source.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func preserveLegacyValue(_ data: Data, destination: URL) throws {
        guard try AttachmentJSON.containsInlineImages(data) else { return }
        let recovery = destination.deletingLastPathComponent().appending(path: "AttachmentMigrationOriginals", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let original = recovery.appending(path: destination.lastPathComponent)
        if !FileManager.default.fileExists(atPath: original.path) { try EncryptedPersonalFile.write(data, to: original) }
    }

    /// Sweep only after a successful parent commit, under its owner transaction/serial worker.
    /// Retain references from every backup and migration original. Any unreadable inventory
    /// cancels the entire sweep; no individual decode failure can turn into image deletion.
    func prune(ownerDirectory: URL, additionalJSON: [Data] = []) {
        transaction {
            do {
                guard FileManager.default.fileExists(atPath: directory.path) else { return }
                var references = Set<String>()
                for data in additionalJSON { try AttachmentJSON.collectReferences(data, into: &references) }
                let files = try AttachmentJSON.jsonFiles(in: ownerDirectory)
                for file in files {
                    let current = try stamp(file)
                    if let cached = inventories[file], cached.stamp == current {
                        references.formUnion(cached.references)
                    } else {
                        var found = Set<String>()
                        let bytes = try Data(contentsOf: file)
                        let json = LocalDataCipher.isEncrypted(bytes)
                            ? try cipher.open(bytes, context: EncryptedPersonalFile.context(for: file)) : bytes
                        try AttachmentJSON.collectReferences(json, into: &found)
                        inventories[file] = (current, found)
                        references.formUnion(found)
                    }
                }
                inventories = inventories.filter { files.contains($0.key) }
                guard let blobs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
                for blob in blobs where blob.pathExtension == "attachment" && !references.contains(blob.deletingPathExtension().lastPathComponent) {
                    try FileManager.default.removeItem(at: blob)
                    verified.removeValue(forKey: blob.deletingPathExtension().lastPathComponent)
                }
            } catch { /* A conservative sweep is optional; the committed parent remains valid. */ }
        }
    }
}

/// A schema-limited transformer migrates nested UploadedFiles without importing MainActor UI
/// models. It preserves every unrelated field, including fields added by newer app versions.
nonisolated enum AttachmentJSON {
    static func jsonFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var result: [URL] = []
        for item in try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw AttachmentStorageError.invalidReference }
            if values.isDirectory == true { result += try jsonFiles(in: item) }
            else if item.pathExtension == "json" { result.append(item) }
        }
        return result
    }
    static func containsInlineImages(_ data: Data) throws -> Bool {
        var found = false
        _ = try visit(JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) { object in
            if isUpload(object), object["imageData"] is String { found = true }
            return object
        }
        return found
    }

    static func migrate(_ data: Data, store: EncryptedAttachmentStore) throws -> Data? {
        var changed = false
        let result = try visit(JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) { object in
            guard isUpload(object) else { return object }
            if let encoded = object["imageData"] as? String {
                guard object["attachment"] == nil || object["attachment"] is NSNull,
                      let bytes = Data(base64Encoded: encoded) else {
                    throw AttachmentStorageError.invalidReference
                }
                let reference = try store.put(AttachmentPayload(bytes))
                var next = object
                next.removeValue(forKey: "imageData")
                next["attachment"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference))
                changed = true
                return next
            }
            if let value = object["attachment"], !(value is NSNull) {
                let reference = try JSONDecoder().decode(AttachmentReference.self, from: JSONSerialization.data(withJSONObject: value))
                _ = try store.read(reference)
            }
            return object
        }
        return changed ? try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .fragmentsAllowed]) : nil
    }

    static func collectReferences(_ data: Data, into references: inout Set<String>) throws {
        _ = try visit(JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) { object in
            if let value = object["attachment"], !(value is NSNull) {
                let reference = try JSONDecoder().decode(AttachmentReference.self, from: JSONSerialization.data(withJSONObject: value))
                try reference.validate()
                references.insert(reference.sha256)
            }
            return object
        }
    }
    private static func isUpload(_ object: [String: Any]) -> Bool {
        object["id"] is String && object["name"] is String && object["rotationDegrees"] is NSNumber
    }
    private static func visit(_ value: Any, transform: ([String: Any]) throws -> [String: Any]) throws -> Any {
        if let array = value as? [Any] { return try array.map { try visit($0, transform: transform) } }
        guard let object = value as? [String: Any] else { return value }
        var next: [String: Any] = [:]
        for (key, value) in object { next[key] = try visit(value, transform: transform) }
        return try transform(next)
    }
}
