import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Stable identities and tokenization")
struct SystemIdentityTests {
    @Test("Stable UUIDs keep the identifiers already persisted from their seeds")
    func stableUUIDMatchesFormattedDigest() {
        for seed in ["", "promoted:7D0C", "makenode-child:A:2", "global-insight-cluster:Grace", "ü✓"] {
            let bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
            let formatted = bytes.map { String(format: "%02x", $0) }.joined()
            let hex = Array(formatted)
            let uuidString = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
                .map { String(hex[$0]) }
                .joined(separator: "-")
            #expect(stableUUID(from: seed) == UUID(uuidString: uuidString))
        }
    }

    @Test("Words past the sequence length do not change an encoding")
    func tokenizerTruncatesLongText() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "vocab-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "grace", "nature", "##s", "."]
            .joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let tokenizer = try WordPieceTokenizer(vocabURL: url, maxLength: 6)

        let short = tokenizer.encode("Grace natures.")
        #expect(short.inputIDs == [2, 4, 5, 6, 7, 3])
        #expect(short.attentionMask == [1, 1, 1, 1, 1, 1])
        let long = tokenizer.encode("Grace natures. Grace nature unknown")
        #expect(long.inputIDs == short.inputIDs && long.attentionMask == short.attentionMask)
        #expect(tokenizer.encode("Zeal").inputIDs == [2, 1, 3, 0, 0, 0])
    }
}
