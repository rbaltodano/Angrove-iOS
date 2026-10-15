//
//  InsightTreeReset.swift
//  Angrove-iOS
//

import Foundation

/// Wipes every on-device Insight Tree artifact so the tree can be rebuilt from scratch: saved
/// (bookmarked) Insights, the global and Study Topic tree snapshots, Nodes, positions, Make Node
/// children, placed Midpoints, discovery dots, seeds, and pending analysis. Conversations
/// themselves are untouched.
enum InsightTreeReset {
    /// Exact UserDefaults keys owned by Insight Tree stores.
    static let exactKeys: [String] = [
        "aquinas.saved.insights.v1",
        "aquinas.global-insight-tree.snapshot.v1",
        "aquinas.global-insight-tree.promoted-ids.v1",
        "aquinas.global-insight-tree.acknowledged-library-ids.v1",
        "aquinas.study-topic.insight-trees.v1",
        "aquinas.pendingInsightTreeAnalysis.v2", // retired backend analysis queue
        "aquinas.conversation.insight-memberships.v1",
        "AquinasSeenInsightIDs",
        "AquinasSeenNodeIDs",
        "AquinasUndiscoveredInsightIDs",
        "AquinasUndiscoveredNodeIDs",
        "AquinasPendingInsightPresentationIDs",
        "AquinasPendingNodePresentationIDs",
    ]

    /// Per-scope keys (positions, labels, clusters, Make Node children, placed Midpoints, seeds).
    static let keyPrefix = "aquinas.insight-tree."

    static func clearPersistedData(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupport: URL? = nil
    ) {
        SerializedPersonalStore.shared.invalidate()
        for key in exactKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }

        #if os(macOS)
        // The Mac stores live under its own folder; never touch a shared Application Support path.
        let base = applicationSupport
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appending(path: "Angrove-macOS", directoryHint: .isDirectory)
        #else
        let base = applicationSupport
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        if let directory = base?.appending(path: "Aquinas/InsightTree", directoryHint: .isDirectory) {
            try? fileManager.removeItem(at: directory)
        }
    }
}
