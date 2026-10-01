import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Defined term markup")
struct DefinedTermMarkupTests {
    private let response = """
    ## Virtue and habit

    For Aquinas, virtue is a [habit](aq://habit) that perfects a power. **Prudence**, \
    the soul’s guide, directs virtue toward its end.

    1. Justice gives each his due.
    - Virtue—the mean—is not mediocrity.
    """

    @Test("Displayed tokens match the words the response view renders")
    func displayedTokensMatchParser() {
        let source = response as NSString
        let displayed = DefinedTermMarkup.displayedTokenRanges(in: response).map(source.substring(with:))
        let rendered = ResponseParser.parseSegments(from: response)
            .filter { !$0.isInsight }
            .flatMap(\.words)

        #expect(displayed == rendered)
    }

    @Test("The pressed occurrence is annotated, not the first one")
    func annotatesPressedOccurrence() throws {
        let tokens = ResponseParser.parseSegments(from: response).flatMap(\.words)
        let second = try #require(tokens.lastIndex(of: "virtue"))

        let result = try #require(DefinedTermMarkup.defining(
            token: "virtue",
            at: .displayedToken(second),
            in: response
        ))

        #expect(result.term == "virtue")
        #expect(result.text.contains("directs [virtue](aq://virtue) toward"))
        #expect(result.text.contains("For Aquinas, virtue is a"))
    }

    @Test("Punctuation, emphasis, and a possessive stay outside the link")
    func keepsSurroundingMarkup() throws {
        let tokens = ResponseParser.parseSegments(from: response).flatMap(\.words)

        let prudenceIndex = try #require(tokens.firstIndex(of: "**Prudence**,"))
        let prudence = try #require(DefinedTermMarkup.defining(
            token: "**Prudence**,",
            at: .displayedToken(prudenceIndex),
            in: response
        ))
        #expect(prudence.term == "Prudence")
        #expect(prudence.text.contains("**[Prudence](aq://prudence)**, the"))

        let soulIndex = try #require(tokens.firstIndex(of: "soul’s"))
        let soul = try #require(DefinedTermMarkup.defining(
            token: "soul’s",
            at: .displayedToken(soulIndex),
            in: response
        ))
        #expect(soul.term == "soul")
        #expect(soul.text.contains("[soul](aq://soul)’s guide"))
    }

    @Test("An annotated word renders as one Insight link token")
    func annotatedWordParsesAsLink() throws {
        let result = try #require(DefinedTermMarkup.defining(
            token: "Justice",
            at: .sourceToken(source: "Justice gives each his due.", index: 0),
            in: response
        ))
        let link = ResponseParser.parseSegments(from: result.text)
            .flatMap(\.words)
            .compactMap(ParsedInsightLink.init(token:))
            .first { $0.title == "Justice" }

        #expect(link?.url.absoluteString == "aq://justice")
        // Only the link markup was added, so the definition context the model sees is unchanged.
        #expect(
            ResponseTextFormatting.definitionContext(from: result.text)
                == ResponseTextFormatting.definitionContext(from: response)
        )
    }

    @Test("A stale location falls back to the first matching word")
    func staleLocationFallsBack() throws {
        let result = try #require(DefinedTermMarkup.defining(
            token: "mediocrity.",
            at: .sourceToken(source: "text that is no longer in the response", index: 3),
            in: response
        ))
        #expect(result.text.hasSuffix("is not [mediocrity](aq://mediocrity)."))
    }

    @Test("Terms come from words only")
    func termExtraction() {
        #expect(DefinedTermMarkup.term(in: "(prudence),") == "prudence")
        #expect(DefinedTermMarkup.term(in: "Virtue—the") == "Virtue")
        #expect(DefinedTermMarkup.term(in: "**actus purus**.") == "actus purus")
        #expect(DefinedTermMarkup.term(in: "—") == nil)
        #expect(DefinedTermMarkup.term(in: "1.") == nil)
        #expect(DefinedTermMarkup.term(in: "[habit](aq://habit)") == nil)
    }
}
