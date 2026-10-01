import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Response source citations")
struct ResponseCitationTests {
    private let justice = AngroveGroundingReference(
        id: "corpus-summa-theologica-0",
        title: "Summa Theologica",
        sourceName: "Summa Theologica",
        facts: "Justice is a habit whereby a man renders to each one his due by a constant and perpetual will. It is the virtue that orders a man in his relations with another.",
        retrievalAliases: [],
        sourceID: "summa-theologica",
        chunkIndex: 4200
    )

    private func citations(_ text: String, _ references: [AngroveGroundingReference]) -> [ResponseCitation] {
        ResponseCitationMatcher.citations(in: text, references: references) { sourceID, chunk in
            "\(sourceID) \(chunk)"
        }
    }

    @Test("A sentence reproducing a passage gets a chip before its final punctuation")
    func quotingSentenceIsCited() {
        let text = "Aquinas calls justice a habit whereby a man renders to each one his due by a constant will. That is the core idea."
        let found = citations(text, [justice])
        #expect(found.count == 1)
        let response = ModelResponse(text: text, citations: found)
        #expect(response.annotatedText.hasPrefix(
            "Aquinas calls justice a habit whereby a man renders to each one his due by a constant will [summa-theologica 4200](aq-cite://summa-theologica/4200). That"
        ))
    }

    @Test("Paraphrase and stock phrasing do not produce a chip")
    func paraphraseIsNotCited() {
        let text = "For Aquinas, justice means consistently giving people what they are owed."
        #expect(citations(text, [justice]).isEmpty)
    }

    @Test("A short span in quotation marks counts as quoting")
    func quotedSpanIsCited() {
        let text = "Justice is \u{201C}a constant and perpetual will\u{201D} toward others."
        #expect(citations(text, [justice]).count == 1)
    }

    @Test("A chip after a closing quotation sits outside the quotation")
    func chipFollowsClosingQuote() throws {
        let text = "He writes, \u{201C}It is the virtue that orders a man in his relations with another.\u{201D} Next."
        let citation = try #require(citations(text, [justice]).first)
        let annotated = ModelResponse(text: text, citations: [citation]).annotatedText
        #expect(annotated.contains("another.\u{201D} [summa-theologica 4200]"))
    }

    @Test("Consecutive sentences quoting one passage share a single chip")
    func consecutiveQuotesShareChip() {
        let text = "Justice is a habit whereby a man renders to each one his due. It is the virtue that orders a man in his relations with another."
        #expect(citations(text, [justice]).count == 1)
    }

    @Test("Curated notes without a corpus location are never cited")
    func curatedReferencesAreSkipped() {
        let curated = AngroveGroundingReference(
            id: "nicaea-325",
            title: "Council of Nicaea",
            sourceName: "Curated",
            facts: justice.facts,
            retrievalAliases: []
        )
        #expect(citations("Justice is a habit whereby a man renders to each one his due.", [curated]).isEmpty)
    }

    @Test("Citation markup is removed from plain text and parses back to its passage")
    func markupRoundTrips() throws {
        let citation = ResponseCitation(label: "John 14", sourceID: "web-bible", chunkIndex: 3762, insertionOffset: 0)
        let markup = ResponseCitationMarkup.markup(for: citation)
        #expect(InlineInsightMarkup.plainText(from: "Believe also in me \(markup).") == "Believe also in me.")
        let url = try #require(URL(string: "aq-cite://web-bible/3762"))
        let target = try #require(ResponseCitationMarkup.target(from: url))
        #expect(target.sourceID == "web-bible")
        #expect(target.chunkIndex == 3762)
    }

    @Test("Locators use the Library outline")
    func locatorLabels() {
        #expect(LibraryPassageLocator.label(sourceID: "web-bible", chunkIndex: 3762) == "John 14")
        #expect(LibraryPassageLocator.label(sourceID: "aristotle-nicomachean-ethics", chunkIndex: 170)
            == "Nicomachean Ethics, Book V")
    }
}
