import Testing
@testable import Angrove_iOS

/// Curated notes are merged ahead of semantic search with no relevance floor, so an alias that
/// matches by accident puts an unrelated note into the prompt and the Thinking sources.
struct CuratedGroundingAliasTests {
    @Test("An alias inside another word does not match")
    func aliasInsideWordDoesNotMatch() {
        // Seen on device: "nica" in "technical" attached the First Council of Nicaea to this.
        let sputnik = "How did the shift from Sputnik 1's technical proof of concept to "
            + "Sputnik 2's biological test alter the public perception of the space race?"
        #expect(LocalAngroveGroundingProvider.aliasMatchedReferences(for: sputnik, limit: 3).isEmpty)
        #expect(LocalAngroveGroundingProvider().references(for: sputnik, limit: 3)
            .allSatisfy { $0.id != "nicaea-325" })

        let librarian = "What does a librarian do?"
        #expect(LocalAngroveGroundingProvider.aliasMatchedReferences(for: librarian, limit: 3).isEmpty)
    }

    @Test("Aliases still match whole words and their inflections")
    func aliasStillMatchesAtWordStart() {
        let ids = { (question: String) in
            LocalAngroveGroundingProvider.aliasMatchedReferences(for: question, limit: 3).map(\.id)
        }
        #expect(ids("What did the Council of Nicaea decide?").contains("nicaea-325"))
        #expect(ids("What was Arianism?").contains("nicaea-325"))
        #expect(ids("Nicaea: what happened there?").contains("nicaea-325"))
    }
}
