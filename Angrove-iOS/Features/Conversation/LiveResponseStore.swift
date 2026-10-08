//
//  LiveResponseStore.swift
//  Angrove-iOS
//

import Foundation
import Observation

/// In-flight presentation state for responses that are still generating.
///
/// The thread view is remounted when the user navigates away and back, which discards its
/// `@State`. Generation keeps running on the shared queue, so this process-scoped store lets a
/// remounted thread resume the same thinking, sources, and entrance animation instead of
/// showing a bare placeholder and snapping the answer in.
@MainActor
@Observable
final class LiveResponseStore {
    static let shared = LiveResponseStore()

    struct Key: Hashable {
        let branchID: UUID
        let responseIndex: Int

        /// Scopes per-source memory (such as "already revealed") to one response.
        func sourceKey(_ sourceID: String) -> String {
            "\(branchID)-\(responseIndex)-\(sourceID)"
        }
    }

    struct Entry {
        var showsThinking: Bool?
        var thinkingSummary: [String]?
        var liveThought: String?
        var groundingSources: [GroundingSourceSummary]?
        var isReceivingStream = false
        /// The answer should play its entrance when it lands, even in a remounted thread.
        var isAnimating = false
        /// When generation was submitted, so a remounted card resumes its elapsed timer.
        var startedAt = Date()
    }

    private(set) var entries: [Key: Entry] = [:]
    /// Sources whose entrance already played; they never replay on later viewport entries.
    private(set) var revealedSourceKeys: Set<String> = []

    func begin(_ key: Key, showsThinking: Bool) {
        revealedSourceKeys = revealedSourceKeys.filter { !$0.hasPrefix("\(key.branchID)-\(key.responseIndex)-") }
        entries[key] = Entry(showsThinking: showsThinking, isAnimating: true)
    }

    func update(_ key: Key, _ change: (inout Entry) -> Void) {
        guard var entry = entries[key] else { return }
        change(&entry)
        entries[key] = entry
    }

    /// Generation is over: drop the live fields but keep `isAnimating` until the reveal ends.
    func finishGeneration(_ key: Key) {
        update(key) {
            $0.thinkingSummary = nil
            $0.liveThought = nil
            $0.groundingSources = nil
            $0.isReceivingStream = false
        }
    }

    func clear(_ key: Key) {
        entries.removeValue(forKey: key)
    }

    func markSourceRevealed(_ sourceKey: String) {
        revealedSourceKeys.insert(sourceKey)
    }
}
