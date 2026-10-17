import Foundation

/// Runs behind the encrypted startup gate, before feature stores are preloaded. It is resumable:
/// blobs are immutable, originals survive, and each parent promotion is an independent atomic
/// write. An interrupted attempt can leave extra blobs, but cannot publish a dangling reference.
nonisolated enum AttachmentMigration {
    static func prepare(root: URL, preferences: PrivatePreferences) throws {
        for name in ["ConversationStore", "Worktree"] {
            let owner = root.appending(path: name, directoryHint: .isDirectory)
            let store = EncryptedAttachmentStore.scoped(to: owner)
            try store.transaction {
                for source in try AttachmentJSON.jsonFiles(in: owner)
                    where !source.pathComponents.contains("AttachmentMigrationOriginals") {
                    try autoreleasepool { try migrateFile(source, store: store) }
                }
                store.prune(ownerDirectory: owner)
            }
        }
        let key = "aquinas.study-topics.v1"
        if let store = preferences.attachments(for: key), let value = try preferences.read(key) {
            guard let data = value as? Data else { throw LocalDataEncryptionError.invalidEnvelope }
            try store.transaction {
                if let migrated = try AttachmentJSON.migrate(data, store: store) {
                    try preferences.preserveAttachmentOriginal(data, store: store)
                    try preferences.write(migrated, key: key)
                    guard try preferences.read(key) as? Data == migrated else { throw AttachmentStorageError.unavailable }
                    store.prune(ownerDirectory: store.directory.deletingLastPathComponent(), additionalJSON: [migrated])
                }
            }
        }
    }

    static func migrateFile(_ source: URL, store: EncryptedAttachmentStore,
                            beforeCommit: () throws -> Void = {}) throws {
        try store.transaction {
            let original = try EncryptedPersonalFile.read(source)
            guard let migrated = try AttachmentJSON.migrate(original, store: store) else { return }
            try store.preserveOriginal(at: source, plaintext: original)
            try beforeCommit()
            try EncryptedPersonalFile.write(migrated, to: source, existingVerified: true)
        }
    }
}
