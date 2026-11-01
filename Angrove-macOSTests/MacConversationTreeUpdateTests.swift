import Testing
@testable import AngroveMac

@MainActor
struct MacConversationTreeUpdateTests {
    @Test func openingConversationEstablishesBaselineWithoutAnUpdate() throws {
        let session = MacConversationState()
        session.configure(preview: true)

        #expect(!session.concepts.isEmpty)
        #expect(session.insightUpdateCount == 0)

        // A repeated appearance must not restore or announce the same content again.
        session.configure(preview: true)
        #expect(session.insightUpdateCount == 0)
    }

    @Test func onlyContentChangesAfterOpeningCountAsUpdates() throws {
        let session = MacConversationState()
        session.configure(preview: true)
        let original = session.concepts
        let concept = try #require(original.first)

        session.concepts = original
        #expect(session.insightUpdateCount == 0)

        session.remove(concept)
        #expect(session.insightUpdateCount == 1)

        session.restore(concept)
        #expect(session.insightUpdateCount == 2)

        session.restore(concept)
        #expect(session.insightUpdateCount == 2)
    }
}
