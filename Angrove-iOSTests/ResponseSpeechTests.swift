import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Response read-aloud")
struct ResponseSpeechTests {
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
        let chunks = await engine.phonemeChunks(for: "Aquinas teaches that justice renders to each one his due.")
        #expect(chunks.count == 1)
        let samples = try await engine.synthesize(phonemes: chunks[0])
        let seconds = Double(samples.count) / ParadeeSpeechEngine.sampleRate
        #expect(seconds > 1.5 && seconds < 8)
        #expect(samples.contains { abs($0) > 0.05 })
    }
}
