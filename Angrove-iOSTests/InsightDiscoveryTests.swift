import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@MainActor
@Suite("Insight discovery")
struct InsightDiscoveryTests {
    private func withPreferences(_ body: (PrivatePreferences) -> Void) throws {
        let suite = "InsightDiscoveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)
        body(PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in key }))
    }

    @Test("Reopening an empty global canvas reveals only newly added insights and nodes")
    func restoredSnapshotDoesNotReplay() throws {
        try withPreferences { preferences in
            let old = UUID(), new = UUID(), oldNode = UUID(), newNode = UUID()
            InsightDiscoveryStore.markPresented(insightIDs: [old], nodeIDs: [oldNode], preferences: preferences)
            #expect(InsightDiscoveryStore.newInsightIDs(in: [old, new], preferences: preferences) == [new])
            #expect(InsightDiscoveryStore.newNodeIDs(in: [oldNode, newNode], preferences: preferences) == [newNode])
            #expect(InsightDiscoveryStore.newInsightIDs(in: [new], excluding: [new], preferences: preferences).isEmpty)
        }
    }

    @Test("Leaving during an entrance cannot replay it; unopened cards keep their dot")
    func presentationSurvivesCancellation() throws {
        try withPreferences { preferences in
            let id = UUID(), nodeID = UUID(), other = UUID()
            preferences.set([id.uuidString], forKey: "AquinasUndiscoveredInsightIDs")
            preferences.set([id.uuidString, other.uuidString], forKey: "AquinasPendingInsightPresentationIDs")
            preferences.set([nodeID.uuidString], forKey: "AquinasPendingNodePresentationIDs")
            InsightDiscoveryStore.markPresented(insightIDs: [id], nodeIDs: [nodeID], preferences: preferences)
            #expect(InsightDiscoveryStore.newInsightIDs(in: [id], preferences: preferences).isEmpty)
            #expect(InsightDiscoveryStore.newNodeIDs(in: [nodeID], preferences: preferences).isEmpty)
            #expect(preferences.stringArray(forKey: "AquinasUndiscoveredInsightIDs") == [id.uuidString])
            #expect(preferences.stringArray(forKey: "AquinasPendingInsightPresentationIDs") == [other.uuidString])
            #expect(preferences.stringArray(forKey: "AquinasPendingNodePresentationIDs") == [])
        }
    }

    @Test("Legacy Insight history restores existing parents on the first visit after upgrading")
    func legacyNodeHistory() throws {
        try withPreferences { preferences in
            let old = UUID(), new = UUID(), oldNode = UUID(), newNode = UUID()
            preferences.set([old.uuidString], forKey: "AquinasSeenInsightIDs")
            #expect(InsightDiscoveryStore.newNodeIDs(
                in: [oldNode, newNode],
                memberInsightIDs: [oldNode: [old, new], newNode: [new]],
                preferences: preferences
            ) == [newNode])
        }
    }

    @Test("Viewing a card clears its dot and pending entrance without losing other trees' history")
    func discoveredInsightStaysDiscovered() throws {
        try withPreferences { preferences in
            let viewed = UUID(), other = UUID()
            InsightDiscoveryStore.markPresented(insightIDs: [other], preferences: preferences)
            preferences.set([viewed.uuidString, other.uuidString], forKey: "AquinasUndiscoveredInsightIDs")
            preferences.set([viewed.uuidString], forKey: "AquinasPendingInsightPresentationIDs")
            InsightDiscoveryStore.markDiscovered(viewed, preferences: preferences)
            InsightDiscoveryStore.markDiscovered(viewed, preferences: preferences)
            #expect(preferences.stringArray(forKey: "AquinasUndiscoveredInsightIDs") == [other.uuidString])
            #expect(preferences.stringArray(forKey: "AquinasPendingInsightPresentationIDs") == [])
            #expect(InsightDiscoveryStore.newInsightIDs(in: [viewed, other], preferences: preferences).isEmpty)
        }
    }
}
