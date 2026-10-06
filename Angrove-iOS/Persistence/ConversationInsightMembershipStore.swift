//
//  ConversationInsightMembershipStore.swift
//  Angrove-iOS
//

import Foundation

/// Records which globally bookmarked Insights were manually saved from each conversation.
/// Insight content remains owned by `InsightLibraryStore`; this store persists only identifiers.
enum ConversationInsightMembershipStore {
    private static let storageKey = "aquinas.conversation.insight-memberships.v1"

    static func insightIDs(for conversationID: UUID) -> Set<UUID> {
        Set(load()[conversationID.uuidString, default: []].compactMap(UUID.init(uuidString:)))
    }

    static func add(insightID: UUID, to conversationID: UUID) {
        var memberships = load()
        var ids = Set(memberships[conversationID.uuidString, default: []])
        ids.insert(insightID.uuidString)
        memberships[conversationID.uuidString] = ids.sorted()
        save(memberships)
    }

    static func remove(insightID: UUID, from conversationID: UUID) {
        var memberships = load()
        var ids = Set(memberships[conversationID.uuidString, default: []])
        ids.remove(insightID.uuidString)
        if ids.isEmpty {
            memberships.removeValue(forKey: conversationID.uuidString)
        } else {
            memberships[conversationID.uuidString] = ids.sorted()
        }
        save(memberships)
    }

    static func removeConversation(_ conversationID: UUID) {
        var memberships = load()
        memberships.removeValue(forKey: conversationID.uuidString)
        save(memberships)
    }

    private static func load() -> [String: [String]] {
        InsightTreeLocalStateStore.load([String: [String]].self, key: storageKey) ?? [:]
    }

    private static func save(_ memberships: [String: [String]]) {
        InsightTreeLocalStateStore.save(memberships, key: storageKey)
    }
}
