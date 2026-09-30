import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Summa article evidence")
struct SummaArticleIndexTests {
    private static func passage(_ text: String, _ index: Int) -> LibraryPassage {
        LibraryPassage(
            text: text,
            title: "Summa Theologica",
            sourceId: SummaArticleIndex.sourceID,
            chunkIndex: index
        )
    }

    /// Two short articles chunked the way the bundled edition is: page headers as their own
    /// chunks, a header glued to the front of a continuation, and a word broken across lines.
    private static let corpus: [LibraryPassage] = [
        "Front matter of the edition.",
        "1521 Article. 5 - Whether the will is evil when it is at variance with erring…",
        "Whether the will is evil when it is at variance with erring reason? Objection 1: It would seem that the will is not evil when it is at variance with erring reason.",
        "Therefore the will is not evil. On the contrary, conscience is nothing else than the application of knowledge to some action. I answer that, Since conscience is a kind of dictate of the reason, to inquire whether the will is evil when it is at variance with erring reason, is the same as to inquire whether an erring conscience binds.",
        "1522 Article. 5 - Whether the will is evil when it is at variance with erring… Hence we must say that every will at variance with reason, whether right or erring, is always evil, in ac- cord with what was said. Reply to Objection 1: Although the judgment of an erring reason is not derived from God, yet it puts forward its judgment as being true.",
        "Whether the will is good when it abides by erring reason? Objection 1: It would seem that the will is good when it abides by erring reason.",
        "I answer that, this question depends on what has been said about ignorance: error arising from negligence does not excuse the will from evil. Reply to Objection 1: The argument fails."
    ].enumerated().map { passage($1, $0) }

    private var index: SummaArticleIndex {
        SummaArticleIndex(passages: Self.corpus, indices: Array(Self.corpus.indices))
    }

    @Test("Articles open at the question, and page headers belong to the article they head")
    func locatesArticles() {
        #expect(index.articleCount == 2)
        #expect(index.articleStart(containing: 0, in: Self.corpus) == nil)
        #expect(index.articleStart(containing: 1, in: Self.corpus) == 2)
        #expect(index.articleStart(containing: 3, in: Self.corpus) == 2)
        #expect(index.articleStart(containing: 4, in: Self.corpus) == 2)
        #expect(index.articleStart(containing: 6, in: Self.corpus) == 5)
    }

    @Test("Evidence is Aquinas's own answer, without objections, replies, or page furniture")
    func assemblesTheAnswer() throws {
        let evidence = try #require(
            index.evidence(forArticleAt: 2, in: Self.corpus, characterBudget: 1_300)
        )
        #expect(evidence.question == "Whether the will is evil when it is at variance with erring reason?")
        #expect(evidence.answer.hasPrefix("I answer that"))
        #expect(evidence.answer.contains("an erring conscience binds"))
        #expect(evidence.answer.contains("is always evil, in accord with what was said."))
        #expect(!evidence.answer.contains("Objection"))
        #expect(!evidence.answer.contains("Article. 5"))
        #expect(evidence.answerIndex == 3)
    }

    @Test("The next article is offered only when its question shares a subject")
    func offersTheQualifyingArticle() {
        #expect(index.relatedNextArticle(after: 2, in: Self.corpus) == 5)
        #expect(index.relatedNextArticle(after: 5, in: Self.corpus) == nil)

        let unrelated = [
            "Whether conscience be a power? Objection 1: It would seem that conscience is a power.",
            "I answer that, properly speaking, conscience is not a power, but an act of applying knowledge.",
            "Whether the appetite is a special power of the soul? Objection 1: It would seem not.",
            "I answer that, it is necessary to assign an appetitive power to the soul of an animal."
        ].enumerated().map { Self.passage($1, $0) }
        let other = SummaArticleIndex(passages: unrelated, indices: Array(unrelated.indices))
        #expect(other.relatedNextArticle(after: 0, in: unrelated) == nil)
    }

    @Test("An answer marker split across two chunks is still found")
    func findsAnAnswerSplitAcrossChunks() throws {
        let split = [
            "Whether prudence of the flesh is a sin? Objection 1: It would seem that it is not. On the contrary, it is an enemy to God. I",
            "answer that, prudence regards things which are directed to the end of the whole of life."
        ].enumerated().map { Self.passage($1, $0) }
        let splitIndex = SummaArticleIndex(passages: split, indices: Array(split.indices))
        let evidence = try #require(
            splitIndex.evidence(forArticleAt: 0, in: split, characterBudget: 1_300)
        )
        #expect(evidence.answer.hasPrefix("I answer that, prudence regards things"))
        #expect(evidence.answerIndex == 0)
    }

    @Test("A long answer keeps its opening and its conclusion")
    func shortensFromTheMiddle() {
        let answer = "I answer that, the opening distinction stands here. "
            + String(repeating: "A middle step of the argument follows. ", count: 60)
            + "Hence we must say the conclusion."
        let shortened = SummaArticleIndex.shortened(answer, to: 400)
        #expect(shortened.count <= 410)
        #expect(shortened.hasPrefix("I answer that, the opening distinction stands here."))
        #expect(shortened.hasSuffix("Hence we must say the conclusion."))
        #expect(shortened.contains("[…]"))
    }
}

/// What the real corpus delivers for questions whose evidence went wrong on the phone
/// (`Documentation/Gemma4-E4B-Quality-Triage.md`).
@Suite(
    "Summa evidence delivery",
    .enabled(if: BundledGroundingAssets.areAvailable, "LocalGrounding assets are not bundled")
)
struct SummaEvidenceDeliveryTests {
    static let developmentQuestions = [
        "What is prudence?",
        "What is natural law?",
        "What is a transcendental in scholastic philosophy?",
        "Explain the difference between substance and accident.",
        "According to Aquinas, must a person follow a conscience that is mistaken?",
        "What conditions does Aquinas require for a just war?",
        "Is gluttony only about eating too much?",
        "What does the Summa teach about whether law is something of reason?",
        "What does the Summa say about whether it is lawful to kill sinners?",
        "Is lying always wrong?",
        "In what year did Aquinas finish the Summa Theologiae?",
        "What is the Summa Theologiae?\n\nHow is each article structured?",
        "Who was Peter Lombard?\n\nDid Aquinas comment on his work?",
        "Can I trust my own reasoning about God?"
    ]

    @Test("Development dump of delivered evidence")
    func dumpsEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["AQUINAS_EVIDENCE_DUMP"] else { return }
        let provider = try MiniLMGroundingProvider()
        var dump = ""
        for question in Self.developmentQuestions {
            dump += "=== \(question)\n"
            for reference in provider.references(for: question, limit: 3) {
                dump += "--- \(reference.id) [chunk \(reference.chunkIndex.map(String.init) ?? "-")] \(reference.facts.count) chars\n\(reference.facts)\n"
            }
            dump += "\n"
        }
        try dump.write(toFile: path, atomically: true, encoding: .utf8)

        // Raw ranking, for judging recall separately from assembly.
        let bundle = Bundle.main
        func url(_ name: String, _ ext: String) throws -> URL {
            try #require(
                bundle.url(forResource: name, withExtension: ext, subdirectory: "LocalGrounding")
                    ?? bundle.url(forResource: name, withExtension: ext)
            )
        }
        let embedder = try MiniLMEmbedder(
            modelURL: url("MiniLM", "mlmodelc"),
            vocabURL: url("vocab", "txt")
        )
        let store = try OnDeviceGroundingStore(
            embeddingsURL: url("embeddings", "bin"),
            passagesURL: url("passages", "json")
        )
        var ranking = ""
        let probes = Self.developmentQuestions + (ProcessInfo.processInfo
            .environment["AQUINAS_EVIDENCE_PROBES"]?
            .split(separator: "|").map(String.init) ?? [])
        for question in probes {
            ranking += "=== \(question)\n"
            let passages = store.retrieve(
                queryEmbedding: try embedder.embed(question),
                k: 30,
                maxDistance: 0.7
            )
            for passage in passages {
                let head = passage.text.prefix(110).replacingOccurrences(of: "\n", with: " ")
                ranking += String(format: "%.3f", passage.distance)
                    + " \(passage.sourceID) [\(passage.chunkIndex ?? -1)] \(head)\n"
            }
        }
        try ranking.write(toFile: path + ".ranking", atomically: true, encoding: .utf8)
    }
}
