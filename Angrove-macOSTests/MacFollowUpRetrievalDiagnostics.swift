import Foundation
import Testing
@testable import AngroveMac

/// Opt-in diagnostic for underspecified follow-up retrieval. For each fixture it records the
/// query `groundingQuery` builds today, the query it would build if the previous question were
/// always included, and the real top-3 references each one retrieves. No model runs.
///
/// `TEST_RUNNER_ANGROVE_FOLLOWUP_DIAGNOSTIC=1 xcodebuild … test
/// -only-testing:Angrove-macOSTests/MacFollowUpRetrievalDiagnostics`
/// Results are printed as `FollowUpDiag <json>` lines (the test sandbox can't write elsewhere).
struct MacFollowUpRetrievalDiagnostics {
    private struct Fixture {
        let id: String
        let previousQuestion: String
        let previousAnswer: String
        let latest: String
        /// A reference mentioning any of these is on the conversation's subject.
        let subjectTerms: [String]
        /// A genuine topic change: including the previous question would be wrong.
        var isTopicShift = false
        /// Text of the passage that actually answers the follow-up, when the corpus has one.
        var gold: String? = nil
    }

    private struct Row: Encodable {
        let id: String
        let isTopicShift: Bool
        let dependsOnContext: Bool
        let currentQuery: String
        let currentTitles: [String]
        let currentOnSubject: Int
        let withPreviousTitles: [String]
        let withPreviousOnSubject: Int
        /// `FollowUpRouting.evaluativeAware`.
        let candidateDependsOnContext: Bool
        let candidateTitles: [String]
        let candidateExcerpts: [String]
        let candidateOnSubject: Int
        let historyKept: Bool
        let candidateHistoryKept: Bool
    }

    private static let fixtures: [Fixture] = [
        // Superlatives and comparisons with no subject of their own.
        .init(id: "virtues-greatest", previousQuestion: "What are the theological virtues?",
              previousAnswer: "Faith, hope, and charity: virtues infused by God that order us directly to God.",
              latest: "Which is the greatest, and why?", subjectTerms: ["charity", "theological virtue", "faith", "hope"],
              gold: "charity is the greatest of the theological virtues"),
        .init(id: "cardinal-most", previousQuestion: "What are the cardinal virtues?",
              previousAnswer: "Prudence, justice, fortitude, and temperance, the hinges of the moral life.",
              latest: "Which matters most?", subjectTerms: ["prudence", "cardinal", "justice", "temperance", "fortitude"],
              gold: "justice is the chief of the moral virtues"),
        .init(id: "five-ways-strongest", previousQuestion: "What are Aquinas's five ways?",
              previousAnswer: "Five arguments for God's existence: from motion, efficient causation, contingency, degrees of perfection, and governance.",
              latest: "Which one is strongest?", subjectTerms: ["five ways", "motion", "contingen", "first cause", "existence of god"],
              gold: "whether god exists"),
        .init(id: "plato-aristotle-influence", previousQuestion: "Who were Plato and Aristotle?",
              previousAnswer: "Two Greek philosophers: Plato, Socrates's student who taught the theory of Forms, and Aristotle, Plato's student who grounded knowledge in experience.",
              latest: "Who was more influential on medieval thought?", subjectTerms: ["plato", "aristotle"]),
        .init(id: "sacraments-first", previousQuestion: "What are the seven sacraments?",
              previousAnswer: "Baptism, confirmation, Eucharist, penance, anointing of the sick, holy orders, and matrimony.",
              latest: "Which is the most important?", subjectTerms: ["sacrament", "eucharist", "baptism"],
              gold: "eucharist is the greatest of the sacraments"),
        .init(id: "transcendentals-why", previousQuestion: "What are the transcendentals?",
              previousAnswer: "Being, one, true, and good: properties that belong to every being as such.",
              latest: "Why?", subjectTerms: ["transcendental", "being", "goodness", "truth"]),
        .init(id: "law-better", previousQuestion: "What are the kinds of law in Aquinas?",
              previousAnswer: "Eternal, natural, human, and divine law.",
              latest: "Which is higher, and how do they relate?", subjectTerms: ["law", "eternal", "natural law"]),
        .init(id: "augustine-agree", previousQuestion: "What did Augustine teach about grace?",
              previousAnswer: "That grace is God's unmerited gift that heals and moves the will, without which no one can turn to God.",
              latest: "Did the Council of Trent agree?", subjectTerms: ["grace", "trent", "justification"]),
        // Controls: a pronoun already links the follow-up (should depend on context today).
        .init(id: "control-pronoun", previousQuestion: "What is natural law?",
              previousAnswer: "Natural law is rational creatures' participation in the eternal law.",
              latest: "How does it differ from divine law?", subjectTerms: ["natural law", "divine law", "law"]),
        // Controls: a genuine topic change (should not take the previous question).
        .init(id: "shift-boethius", previousQuestion: "What is natural law?",
              previousAnswer: "Natural law is rational creatures' participation in the eternal law.",
              latest: "Who was Boethius?", subjectTerms: ["boethius"], isTopicShift: true),
        .init(id: "shift-lepanto", previousQuestion: "What are the theological virtues?",
              previousAnswer: "Faith, hope, and charity: virtues infused by God that order us directly to God.",
              latest: "What happened at the Battle of Lepanto?", subjectTerms: ["lepanto"], isTopicShift: true),
    ]

    private struct VariantRow: Encodable {
        let id: String
        let variant: String
        let query: String
        let goldRankTop10: Int?
    }

    /// Query phrasings for a follow-up that depends on the previous question.
    private static func variants(_ fixture: Fixture) -> [(String, String)] {
        let subject = fixture.previousQuestion
            .lowercased()
            .replacingOccurrences(of: "?", with: "")
            .split(separator: " ")
            .filter { !["what", "who", "are", "were", "is", "was", "the", "in", "of", "did", "teach", "about", "and"].contains($0) }
            .joined(separator: " ")
        return [
            ("previousThenLatest", "\(fixture.previousQuestion)\n\n\(fixture.latest)"),
            ("latestThenPrevious", "\(fixture.latest)\n\n\(fixture.previousQuestion)"),
            ("latestWithSubject", "\(fixture.latest) \(subject)"),
            // "Which is the greatest, and why?" -> "Which of the theological virtues is the greatest, and why?"
            ("whichOfSubject", Self.whichOf(fixture.latest, subject: subject)),
            ("handRewritten", Self.handRewritten[fixture.id] ?? fixture.latest),
            // Sanity check: can the retriever find the passage from its own wording?
            ("goldHeading", "Whether \(fixture.gold ?? "")?"),
        ]
    }

    /// An upper bound: the standalone question a person would write.
    private static let handRewritten = [
        "virtues-greatest": "Which of the theological virtues is the greatest?",
        "cardinal-most": "Which of the cardinal virtues is the most important?",
        "five-ways-strongest": "Which of Aquinas's five ways to prove that God exists is the strongest?",
        "sacraments-first": "Which of the seven sacraments is the greatest?",
    ]

    private static func whichOf(_ latest: String, subject: String) -> String {
        for opener in ["Which one is ", "Which is ", "Which "] where latest.hasPrefix(opener) {
            let rest = latest.dropFirst(opener.count)
            let verb = opener == "Which " ? "" : "is "
            return "Which of the \(subject) \(verb)\(rest)"
        }
        return "\(latest) \(subject)"
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANGROVE_FOLLOWUP_DIAGNOSTIC"] != nil))
    func followUpQueryVariants() async throws {
        let provider = LazyGroundingProvider()
        for fixture in Self.fixtures {
            guard let gold = fixture.gold else { continue }
            for (name, query) in Self.variants(fixture) {
                let references = await provider.referencesAsync(for: query, limit: 10)
                let rank = references.firstIndex { "\($0.title) \($0.facts)".lowercased().contains(gold) }
                let row = VariantRow(id: fixture.id, variant: name, query: query, goldRankTop10: rank.map { $0 + 1 })
                print("FollowUpVariant \(String(decoding: try JSONEncoder().encode(row), as: UTF8.self))")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANGROVE_FOLLOWUP_DIAGNOSTIC"] != nil))
    func followUpRetrieval() async throws {
        let provider = LazyGroundingProvider()
        for fixture in Self.fixtures {
            let context = ConversationContext(transcript: [
                .user(fixture.previousQuestion, nil, []),
                .text(fixture.previousAnswer),
                .user(fixture.latest, nil, []),
            ])
            let currentQuery = LiteRTAngroveModel.groundingQuery(for: context)
            let withPrevious = "\(fixture.previousQuestion)\n\n\(fixture.latest)"
            let current = await provider.referencesAsync(for: currentQuery, limit: 3)
            let merged = await provider.referencesAsync(for: withPrevious, limit: 3)
            let candidateQuery = LiteRTAngroveModel.groundingQuery(for: context, routing: .evaluativeAware)
            let candidate = await provider.referencesAsync(for: candidateQuery, limit: 3)
            func historyKept(_ routing: LiteRTAngroveModel.FollowUpRouting) -> Bool {
                !LiteRTAngroveModel.startsFreshTopic(
                    latestQuestion: fixture.latest,
                    previousQuestion: fixture.previousQuestion,
                    previousAnswer: fixture.previousAnswer,
                    routing: routing
                )
            }
            let row = Row(
                id: fixture.id,
                isTopicShift: fixture.isTopicShift,
                // groundingQuery includes the previous question only when it judges the
                // follow-up to depend on it.
                dependsOnContext: currentQuery != fixture.latest,
                currentQuery: currentQuery,
                currentTitles: current.map(\.title),
                currentOnSubject: Self.onSubject(current, terms: fixture.subjectTerms),
                withPreviousTitles: merged.map(\.title),
                withPreviousOnSubject: Self.onSubject(merged, terms: fixture.subjectTerms),
                candidateDependsOnContext: candidateQuery != fixture.latest,
                candidateTitles: candidate.map(\.title),
                candidateExcerpts: candidate.map { String($0.facts.prefix(400)) },
                candidateOnSubject: Self.onSubject(candidate, terms: fixture.subjectTerms),
                historyKept: historyKept(.standard),
                candidateHistoryKept: historyKept(.evaluativeAware)
            )
            print("FollowUpDiag \(String(decoding: try JSONEncoder().encode(row), as: UTF8.self))")
        }
    }

    private static func onSubject(_ references: [AngroveGroundingReference], terms: [String]) -> Int {
        references.filter { reference in
            let text = "\(reference.title) \(reference.facts)".lowercased()
            return terms.contains { text.contains($0) }
        }.count
    }
}
