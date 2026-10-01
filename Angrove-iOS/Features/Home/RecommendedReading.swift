//
//  RecommendedReading.swift
//  Angrove-iOS
//

import Foundation

/// One library work that grounded answers, counted across every retrieval that cited it.
struct RecommendedWork: Codable, Equatable {
    let title: String
    /// The `sourceName` the Library uses to open this work.
    let sourceName: String
    let count: Int

    var reason: String {
        count == 1
            ? "Referenced in one of your recent answers."
            : "Referenced \(count) times across your conversations."
    }
}

/// Home's "Read Material" picks, built only from works the retrieval layer actually pulled.
/// The section stays hidden until three distinct works have grounded answers, then shows the
/// three most-pulled works as a snapshot that refreshes every few days rather than reshuffling
/// after every answer.
enum RecommendedReading {
    static let requiredWorkCount = 3
    static let refreshInterval: TimeInterval = 3 * 24 * 60 * 60

    private static let snapshotKey = "aquinas.home.recommendedReading.snapshot.v1"

    private struct Snapshot: Codable {
        let createdAt: Date
        let works: [RecommendedWork]
    }

    static func works(
        for conversations: [InquiryConversation],
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> [RecommendedWork] {
        works(
            from: conversations.flatMap { conversation in
                conversation.branches.flatMap { branch in
                    (branch.responsePresentations ?? []).flatMap { $0.groundingSources ?? [] }
                }
            },
            now: now,
            defaults: defaults
        )
    }

    static func works(
        from sources: [GroundingSourceSummary],
        now: Date,
        defaults: UserDefaults
    ) -> [RecommendedWork] {
        let ranked = rankedWorks(from: sources)
        guard ranked.count >= requiredWorkCount else { return [] }

        if let data = defaults.data(forKey: snapshotKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           snapshot.works.count == requiredWorkCount,
           now.timeIntervalSince(snapshot.createdAt) < refreshInterval {
            return snapshot.works
        }

        let picks = Array(ranked.prefix(requiredWorkCount))
        if let data = try? JSONEncoder().encode(Snapshot(createdAt: now, works: picks)) {
            defaults.set(data, forKey: snapshotKey)
        }
        return picks
    }

    /// Groups retrieved passages by the work they came from, most-pulled first. Passage IDs are
    /// per retrieval, so grouping by ID would list the same book once per passage. Only corpus
    /// passages (whose title is their work) count: curated grounding facts cite works such as
    /// the Catechism that the Library cannot open.
    static func rankedWorks(from sources: [GroundingSourceSummary]) -> [RecommendedWork] {
        var order: [String] = []
        var groups: [String: RecommendedWork] = [:]
        for source in sources where source.title == source.sourceName {
            let title = workTitle(for: source)
            let key = title.lowercased()
            guard !title.isEmpty else { continue }
            if let current = groups[key] {
                groups[key] = RecommendedWork(
                    title: current.title,
                    sourceName: current.sourceName,
                    count: current.count + 1
                )
            } else {
                order.append(key)
                groups[key] = RecommendedWork(title: title, sourceName: source.sourceName, count: 1)
            }
        }
        return order.compactMap { groups[$0] }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    /// Scripture citations are titled "John 14 — <work>"; the Library lists the work itself.
    private static func workTitle(for source: GroundingSourceSummary) -> String {
        var title = source.sourceName
        if let range = title.range(of: " — ", options: .backwards) {
            title = String(title[range.upperBound...])
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
