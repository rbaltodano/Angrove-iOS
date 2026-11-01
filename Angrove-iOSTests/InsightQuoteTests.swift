import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Quoting Insights")
struct InsightQuoteTests {
    private func insight(_ word: String) -> ConceptDefinition {
        ConceptDefinition(word: word, partOfSpeech: "", pronunciation: "", meaning: "\(word) meaning", example: "")
    }

    @Test("# starts a mention only at the start of a word")
    func activeQuery() {
        #expect(InsightMention.activeQuery(in: "How does #pru") == "pru")
        #expect(InsightMention.activeQuery(in: "#") == "")
        #expect(InsightMention.activeQuery(in: "Learning C#") == nil)
        #expect(InsightMention.activeQuery(in: "# heading") == nil)
        #expect(InsightMention.activeQuery(in: "#prudence\nand") == nil)
    }

    @Test("Suggestions put title prefixes first and skip quoted Insights")
    func suggestions() {
        let prudence = insight("Prudence")
        let candidates = [insight("Jurisprudence"), prudence, insight("Justice"), insight("prudence")]
        let names = InsightMention.suggestions(for: "pru", from: candidates).map(\.word)
        #expect(names == ["Prudence", "Jurisprudence"])
        #expect(InsightMention.suggestions(for: "pru", from: candidates, excluding: [prudence.id]).map(\.word)
            == ["Jurisprudence"])
    }

    @Test("Complete #titles are recognized anywhere, preferring the longest title")
    func mentions() {
        let candidates = [insight("Law"), insight("Law of nature"), insight("Prudence")]
        let text = "Does #prudence follow the #law of nature, or #pru"
        let found = InsightMention.mentions(in: text, candidates: candidates)
        #expect(found.map(\.concept.word) == ["Prudence", "Law of nature"])
        #expect((text as NSString).substring(with: found[0].range) == "#prudence")
        // At the end of the draft, "#law" waits while "Law of nature" is still possible.
        #expect(InsightMention.mentions(in: "Explain #law", candidates: candidates).isEmpty)
        #expect(InsightMention.mentions(in: "Explain #law ", candidates: candidates).map(\.concept.word) == ["Law"])
        #expect(InsightMention.mentions(in: "Explain #prudence", candidates: candidates).count == 1)
        #expect(InsightMention.mentions(in: "Learning C#prudence", candidates: candidates).isEmpty)
    }

    @Test("Sending keeps a mention's words and drops its #")
    func resolving() {
        let candidates = [insight("Prudence"), insight("Justice")]
        let text = "How does #prudence relate to #justice?"
        let found = InsightMention.mentions(in: text, candidates: candidates)
        #expect(InsightMention.resolving(found, in: text) == "How does prudence relate to justice?")
    }

    @Test("Choosing from the menu completes the typed #title")
    func completion() {
        #expect(InsightMention.completingActiveQuery(in: "Explain #pru", with: insight("Prudence"))
            == "Explain #Prudence ")
        #expect(InsightMention.completingActiveQuery(in: "#", with: insight("Justice")) == "#Justice ")
    }

    @Test("A question quotes up to five distinct Insights")
    func quoteLimit() {
        var branch = ChatBranch(startingConcept: nil)
        let first = insight("One")
        branch.attachQuote(first)
        branch.attachQuote(first)
        #expect(branch.branchContextConcepts == [first])
        for word in ["Two", "Three", "Four", "Five", "Six"] { branch.attachQuote(insight(word)) }
        #expect(branch.branchContextConcepts.map(\.word) == ["One", "Two", "Three", "Four", "Five"])
        #expect(!branch.canQuoteAnotherInsight)
    }

    @Test("Several quotes round-trip, and the first stays readable by earlier builds")
    func storageCompatibility() throws {
        let quotes = [insight("Prudence"), insight("Justice")]
        var branch = ChatBranch(startingConcept: nil)
        branch.attachedConcepts = quotes
        branch.activeChatBlocks = [.user("How do these relate?", quotes, [])]
        let data = try JSONEncoder().encode(branch)

        let decoded = try JSONDecoder().decode(ChatBranch.self, from: data)
        #expect(decoded.attachedConcepts == quotes)
        #expect(decoded.activeChatBlocks == branch.activeChatBlocks)

        // Earlier builds read one optional quote from these keys.
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attached = try #require(json["attachedConcept"] as? [String: Any])
        #expect(attached["word"] as? String == "Prudence")
        let blocks = try #require(json["activeChatBlocks"] as? [[String: Any]])
        let user = try #require(blocks.first?["user"] as? [String: Any])
        #expect((user["_1"] as? [String: Any])?["word"] as? String == "Prudence")
    }

    @Test("Questions saved with one quote still decode")
    func legacyDecoding() throws {
        let concept = insight("Prudence")
        let conceptJSON = String(decoding: try JSONEncoder().encode(concept), as: UTF8.self)
        let legacy = #"{"user":{"_0":"Why?","_1":\#(conceptJSON),"_2":[]}}"#
        let block = try JSONDecoder().decode(ChatBlock.self, from: Data(legacy.utf8))
        #expect(block == .user("Why?", [concept], []))
        let unquoted = try JSONDecoder().decode(ChatBlock.self, from: Data(#"{"user":{"_0":"Why?","_2":[]}}"#.utf8))
        #expect(unquoted == .user("Why?", [], []))
    }

    @Test("Each quoted Insight precedes the question in model markup")
    func promptMarkup() {
        let prompt = ConversationPromptMarkup.userPrompt(
            question: "How do these relate?",
            quotedInsights: [insight("Prudence"), insight("Justice")]
        )
        #expect(prompt.components(separatedBy: "<insight_quote>").count == 3)
        #expect(prompt.hasSuffix("User question:\nHow do these relate?"))
    }
}
