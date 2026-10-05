//
//  GlossedTermStore.swift
//  Angrove-iOS
//

import Foundation

/// A contextual definition the user looked up in a conversation. Home's "Terms You Glossed Over"
/// resurfaces one that was never saved as an Insight.
struct GlossedTermRecord: Codable, Equatable {
    let definition: ConceptDefinition
    let requestedTerm: String
    let lookedUpAt: Date
}

/// Records definition lookups per conversation. The first lookup of a term is kept so its age
/// reflects when the user first skimmed past it; later lookups of the same term don't reset it.
enum GlossedTermStore {
    static let storageKey = "aquinas.home.glossed-terms.v1"

    static func recordLookup(
        _ definition: ConceptDefinition,
        requestedTerm: String,
        in conversationID: UUID,
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        var all = load(defaults: defaults)
        var records = all[conversationID.uuidString, default: []]
        guard !records.contains(where: { $0.definition.id == definition.id }) else { return }
        records.append(
            GlossedTermRecord(definition: definition, requestedTerm: requestedTerm, lookedUpAt: date)
        )
        all[conversationID.uuidString] = records
        save(all, defaults: defaults)
    }

    static func records(
        for conversationID: UUID,
        defaults: UserDefaults = .standard
    ) -> [GlossedTermRecord] {
        load(defaults: defaults)[conversationID.uuidString, default: []]
    }

    static func removeConversation(_ conversationID: UUID, defaults: UserDefaults = .standard) {
        var all = load(defaults: defaults)
        all.removeValue(forKey: conversationID.uuidString)
        save(all, defaults: defaults)
    }

    private static func load(defaults: UserDefaults) -> [String: [GlossedTermRecord]] {
        guard let data = PrivatePreferences(defaults: defaults).data(forKey: storageKey),
              let records = try? JSONDecoder().decode(
                [String: [GlossedTermRecord]].self,
                from: data
              ) else {
            return [:]
        }
        return records
    }

    private static func save(_ records: [String: [GlossedTermRecord]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        PrivatePreferences(defaults: defaults).set(data, forKey: storageKey)
    }
}
