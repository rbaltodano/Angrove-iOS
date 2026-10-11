import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Response read-aloud")
struct ResponseSpeechTests {
    @Test("Card speech indices include only visible context headings")
    @MainActor
    func cardSpeechIndices() {
        let definitions = [
            InsightDefinition(context: "ethics", meaning: "Justice gives each their due."),
            InsightDefinition(context: "", meaning: "A second meaning."),
            InsightDefinition(context: "political philosophy", meaning: "A third meaning.")
        ]
        let text = CardSpeech.text(for: definitions)
        let units = CardSpeech.units(for: text)
        #expect(CardSpeech.wordStart(for: 1, in: definitions) == 9)
        #expect(CardSpeech.wordStart(for: 2, in: definitions) == 12)
        #expect(units.flatMap(\.words).map(\.index) == Array(0..<20))
        #expect(CardSpeech.text(for: [definitions[0]]) == definitions[0].meaning)
        #expect(CardSpeech.units(for: "  \n ").isEmpty)
    }

    @Test("Clipped card speech matches its full passage")
    @MainActor
    func clippedCardSpeech() {
        let passage = ConceptDefinition(
            word: "Passage", partOfSpeech: "", pronunciation: "",
            meaning: "First line.\nSecond line.", example: "", isLibraryQuote: true
        )
        #expect(CardSpeech.text(for: passage) == passage.semanticDefinition)
        #expect(CardSpeech.units(for: CardSpeech.text(for: passage)).flatMap(\.words).map(\.token)
            == ["First", "line.", "Second", "line."])
    }

    @Test("Speech text drops markup and expands Summa abbreviations")
    func normalizesResponseText() {
        let sentences = SpeechTextNormalizer.sentences(in: """
        **Prudence** is {{right reason}} in action. St. Thomas cites q. 47, a. 2.
        - *Courage* follows.
        """)
        #expect(sentences == [
            "Prudence is right reason in action.",
            "Saint Thomas cites question 47, article 2.",
            "Courage follows.",
        ])
    }

    @Test("Curated pronunciations cover Aquinas and possessives")
    func curatedPronunciations() {
        #expect(SpeechPronunciations.phonemes(for: "Aquinas") == "əkwˈInəs")
        #expect(SpeechPronunciations.phonemes(for: "Aquinas’s") == "əkwˈInəsᵻz")
        #expect(SpeechPronunciations.phonemes(for: "Xyzzor") != nil)
    }

    @Test("Long phoneme strings split at spaces within the model limit")
    func splitsLongChunks() {
        let long = Array(repeating: "wˈʌn", count: 200).joined(separator: " ")
        let chunks = ParadeeSpeechEngine.split(long)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= ParadeeSpeechEngine.maxPhonemes && !$0.hasPrefix(" ") })
    }

    @Test("Paradee synthesizes audio from a response sentence")
    func synthesizesAudio() async throws {
        let engine = try ParadeeSpeechEngine()
        let chunks = await engine.sentences(for: "Aquinas teaches that justice renders to each one his due.").flatMap(\.chunks)
        #expect(chunks.count == 1)
        let samples = try await engine.synthesize(phonemes: chunks[0])
        let seconds = Double(samples.count) / ParadeeSpeechEngine.sampleRate
        #expect(seconds > 1.5 && seconds < 8)
        #expect(samples.contains { abs($0) > 0.05 })
    }
}
