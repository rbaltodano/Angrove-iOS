import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Home discovery cards")
struct HomeDiscoveryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func freshDefaults() -> UserDefaults {
        let name = "HomeDiscoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func concept(_ word: String) -> ConceptDefinition {
        ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: word),
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: "\(word) in this conversation.",
            example: ""
        )
    }

    private func seed(_ label: String, _ embedding: [Double], ageDays: Double) -> LocalInsightTreeSeed {
        LocalInsightTreeSeed(
            id: UUID(),
            label: label,
            summary: "",
            embedding: embedding,
            embeddingVersion: "test",
            createdAt: now.addingTimeInterval(-ageDays * 86_400)
        )
    }

    // MARK: Today in History

    @Test("Today in History returns the curated entry for its date and nothing otherwise")
    func todayInHistoryUsesCuratedCatalog() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let aquinasDeath = calendar.date(from: DateComponents(year: 2027, month: 3, day: 7))!
        let uncovered = calendar.date(from: DateComponents(year: 2027, month: 1, day: 2))!

        #expect(
            TodayInHistoryCatalog.entry(for: aquinasDeath, calendar: calendar)?.title
                == "Death of Thomas Aquinas"
        )
        #expect(TodayInHistoryCatalog.entry(for: uncovered, calendar: calendar) == nil)
        #expect(Set(TodayInHistoryCatalog.entries.map(\.date)).count == TodayInHistoryCatalog.entries.count)
    }

    // MARK: Terms You Glossed Over

    @Test("Glossed term picks the oldest stale lookup that was never saved")
    func glossedTermSelection() {
        let saved = concept("Grace")
        let stale = concept("Prudence")
        let older = concept("Virtue")
        let fresh = concept("Justice")
        let records = [
            GlossedTermRecord(definition: saved, requestedTerm: "grace", lookedUpAt: now.addingTimeInterval(-5 * 86_400)),
            GlossedTermRecord(definition: stale, requestedTerm: "prudence", lookedUpAt: now.addingTimeInterval(-2 * 86_400)),
            GlossedTermRecord(definition: older, requestedTerm: "virtue", lookedUpAt: now.addingTimeInterval(-3 * 86_400)),
            GlossedTermRecord(definition: fresh, requestedTerm: "justice", lookedUpAt: now.addingTimeInterval(-3_600)),
        ]

        let card = HomeDiscovery.glossedTerm(in: records, savedInsightIDs: [saved.id], now: now)

        #expect(card?.concept == older)
        #expect(HomeDiscovery.glossedTerm(in: [records[3]], savedInsightIDs: [], now: now) == nil)
    }

    @Test("A repeated lookup keeps the first lookup time")
    func glossedTermKeepsFirstLookup() {
        let defaults = freshDefaults()
        let conversationID = UUID()
        let term = concept("Prudence")

        GlossedTermStore.recordLookup(term, requestedTerm: "prudence", in: conversationID, at: now.addingTimeInterval(-86_400), defaults: defaults)
        GlossedTermStore.recordLookup(term, requestedTerm: "prudence", in: conversationID, at: now, defaults: defaults)

        let records = GlossedTermStore.records(for: conversationID, defaults: defaults)
        #expect(records.count == 1)
        #expect(records.first?.lookedUpAt == now.addingTimeInterval(-86_400))
    }

    // MARK: Your Quote

    @Test("Quote pre-filter rejects questions, short replies, and filler")
    func quoteCandidateFilter() {
        #expect(HomeDiscovery.isQuoteCandidate(
            "Mercy perfects justice rather than suspending it, because it gives more than is owed."
        ))
        #expect(!HomeDiscovery.isQuoteCandidate("Does mercy suspend justice, or does it perfect it somehow?"))
        #expect(!HomeDiscovery.isQuoteCandidate("Thanks, that makes sense."))
    }

    @Test("Quote surfacing is stable within a day and respects the cooldown")
    func quoteSurfacingCooldown() {
        let defaults = freshDefaults()
        let conversationID = UUID()
        FlaggedQuoteStore.flag("First synthesis about mercy and justice.", reason: nil, in: conversationID, at: now, defaults: defaults)
        FlaggedQuoteStore.flag("Second synthesis about grace and nature.", reason: nil, in: conversationID, at: now.addingTimeInterval(60), defaults: defaults)

        let first = FlaggedQuoteStore.surfaceableQuote(for: conversationID, now: now, defaults: defaults)
        let sameDay = FlaggedQuoteStore.surfaceableQuote(for: conversationID, now: now.addingTimeInterval(3_600), defaults: defaults)
        let nextDay = FlaggedQuoteStore.surfaceableQuote(for: conversationID, now: now.addingTimeInterval(86_400), defaults: defaults)
        let dayAfter = FlaggedQuoteStore.surfaceableQuote(for: conversationID, now: now.addingTimeInterval(2 * 86_400), defaults: defaults)

        #expect(first?.quoteText == "First synthesis about mercy and justice.")
        #expect(sameDay?.id == first?.id)
        #expect(nextDay?.quoteText == "Second synthesis about grace and nature.")
        #expect(dayAfter == nil)
    }

    // MARK: Loose Thread

    @Test("Loose thread is a Node Concept with no strong connection, preferring more Insights")
    func looseThreadSelection() {
        let conversationID = UUID()
        let grace = seed("Grace", [1, 0, 0], ageDays: 3)
        let nature = seed("Nature", [0.95, 0.31, 0], ageDays: 2)
        let usury = seed("Usury", [0, 0, 1], ageDays: 1)
        let music = seed("Music", [0, 1, 0], ageDays: 4)

        let card = HomeDiscovery.looseThread(
            conversationID: conversationID,
            seeds: [grace, nature, usury, music],
            insightEmbeddings: [[0, 0.1, 1], [0, 0, 1]]
        )

        #expect(card?.nodeID == usury.id)
        #expect(card?.insightCount == 2)
        #expect(card?.conversationID == conversationID)
    }

    @Test("Loose thread needs at least two Node Concepts and ties prefer the oldest")
    func looseThreadEdgeCases() {
        let only = seed("Grace", [1, 0, 0], ageDays: 1)
        #expect(HomeDiscovery.looseThread(conversationID: UUID(), seeds: [only], insightEmbeddings: []) == nil)

        let newer = seed("Usury", [0, 0, 1], ageDays: 1)
        let older = seed("Music", [0, 1, 0], ageDays: 5)
        let card = HomeDiscovery.looseThread(
            conversationID: UUID(),
            seeds: [newer, older],
            insightEmbeddings: []
        )
        #expect(card?.nodeID == older.id)
    }
}
