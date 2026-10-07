//
//  LocalInsightTreeSeedStore.swift
//  Angrove-iOS
//

import Foundation

/// A persistent on-device Node Concept extracted from a conversation turn. The embedding version
/// prevents vectors created in the old `NLEmbedding` space from being compared with bundled
/// MiniLM vectors; stale seeds are re-embedded before their next relatedness decision.
nonisolated struct LocalInsightTreeSeed: Sendable, Codable, Equatable {
    let id: UUID
    let label: String
    let summary: String
    let embedding: [Double]?
    let embeddingVersion: String?
    let createdAt: Date

    init(
        id: UUID,
        label: String,
        summary: String,
        embedding: [Double]?,
        embeddingVersion: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.label = label
        self.summary = summary
        self.embedding = embedding
        self.embeddingVersion = embeddingVersion
        self.createdAt = createdAt
    }
}

nonisolated struct LocalInsightTreeSeedFileStore: @unchecked Sendable {
    static let legacyKey = "aquinas.insight-tree.local-seeds.v1"

    let fileURL: URL
    let defaults: UserDefaults
    let fileManager: FileManager

    init(
        fileURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load() -> [String: [LocalInsightTreeSeed]] {
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                return try JSONDecoder().decode([String: [LocalInsightTreeSeed]].self,
                    from: EncryptedPersonalFile.read(fileURL))
            } catch {
                PersonalDataProtection.report(error)
                return [:]
            }
        }
        guard let data = PrivatePreferences(defaults: defaults).data(forKey: Self.legacyKey) else { return [:] }
        guard let seeds = try? JSONDecoder().decode([String: [LocalInsightTreeSeed]].self, from: data) else {
            PersonalDataProtection.report(LocalDataEncryptionError.invalidEnvelope)
            return [:]
        }
        do {
            try save(seeds)
            PrivatePreferences(defaults: defaults).removeObject(forKey: Self.legacyKey)
        } catch {
            // Preserve the legacy value until the protected file write succeeds.
        }
        return seeds
    }

    func save(_ seeds: [String: [LocalInsightTreeSeed]]) throws {
        if !fileManager.fileExists(atPath: fileURL.path),
           let legacy = PrivatePreferences(defaults: defaults).data(forKey: Self.legacyKey),
           (try? JSONDecoder().decode([String: [LocalInsightTreeSeed]].self, from: legacy)) == nil {
            throw LocalDataEncryptionError.invalidEnvelope
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            let current = try EncryptedPersonalFile.read(fileURL)
            guard (try? JSONDecoder().decode([String: [LocalInsightTreeSeed]].self, from: current)) != nil else {
                throw LocalDataEncryptionError.invalidEnvelope
            }
        }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(seeds)
        try EncryptedPersonalFile.write(data, to: fileURL)
    }
}

enum LocalInsightTreeSeedStore {
    nonisolated static func preload() {
        if let store = liveStore() { _ = SerializedPersonalStore.shared.loadSeeds(store: store) }
    }

    static func seeds(for conversationID: UUID) -> [LocalInsightTreeSeed] {
        load()[conversationID.uuidString, default: []]
    }

    static func appendSeed(_ seed: LocalInsightTreeSeed, for conversationID: UUID) {
        var all = load()
        all[conversationID.uuidString, default: []].append(seed)
        if let store = liveStore() { SerializedPersonalStore.shared.saveSeeds(all, store: store) }
    }

    static func replaceSeeds(
        _ seeds: [LocalInsightTreeSeed],
        for conversationID: UUID
    ) {
        var all = load()
        all[conversationID.uuidString] = seeds
        if let store = liveStore() { SerializedPersonalStore.shared.saveSeeds(all, store: store) }
    }

    static func removeConversation(_ conversationID: UUID) {
        var all = load()
        all.removeValue(forKey: conversationID.uuidString)
        if let store = liveStore() { SerializedPersonalStore.shared.saveSeeds(all, store: store) }
    }

    private static func load() -> [String: [LocalInsightTreeSeed]] {
        guard let store = liveStore() else { return [:] }
        return SerializedPersonalStore.shared.loadSeeds(store: store)
    }

    nonisolated private static func liveStore() -> LocalInsightTreeSeedFileStore? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return LocalInsightTreeSeedFileStore(
            fileURL: applicationSupport.appending(
                path: "Aquinas/InsightTree/local-seeds-v2.json"
            )
        )
    }
}
