//
//  InsightDiscoveryStore.swift
//  Angrove-iOS
//

import Foundation

enum InsightDiscoveryStore {
    private static let seenInsightIDsKey = "AquinasSeenInsightIDs"
    private static let seenNodeIDsKey = "AquinasSeenNodeIDs"
    private static let undiscoveredIDsKey = "AquinasUndiscoveredInsightIDs"
    private static let undiscoveredNodeIDsKey = "AquinasUndiscoveredNodeIDs"
    private static let pendingInsightPresentationIDsKey =
        "AquinasPendingInsightPresentationIDs"
    private static let pendingNodePresentationIDsKey =
        "AquinasPendingNodePresentationIDs"

    static func loadSeenInsightIDs(preferences: PrivatePreferences = .standard) -> Set<UUID> {
        guard let strings = loadStrings(forKey: seenInsightIDsKey, preferences: preferences) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    static func saveSeenInsightIDs(_ ids: [UUID], preferences: PrivatePreferences = .standard) {
        saveStrings(ids.map(\.uuidString), forKey: seenInsightIDsKey, preferences: preferences)
    }

    /// Loading an existing snapshot into an empty canvas is not a new discovery.
    static func newInsightIDs(
        in currentIDs: Set<UUID>,
        excluding previousIDs: Set<UUID> = [],
        preferences: PrivatePreferences = .standard
    ) -> Set<UUID> {
        currentIDs.subtracting(previousIDs)
            .subtracting(loadIDs(forKey: seenInsightIDsKey, preferences: preferences))
    }

    static func newNodeIDs(
        in currentIDs: Set<UUID>,
        excluding previousIDs: Set<UUID> = [],
        memberInsightIDs: [UUID: Set<UUID>] = [:],
        preferences: PrivatePreferences = .standard
    ) -> Set<UUID> {
        var seenNodes = loadIDs(forKey: seenNodeIDsKey, preferences: preferences)
        if seenNodes.isEmpty {
            // Older versions kept only Insight history. Preserve their existing parent Nodes
            // on the first visit after upgrading, even if a new Insight has joined that Node.
            let seenInsights = loadIDs(forKey: seenInsightIDsKey, preferences: preferences)
            seenNodes.formUnion(memberInsightIDs.compactMap { nodeID, insightIDs in
                insightIDs.isDisjoint(with: seenInsights) ? nil : nodeID
            })
        }
        return currentIDs.subtracting(previousIDs).subtracting(seenNodes)
    }

    /// Record the entrance before starting its cancellable animation. Keep discovery dots
    /// until the user opens the card, but never replay the entrance on the next tree visit.
    static func markPresented(
        insightIDs: Set<UUID>,
        nodeIDs: Set<UUID> = [],
        preferences: PrivatePreferences = .standard
    ) {
        let seen = loadIDs(forKey: seenInsightIDsKey, preferences: preferences)
        saveIDs(seen.union(insightIDs), forKey: seenInsightIDsKey, preferences: preferences)
        let seenNodes = loadIDs(forKey: seenNodeIDsKey, preferences: preferences)
        saveIDs(seenNodes.union(nodeIDs), forKey: seenNodeIDsKey, preferences: preferences)
        let pendingInsights = loadIDs(forKey: pendingInsightPresentationIDsKey, preferences: preferences)
        let pendingNodes = loadIDs(forKey: pendingNodePresentationIDsKey, preferences: preferences)
        saveIDs(pendingInsights.subtracting(insightIDs), forKey: pendingInsightPresentationIDsKey, preferences: preferences)
        saveIDs(pendingNodes.subtracting(nodeIDs), forKey: pendingNodePresentationIDsKey, preferences: preferences)
    }

    static func markDiscovered(_ id: UUID, preferences: PrivatePreferences = .standard) {
        markPresented(insightIDs: [id], preferences: preferences)
        let undiscovered = loadIDs(forKey: undiscoveredIDsKey, preferences: preferences)
        saveIDs(undiscovered.subtracting([id]), forKey: undiscoveredIDsKey, preferences: preferences)
    }

    static func loadUndiscoveredInsightIDs() -> Set<UUID> {
        guard let strings = loadStrings(forKey: undiscoveredIDsKey, preferences: .standard) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    static func saveUndiscoveredInsightIDs(_ ids: Set<UUID>) {
        saveStrings(ids.map(\.uuidString), forKey: undiscoveredIDsKey, preferences: .standard)
    }

    @discardableResult
    static func markUndiscovered(_ ids: [UUID]) -> Set<UUID> {
        var current = loadUndiscoveredInsightIDs()
        var changed = false
        for id in ids where !current.contains(id) {
            current.insert(id)
            changed = true
        }
        if changed {
            saveUndiscoveredInsightIDs(current)
        }
        return current
    }

    @discardableResult
    static func markNewInsightsUndiscovered(_ currentInsightIDs: [UUID]) -> Set<UUID> {
        let seenIDs = loadSeenInsightIDs()
        let newIDs = currentInsightIDs.filter { !seenIDs.contains($0) }
        return markUndiscovered(newIDs)
    }

    static func visibleUndiscoveredCount(for visibleInsightIDs: [UUID]) -> Int {
        loadUndiscoveredInsightIDs()
            .intersection(Set(visibleInsightIDs))
            .count
    }

    static func loadUndiscoveredNodeIDs() -> Set<UUID> {
        loadIDs(forKey: undiscoveredNodeIDsKey)
    }

    static func saveUndiscoveredNodeIDs(_ ids: Set<UUID>) {
        saveIDs(ids, forKey: undiscoveredNodeIDsKey)
    }

    @discardableResult
    static func markNodesUndiscovered(_ ids: [UUID]) -> Set<UUID> {
        var current = loadUndiscoveredNodeIDs()
        let previousCount = current.count
        current.formUnion(ids)
        if current.count != previousCount {
            saveUndiscoveredNodeIDs(current)
        }
        return current
    }

    static func markPendingTreePresentation(
        insightIDs: [UUID],
        nodeIDs: [UUID]
    ) {
        var pendingInsights = pendingInsightPresentationIDs()
        var pendingNodes = pendingNodePresentationIDs()
        pendingInsights.formUnion(insightIDs)
        pendingNodes.formUnion(nodeIDs)
        saveIDs(pendingInsights, forKey: pendingInsightPresentationIDsKey)
        saveIDs(pendingNodes, forKey: pendingNodePresentationIDsKey)
    }

    static func pendingInsightPresentationIDs() -> Set<UUID> {
        loadIDs(forKey: pendingInsightPresentationIDsKey)
    }

    static func pendingNodePresentationIDs() -> Set<UUID> {
        loadIDs(forKey: pendingNodePresentationIDsKey)
    }

    static func clearPendingTreePresentation(
        insightIDs: Set<UUID>,
        nodeIDs: Set<UUID>
    ) {
        var pendingInsights = pendingInsightPresentationIDs()
        var pendingNodes = pendingNodePresentationIDs()
        pendingInsights.subtract(insightIDs)
        pendingNodes.subtract(nodeIDs)
        saveIDs(pendingInsights, forKey: pendingInsightPresentationIDsKey)
        saveIDs(pendingNodes, forKey: pendingNodePresentationIDsKey)
    }

    private static func loadIDs(forKey key: String, preferences: PrivatePreferences = .standard) -> Set<UUID> {
        guard let strings = loadStrings(forKey: key, preferences: preferences) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func saveIDs(_ ids: Set<UUID>, forKey key: String, preferences: PrivatePreferences = .standard) {
        saveStrings(ids.map(\.uuidString), forKey: key, preferences: preferences)
    }

    private static func loadStrings(forKey key: String, preferences: PrivatePreferences) -> [String]? {
        if preferences.defaults === UserDefaults.standard {
            if let stored = InsightTreeLocalStateStore.load([String].self, key: key) {
                return stored
            }
            guard let legacy = preferences.stringArray(forKey: key) else { return nil }
            InsightTreeLocalStateStore.save(legacy, key: key)
            if InsightTreeLocalStateStore.load([String].self, key: key) == legacy {
                preferences.removeObject(forKey: key)
            }
            return legacy
        }
        return preferences.stringArray(forKey: key)
    }

    private static func saveStrings(_ values: [String], forKey key: String, preferences: PrivatePreferences) {
        if preferences.defaults === UserDefaults.standard {
            InsightTreeLocalStateStore.save(values, key: key)
            if InsightTreeLocalStateStore.load([String].self, key: key) == values {
                preferences.removeObject(forKey: key)
            }
        } else {
            preferences.set(values, forKey: key)
        }
    }
}
