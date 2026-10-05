//
//  FlaggedQuoteStore.swift
//  Angrove-iOS
//

import Foundation

/// A user message the local model judged to be an original synthesis worth resurfacing on Home.
struct FlaggedQuote: Codable, Equatable, Identifiable {
    let id: UUID
    let quoteText: String
    let reason: String?
    let flaggedAt: Date
    var surfacedAt: Date?
}

/// Per-conversation "Your Quote" candidates. Surfacing is idempotent within a day: the quote shown
/// today is shown again all day, and a quote is not shown again until `resurfaceCooldownDays`
/// have passed.
enum FlaggedQuoteStore {
    static let storageKey = "aquinas.home.flagged-quotes.v1"
    static let resurfaceCooldownDays = 14

    static func flag(
        _ quoteText: String,
        reason: String?,
        in conversationID: UUID,
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        let text = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var all = load(defaults: defaults)
        var quotes = all[conversationID.uuidString, default: []]
        guard !quotes.contains(where: { $0.quoteText == text }) else { return }
        quotes.append(FlaggedQuote(id: UUID(), quoteText: text, reason: reason, flaggedAt: date))
        all[conversationID.uuidString] = quotes
        save(all, defaults: defaults)
    }

    static func surfaceableQuote(
        for conversationID: UUID,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> FlaggedQuote? {
        var all = load(defaults: defaults)
        var quotes = all[conversationID.uuidString, default: []]
        if let today = quotes.first(where: { quote in
            guard let surfacedAt = quote.surfacedAt else { return false }
            return calendar.isDate(surfacedAt, inSameDayAs: now)
        }) {
            return today
        }
        guard let cooldownStart = calendar.date(
            byAdding: .day,
            value: -resurfaceCooldownDays,
            to: now
        ), let index = quotes.indices
            .filter({ index in
                guard let surfacedAt = quotes[index].surfacedAt else { return true }
                return surfacedAt <= cooldownStart
            })
            .min(by: { quotes[$0].flaggedAt < quotes[$1].flaggedAt }) else {
            return nil
        }
        quotes[index].surfacedAt = now
        all[conversationID.uuidString] = quotes
        save(all, defaults: defaults)
        return quotes[index]
    }

    static func removeConversation(_ conversationID: UUID, defaults: UserDefaults = .standard) {
        var all = load(defaults: defaults)
        all.removeValue(forKey: conversationID.uuidString)
        save(all, defaults: defaults)
    }

    private static func load(defaults: UserDefaults) -> [String: [FlaggedQuote]] {
        guard let data = PrivatePreferences(defaults: defaults).data(forKey: storageKey),
              let quotes = try? JSONDecoder().decode([String: [FlaggedQuote]].self, from: data) else {
            return [:]
        }
        return quotes
    }

    private static func save(_ quotes: [String: [FlaggedQuote]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(quotes) else { return }
        PrivatePreferences(defaults: defaults).set(data, forKey: storageKey)
    }
}
