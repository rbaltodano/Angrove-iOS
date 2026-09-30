//
//  AquinasGrounding.swift
//  Aquinas-iOS
//

import Foundation

/// A short, trusted reference passage supplied to Aquinas before generation. The language model
/// may explain these facts, but it must not replace or contradict them.
nonisolated struct AquinasGroundingReference: Sendable, Equatable {
    let id: String
    let title: String
    let sourceName: String
    let facts: String
    let retrievalAliases: [String]
    /// Set for corpus passages (not curated notes), locating the passage for inline citations.
    var sourceID: String? = nil
    var chunkIndex: Int? = nil

    var promptText: String {
        "[\(title) — \(sourceName)]\n\(facts)"
    }
}

/// Retrieval boundary for factual grounding. The first implementation uses a tiny local lexical
/// index so the contract works offline today. A MiniLM-backed provider can replace its ranking
/// implementation later without changing conversation generation or UI code.
nonisolated protocol AquinasGroundingProviding: Sendable {
    func references(
        for question: String,
        limit: Int
    ) -> [AquinasGroundingReference]
}

nonisolated struct LocalAquinasGroundingProvider: AquinasGroundingProviding {
    /// State only what is true. A `facts` string must never name the thing it is trying to rule
    /// out, because the model reads that name as the subject rather than as the exclusion.
    ///
    /// Confirmed on a physical iPhone: the `john-14` note used to end "This is a different passage
    /// from John 4, the account of Jesus and the Samaritan woman at the well." Asked "what does
    /// John 14 say", retrieval was correct — Show Thinking listed both the curated note and the
    /// real `John 14 — World English Bible` chapter text — and the model answered with an entire
    /// essay on John 4 and the woman at the well, inventing a "John 4:231" citation to support it.
    /// The sentence written to prevent that confusion produced it.
    ///
    /// Disambiguation belongs in `retrievalAliases`, which steer retrieval without entering the
    /// prompt. Several entries below still carry contrastive clauses ("It was not called the
    /// Council of Adhesion", "It must not be confused with Nicaea in 325", "It is not known to have
    /// been written by the Apostle Paul") and are the same hazard; they are kept for now only
    /// because they predate this finding and have not been individually re-tested on device.
    private static let references: [AquinasGroundingReference] = [
        AquinasGroundingReference(
            id: "nicaea-325",
            title: "First Council of Nicaea (325)",
            sourceName: "Catechism of the Catholic Church §242",
            facts: "The first ecumenical council met at Nicaea in 325. It addressed the Arian controversy and confessed that the Son is consubstantial (homoousios) with the Father. Nicaea is the historical English spelling; modern İznik is the city at that site.",
            retrievalAliases: [
                "first ecumenical council", "council of nicaea", "council of nicea",
                "nicaea", "nicea", "nica", "nicene creed", "homoousios", "arian"
            ]
        ),
        AquinasGroundingReference(
            id: "constantinople-381",
            title: "First Council of Constantinople (381)",
            sourceName: "Catechism of the Catholic Church §245",
            facts: "The First Council of Constantinople met in 381 and is counted as the second ecumenical council. It reaffirmed the faith of Nicaea and confessed the divinity of the Holy Spirit, contributing to the Nicene-Constantinopolitan Creed. It was not called the Council of Adhesion and it was not the council that settled the veneration of icons.",
            retrievalAliases: [
                "second ecumenical council", "first council of constantinople",
                "council of constantinople", "constantinople", "council of adhesion",
                "holy spirit", "nicene constantinopolitan creed"
            ]
        ),
        AquinasGroundingReference(
            id: "nicaea-787",
            title: "Second Council of Nicaea (787)",
            sourceName: "Catechism of the Catholic Church §2131",
            facts: "The Second Council of Nicaea met in 787 and is counted as the seventh ecumenical council. It defended the veneration of sacred images against iconoclasm. It must not be confused with Nicaea in 325 or Constantinople in 381.",
            retrievalAliases: [
                "second council of nicaea", "nicaea ii", "seventh ecumenical council",
                "icons", "icon veneration", "iconoclasm"
            ]
        ),
        AquinasGroundingReference(
            id: "didache-authorship",
            title: "The Didache",
            sourceName: "Aquinas curated reference note",
            facts: "The Didache, also called the Teaching of the Twelve Apostles, is an anonymous early Christian church-order and teaching text. Its author is unknown. It is not known to have been written by the Apostle Paul.",
            retrievalAliases: [
                "didache", "teaching of the twelve apostles", "written by paul",
                "apostle paul", "didache authorship"
            ]
        ),
        // A small stopgap for extremely well-known, doctrinally-central chapters, not an attempt
        // at Bible-wide coverage — full Scripture retrieval remains a separate on-device RAG
        // roadmap item.
        AquinasGroundingReference(
            id: "john-14",
            title: "Gospel of John, Chapter 14",
            sourceName: "Aquinas curated reference note",
            facts: "John 14 is part of Jesus's Farewell Discourse to his disciples at the Last Supper, the night before his crucifixion. It opens with Jesus telling the disciples not to let their hearts be troubled, and to trust in God and in him. In response to Thomas's question about the way, Jesus says he is the way, the truth, and the life, and that no one comes to the Father except through him. Jesus promises to send the Holy Spirit, called the Advocate (or Helper), to be with the disciples after he is gone, and to teach them and remind them of all he has said.",
            retrievalAliases: [
                "john 14", "john chapter 14", "gospel of john 14", "farewell discourse",
                "way the truth and the life", "let not your hearts be troubled"
            ]
        ),
        AquinasGroundingReference(
            id: "john-3",
            title: "Gospel of John, Chapter 3",
            sourceName: "Aquinas curated reference note",
            facts: "John 3 recounts Jesus's night conversation with Nicodemus, a Pharisee and member of the Jewish ruling council, about being born again (or born from above) of water and the Spirit in order to enter the kingdom of God. The chapter contains the statement that God so loved the world that he gave his only Son, so that whoever believes in him should not perish but have eternal life.",
            retrievalAliases: [
                "john 3", "john chapter 3", "gospel of john 3", "nicodemus",
                "born again", "god so loved the world"
            ]
        ),
        AquinasGroundingReference(
            id: "matthew-5",
            title: "Gospel of Matthew, Chapter 5",
            sourceName: "Aquinas curated reference note",
            facts: "Matthew 5 opens the Sermon on the Mount, Jesus's extended teaching to his disciples and the crowds. It begins with the Beatitudes, a series of blessings on the poor in spirit, those who mourn, the meek, and others, and goes on to describe the disciples as salt of the earth and light of the world, and to deepen several commands of the Mosaic law (on anger, adultery, oaths, and retaliation) beyond their external observance.",
            retrievalAliases: [
                "matthew 5", "matthew chapter 5", "sermon on the mount", "beatitudes",
                "salt of the earth", "light of the world"
            ]
        ),
        AquinasGroundingReference(
            id: "romans-8",
            title: "Letter to the Romans, Chapter 8",
            sourceName: "Aquinas curated reference note",
            facts: "Romans 8 is Paul's teaching on life in the Spirit. It opens with the statement that there is now no condemnation for those who are in Christ Jesus, describes the Spirit as testifying with believers that they are children of God, and closes with the assurance that nothing in creation can separate believers from the love of God in Christ Jesus.",
            retrievalAliases: [
                "romans 8", "romans chapter 8", "no condemnation", "life in the spirit",
                "more than conquerors"
            ]
        ),
        AquinasGroundingReference(
            id: "1-corinthians-13",
            title: "First Letter to the Corinthians, Chapter 13",
            sourceName: "Aquinas curated reference note",
            facts: "1 Corinthians 13 is Paul's teaching on love (agape), often called the \"love chapter.\" It states that without love, even great gifts and knowledge are worthless, describes love as patient and kind, and concludes that faith, hope, and love remain, with love as the greatest of the three.",
            retrievalAliases: [
                "1 corinthians 13", "first corinthians 13", "corinthians chapter 13",
                "love chapter", "love is patient"
            ]
        ),
        AquinasGroundingReference(
            id: "psalm-23",
            title: "Psalm 23",
            sourceName: "Aquinas curated reference note",
            facts: "Psalm 23 is a psalm of David describing the Lord as a shepherd who provides, guides, and protects. It includes the images of green pastures, still waters, and walking through the valley of the shadow of death without fear, and closes with the psalmist's confidence in dwelling in the house of the Lord forever.",
            retrievalAliases: [
                "psalm 23", "the lord is my shepherd", "valley of the shadow of death",
                "green pastures"
            ]
        ),
        // Facts about Aquinas's works and scholastic vocabulary that the bundled sources do not
        // state about themselves. Without them the app either abstained ("In what year did
        // Aquinas finish the Summa?") or the model answered from memory and got the order of an
        // article, or the sense of "transcendental", wrong. Aliases are specific phrases: a bare
        // "summa" would attach these to every question about the Summa's teaching.
        AquinasGroundingReference(
            id: "summa-theologiae-composition",
            title: "The Summa Theologiae: composition",
            sourceName: "Aquinas curated reference note",
            facts: "Thomas Aquinas wrote the Summa Theologiae between about 1265 and 1273. The work is unfinished. He stopped writing in December 1273, partway through the Third Part's treatment of the sacrament of penance, and died in March 1274. His followers compiled a Supplement from his earlier Commentary on the Sentences to complete the plan. The Summa has three parts, the second divided in two; each part is divided into questions, and each question into articles.",
            retrievalAliases: [
                "finish the summa", "finished the summa", "complete the summa",
                "completed the summa", "completion of the summa", "summa unfinished",
                "finish writing the summa", "stop writing the summa", "stopped writing the summa",
                "when was the summa written", "write the summa", "wrote the summa",
                "what is the summa", "parts of the summa"
            ]
        ),
        AquinasGroundingReference(
            id: "summa-article-structure",
            title: "The structure of an article in the Summa Theologiae",
            sourceName: "Aquinas curated reference note",
            facts: "Every article of the Summa Theologiae follows the same order. First, a question beginning \"Whether\". Second, the objections: arguments against the conclusion Aquinas will reach, each introduced \"It would seem that\". Third, \"On the contrary\" (sed contra), which cites an authority against the objections. Fourth, Aquinas's own answer in the body of the article, beginning \"I answer that\" (respondeo). Fifth, a reply to each objection in turn.",
            retrievalAliases: [
                "article structured", "articles structured", "structure of an article",
                "structure of each article", "structure of the articles", "structure of the summa",
                "sed contra", "respondeo", "objections and replies"
            ]
        ),
        AquinasGroundingReference(
            id: "aquinas-commentary-on-the-sentences",
            title: "Peter Lombard's Sentences and Aquinas's commentary",
            sourceName: "Aquinas curated reference note",
            facts: "Peter Lombard (c. 1096–1160), bishop of Paris, compiled the Four Books of Sentences around 1150. It became the standard theology textbook of the medieval universities. Thomas Aquinas wrote a commentary on it, the Scriptum super libros Sententiarum (Commentary on the Sentences), from his lectures at Paris in about 1252–1256. It was his first major work: commenting on the Sentences was the normal requirement for becoming a master of theology.",
            retrievalAliases: [
                "peter lombard", "lombard's sentences", "sentences of peter lombard",
                "commentary on the sentences", "book of sentences", "books of sentences"
            ]
        ),
        // The primary text reaches the model too (I–II q.19 a.5–6, via a subject route), but
        // Aquinas's answer there opens with a view he rejects and speaks of "erring reason" and
        // "the will". Given only that, the model answered about when error excuses and never
        // said that conscience binds, or reversed it outright (held-B1).
        AquinasGroundingReference(
            id: "erring-conscience",
            title: "Aquinas on a mistaken conscience",
            sourceName: "Aquinas curated reference note",
            facts: "Aquinas treats a mistaken conscience in Summa Theologiae I–II, question 19, articles 5 and 6, and his answer has two parts. First, conscience binds even when it is mistaken: a person who acts against what their reason judges to be right does wrong, whether that judgment is correct or in error, because they choose what they take to be evil. Second, following a mistaken conscience is not thereby good. If the mistake comes from ignorance the person is responsible for, such as negligence or ignorance of the divine law they are bound to know, the act is still wrong. If it comes from blameless ignorance of a circumstance, the person is excused. So the duty is both to follow conscience and to form it well.",
            retrievalAliases: [
                "mistaken conscience", "erring conscience", "erroneous conscience",
                "conscience that is mistaken", "conscience is mistaken", "conscience that is wrong",
                "conscience is wrong", "conscience errs", "conscience that errs",
                "conscience be wrong", "conscience be mistaken", "wrong conscience",
                "conscience bind", "conscience binds"
            ]
        ),
        AquinasGroundingReference(
            id: "substance-and-accident",
            title: "Substance and accident",
            sourceName: "Aquinas curated reference note",
            facts: "In Aristotle and the scholastics, a substance is what exists in itself and not in another as in a subject: this man, this horse, this tree. An accident is what exists only in a substance, as a feature of it: its color, size, shape, position, or activity. The difference is one of dependence. A substance has being in its own right and underlies change; an accident has being only by inhering in a substance, and can come or go while the substance remains the same thing. Aristotle lists nine kinds of accident, including quantity, quality, and relation.",
            retrievalAliases: [
                "substance and accident", "accident and substance", "substance and accidents",
                "accidents and substance", "substance from accident", "substance versus accident",
                "substance vs accident"
            ]
        ),
        AquinasGroundingReference(
            id: "scholastic-transcendentals",
            title: "The transcendentals in scholastic philosophy",
            sourceName: "Aquinas curated reference note",
            facts: "In scholastic philosophy the transcendentals are the properties that belong to every being simply because it is a being, so they are not confined to any one category of things. The usual list is being, one, true, and good; Aquinas's fuller list in De veritate q.1 a.1 is being, thing, one, something, true, and good. They are coextensive with being: whatever is, is one, true, and good in some respect. Each adds to \"being\" only a further aspect under which the same thing is considered.",
            retrievalAliases: [
                "transcendentals", "transcendental in scholastic", "scholastic transcendental",
                "transcendental in thomis", "transcendental in aquinas",
                "transcendental properties of being", "transcendental property of being"
            ]
        )
    ]

    func references(
        for question: String,
        limit: Int = 3
    ) -> [AquinasGroundingReference] {
        guard limit > 0 else { return [] }
        let normalizedQuestion = Self.normalized(question)
        let questionTokens = Self.tokens(in: normalizedQuestion)

        return Self.references
            .compactMap { reference -> (AquinasGroundingReference, Int)? in
                let aliasScore = reference.retrievalAliases.reduce(into: 0) { score, alias in
                    if normalizedQuestion.contains(Self.normalized(alias)) {
                        score += 12
                    }
                }
                let referenceTokens = Self.tokens(
                    in: reference.title + " " + reference.facts + " "
                        + reference.retrievalAliases.joined(separator: " ")
                )
                let overlapScore = questionTokens.intersection(referenceTokens).count * 2
                let score = aliasScore + overlapScore
                return score > 2 ? (reference, score) : nil
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.id < $1.0.id }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Curated references whose question matched a retrieval *alias* rather than merely sharing a
    /// couple of tokens.
    ///
    /// The general `references(for:limit:)` ranking above admits a two-token overlap, which is the
    /// right bar when these entries are the entire corpus but far too loose when they are merged
    /// ahead of MiniLM results for every question. Alias hits are the precise signal, so the
    /// merged path uses only those — see `MiniLMGroundingProvider`.
    ///
    /// This exists because the bundled 48k-passage corpus has essentially no conciliar or creedal
    /// text: "Nicene Creed" appears once in the whole export (incidentally, in the Thirty-Nine
    /// Articles) and "begotten, not made" once, so semantic search answers council questions out
    /// of Livy and Herodotus. These curated entries carry the anti-confusion facts that coverage
    /// gap would otherwise lose, and their stable ids are what `verifiedGroundedResponse` gates on.
    static func aliasMatchedReferences(
        for question: String,
        limit: Int
    ) -> [AquinasGroundingReference] {
        guard limit > 0 else { return [] }
        let normalizedQuestion = normalized(question)

        return references
            .compactMap { reference -> (AquinasGroundingReference, Int)? in
                let score = reference.retrievalAliases.reduce(into: 0) { score, alias in
                    if normalizedQuestion.contains(normalized(alias)) {
                        score += alias.count
                    }
                }
                return score > 0 ? (reference, score) : nil
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.id < $1.0.id }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
    }

    private static func tokens(in text: String) -> Set<String> {
        Set(
            normalized(text)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
    }
}
