import Foundation
import LiteRTLM
import Testing
@testable import Angrove_iOS

@Suite("LiteRT production runtime contracts")
struct LiteRTProductionRuntimeTests {
    @Test("Model store rejects a truncated package")
    func modelStoreRejectsTruncatedPackage() throws {
        let manifest = LiteRTModelManifest(
            fileName: "test.litertlm",
            byteCount: 4,
            sha256: "unused"
        )
        let store = LiteRTModelStore(manifest: manifest)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([0, 1, 2]).write(to: fileURL)

        #expect(throws: LiteRTModelStoreError.self) {
            try store.validateModel(at: fileURL)
        }
    }

    @Test("Model store accepts an exact development probe package")
    func modelStoreAcceptsDevelopmentProbePackage() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([0, 1, 2, 3]).write(to: fileURL)
        let manifest = LiteRTModelManifest(
            fileName: fileURL.lastPathComponent,
            byteCount: 4,
            sha256: "development-probe"
        )
        let store = LiteRTModelStore(
            manifest: manifest,
            developmentModelURL: fileURL
        )

        #expect(try store.installedModelURL() == fileURL)
    }

    @Test("Installer hashes model bytes deterministically")
    func installerHashesModel() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("test".utf8).write(to: fileURL)

        #expect(
            try LiteRTModelInstaller.sha256(of: fileURL)
                == "9f86d081884c7d659a2feaa0c55ad015"
                    + "a3bf4f1b2b0b822cd15d6c15b0f00a08"
        )
    }

    @MainActor
    @Test("Natural definition questions are recognized")
    func detectsDefinitionRequests() {
        #expect(
            definitionTerm(in: "What does prudence mean?") == "prudence"
        )
        #expect(
            definitionTerm(in: "What is the meaning of act and potency?")
                == "act and potency"
        )
        #expect(
            definitionTerm(in: "Please define natural law.") == "natural law"
        )
        #expect(
            definitionTerm(in: "What is prudence?") == "prudence"
        )
    }

    @MainActor
    @Test("Broad what-is questions do not become definition cards")
    func broadQuestionsDoNotTriggerDefinitionCards() {
        #expect(definitionTerm(in: "What is the second ecumenical council?") == nil)
        #expect(definitionTerm(in: "What is the Peloponnesian War about?") == nil)
        #expect(definitionTerm(in: "What is the best way to learn JavaScript?") == nil)
        #expect(definitionTerm(in: "What is happening with this code?") == nil)
        #expect(definitionTerm(in: "What is natural law?") == "natural law")
    }

    @Test("General-knowledge definitions remain ordinary conversation")
    func generalKnowledgeDefinitionDoesNotCreateInsightMetadata() {
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What does moral obligation mean?"))

        let response = ModelResponse(
            text: "Infralapsarianism is a theological ordering of the divine decrees.",
            evidenceBasis: .generalKnowledge
        )

        #expect(response.evidenceBasis == .generalKnowledge)
        #expect(response.keyTerms.isEmpty)
        #expect(response.insight == nil)
        #expect(InlineInsightMarkup.insights(in: response.annotatedText).isEmpty)
    }

    @Test("Definition evidence must name the requested term")
    func definitionEvidenceRejectsSemanticNearMatches() {
        let nearMatch = AngroveGroundingReference(
            id: "near-match",
            title: "Predestination",
            sourceName: "Test source",
            facts: "This passage discusses divine providence and election.",
            retrievalAliases: []
        )
        let directMatch = AngroveGroundingReference(
            id: "direct-match",
            title: "Infralapsarianism",
            sourceName: "Test source",
            facts: "Infralapsarianism orders the divine decrees after the fall.",
            retrievalAliases: []
        )

        #expect(
            LiteRTAngroveModel.definitionEvidence(
                for: "infralapsarianism",
                in: [nearMatch]
            ).isEmpty
        )
        #expect(
            LiteRTAngroveModel.definitionEvidence(
                for: "infralapsarianism",
                in: [nearMatch, directMatch]
            ) == [directMatch]
        )
    }

    @Test("Specialist definitions can use general knowledge")
    func specialistDefinitionEvidenceRequirement() {
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What is infralapsarianism?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What is utilitarianism?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What is moral obligation?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What is courage?"))
    }

    @Test("Response evidence bases have user-facing disclosure titles")
    func responseEvidenceBasisDisclosureTitles() {
        #expect(ResponseEvidenceBasis.generalKnowledge.disclosureTitle == "General Knowledge")
        #expect(ResponseEvidenceBasis.corpusGrounded.disclosureTitle == "Corpus Grounded")
        #expect(ResponseEvidenceBasis.sourceRequired.disclosureTitle == "Source Required")
        #expect(ResponseEvidenceBasis.generalKnowledge.disclosureDescription.contains("general knowledge"))
        #expect(ResponseEvidenceBasis.corpusGrounded.disclosureDescription.contains("passages"))
        #expect(ResponseEvidenceBasis.sourceRequired.disclosureDescription.contains("reliable passage"))
    }

    @Test("Evidence-required requests abstain when no passage is retrieved")
    func evidenceRequirementSelection() {
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("Who is the current pope?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What did Nicaea decide?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What is the Nicene Creed?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("Define the Council of Nicaea."))
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("What does the Nicene Creed say?"))
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("Who wrote the Didache?"))
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("Quote Session VI of the Council of Trent."))
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("Can you quote the Gospel of John?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("When was the Council of Trent?"))

        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("Can Spider-Man be a good role model even if he is not real?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("I feel stuck and need some perspective."))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("What does moral obligation mean?"))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("Please define moral obligation."))
        #expect(!LiteRTAngroveModel.requiresCorpusEvidence("Imagine how a parent might teach courage."))
    }

    @Test("Historical reflections and general facts do not require a passage")
    func historicalDiscussionWithoutPassages() {
        let reflection = "I think the introduction of biological elements into the space race transformed the shift into one that really got people thinking about the future of humanity. At the same time the fear of the cold war might have made people think we were doing it for the wrong reasons."
        for question in [reflection,
            "How did Sputnik 2 change the space race?",
            "When was Sputnik 2 launched?",
            "Who was Laika?",
            "How many animals flew on Sputnik 2?",
            "How does history shape our hopes for humanity?",
            "I feel warmth toward that idea.",
            "I think scientific ambition was a source of hope during the Cold War."
        ] {
            #expect(!LiteRTAngroveModel.requiresCorpusEvidence(question))
        }
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("Cite a source for Sputnik 2's launch date."))
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("According to this chapter, why was Laika chosen?"))
        #expect(LiteRTAngroveModel.requiresCorpusEvidence("What is the latest space mission?"))

        let instruction = LiteRTAngroveModel.evidenceExperimentInstruction(
            context: ConversationContext(transcript: [.user(reflection, nil, [])]),
            references: []
        )
        #expect(instruction.contains("Engage with the user’s argument"))
        #expect(instruction.contains("historical and scientific discussion"))
    }

    @Test("A reflective reply retrieves through its unanswered study prompt")
    func reflectiveFollowUpRetainsStudyPromptForGrounding() {
        let prompt = "How does the understanding of justification as a gift received through faith and charity inform one's practical life and moral action?"
        let reflection = "Well it has me thinking that I should be gracious to others since I have been shown grace."
        let query = LiteRTAngroveModel.groundingQuery(
            for: ConversationContext(
                transcript: [
                    .user(prompt, nil, []),
                    .user(reflection, nil, [])
                ]
            )
        )

        #expect(query.contains(prompt))
        #expect(query.contains(reflection))
    }

    @Test("A normal follow-up still retrieves from only its latest question")
    func answeredConversationDoesNotReusePriorQuestionForGrounding() {
        let latestQuestion = "What is infralapsarianism?"
        let query = LiteRTAngroveModel.groundingQuery(
            for: ConversationContext(
                transcript: [
                    .user("What is justification?", nil, []),
                    .text("Justification is God's gracious work of making a person righteous."),
                    .user(latestQuestion, nil, [])
                ]
            )
        )

        #expect(query == latestQuestion)
    }

    @Test("A follow-up that depends on the previous exchange retrieves with the previous question")
    func contextDependentFollowUpRetrievesWithPreviousQuestion() {
        let lombard = LiteRTAngroveModel.groundingQuery(
            for: ConversationContext(
                transcript: [
                    .user("Who was Peter Lombard?", nil, []),
                    .text("Peter Lombard was a theologian and bishop of Paris whose Four Books of Sentences became the standard theology textbook."),
                    .user("Did Aquinas comment on his work?", nil, [])
                ]
            )
        )
        #expect(lombard.contains("Peter Lombard"))
        #expect(lombard.contains("Did Aquinas comment on his work?"))

        let subjectless = LiteRTAngroveModel.groundingQuery(
            for: ConversationContext(
                transcript: [
                    .user("What is the natural law?", nil, []),
                    .text("The natural law is the rational creature's participation in the eternal law."),
                    .user("Can you give a concrete example?", nil, [])
                ]
            )
        )
        #expect(subjectless.contains("natural law"))

        let answerSubject = LiteRTAngroveModel.groundingQuery(
            for: ConversationContext(
                transcript: [
                    .user("What is the Summa Theologiae?", nil, []),
                    .text("The Summa Theologiae is Thomas Aquinas's unfinished systematic presentation of theology, organized into questions and articles."),
                    .user("How is each article structured?", nil, [])
                ]
            )
        )
        #expect(answerSubject.contains("Summa Theologiae"))

        let newTopic = "What's the capital of Portugal?"
        let unrelated = LiteRTAngroveModel.groundingQuery(
            for: ConversationContext(
                transcript: [
                    .user("Who was Peter Lombard?", nil, []),
                    .text("Peter Lombard was a theologian and bishop of Paris."),
                    .user(newTopic, nil, [])
                ]
            )
        )
        #expect(unrelated == newTopic)
    }

    @MainActor
    @Test("A follow-up with a pronoun is told what the previous question asked about")
    func pronounFollowUpNamesThePreviousQuestion() throws {
        let request = try #require(
            LiteRTAngroveModel.latestRequestMessage(
                for: ConversationContext(
                    transcript: [
                        .user("Who was Peter Lombard?", nil, []),
                        .text("Peter Lombard was a theologian and bishop of Paris."),
                        .user("Did Aquinas comment on his work?", nil, [])
                    ]
                )
            )
        )
        #expect(request.toString.contains("The previous question was: “Who was Peter Lombard?”"))

        let standalone = try #require(
            LiteRTAngroveModel.latestRequestMessage(
                for: ConversationContext(
                    transcript: [
                        .user("Who was Peter Lombard?", nil, []),
                        .text("Peter Lombard was a theologian and bishop of Paris."),
                        .user("What is the natural law?", nil, [])
                    ]
                )
            )
        )
        #expect(!standalone.toString.contains("The previous question was"))
    }

    @MainActor
    @Test("A follow-up that points at earlier items keeps the conversation")
    func itemReferenceKeepsContext() {
        #expect(
            !LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "Which one governs the others?",
                previousQuestion: "What are the cardinal virtues?",
                previousAnswer: "The cardinal virtues are prudence, justice, fortitude, and temperance."
            )
        )
    }

    @Test("A source-dependent question needs a reference about what it names")
    func evidenceMustNameTheSubject() {
        let council = AngroveGroundingReference(
            id: "corpus-seven-ecumenical-councils-0",
            title: "The Seven Ecumenical Councils",
            sourceName: "The Seven Ecumenical Councils",
            facts: "Cardinal Baronius disputed the genuineness of this Canon, as Pope Innocent III declares.",
            retrievalAliases: [],
            sourceID: "seven-ecumenical-councils",
            chunkIndex: 12
        )
        let summa = AngroveGroundingReference(
            id: "corpus-summa-theologica-0",
            title: "Summa Theologica",
            sourceName: "Summa Theologica",
            facts: "Question: Whether it is lawful to kill sinners? Aquinas's own answer: I answer that…",
            retrievalAliases: [],
            sourceID: "summa-theologica",
            chunkIndex: 8537
        )
        let note = AngroveGroundingReference(
            id: "aquinas-life",
            title: "Thomas Aquinas: life",
            sourceName: "Angrove curated reference note",
            facts: "Pope John XXII canonized him on 18 July 1323.",
            retrievalAliases: []
        )
        let canonization = "Which pope canonized Aquinas, and in what year?"
        #expect(!LiteRTAngroveModel.referencesNameSubject(of: canonization, in: [council]))
        #expect(LiteRTAngroveModel.referencesNameSubject(of: canonization, in: [note, council]))
        #expect(LiteRTAngroveModel.referencesNameSubject(
            of: "According to Aquinas, is it lawful to kill sinners?",
            in: [summa]
        ))
        #expect(!LiteRTAngroveModel.referencesNameSubject(
            of: "Who wrote the Letter to the Hebrews?",
            in: [council]
        ))
        // A question that names nothing is not gated.
        #expect(LiteRTAngroveModel.referencesNameSubject(
            of: "What year did the council meet?",
            in: [council]
        ))
    }

    @Test("Definition evidence may name the term in the plural")
    func definitionEvidenceAllowsPlural() {
        let note = AngroveGroundingReference(
            id: "scholastic-transcendentals",
            title: "The transcendentals in scholastic philosophy",
            sourceName: "Angrove curated reference note",
            facts: "In scholastic philosophy the transcendentals are the properties that belong to every being.",
            retrievalAliases: []
        )
        let unrelated = AngroveGroundingReference(
            id: "other",
            title: "Summa Theologica",
            sourceName: "Summa Theologica",
            facts: "Philosophy treats of many things in the schools.",
            retrievalAliases: []
        )
        let evidence = LiteRTAngroveModel.definitionEvidence(
            for: "a transcendental in scholastic philosophy",
            in: [note, unrelated]
        )
        #expect(evidence.map(\.id) == ["scholastic-transcendentals"])
    }

    @MainActor
    @Test("A follow-up about a subject the previous answer introduced keeps the conversation")
    func followUpOnAnswerSubjectKeepsContext() {
        let answer = "The Summa Theologiae is Thomas Aquinas's unfinished systematic presentation of theology, organized into questions and articles."
        #expect(
            !LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "How is each article structured?",
                previousQuestion: "What is the Summa Theologiae?",
                previousAnswer: answer
            )
        )
        // Without the answer there is nothing to connect the two questions.
        #expect(
            LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "How is each article structured?",
                previousQuestion: "What is the Summa Theologiae?"
            )
        )
        for unrelated in [
            "What's the capital of Portugal?",
            "Can you explain quantum entanglement in physics?",
            "Can you write some JavaScript cursor tracker code?"
        ] {
            #expect(
                LiteRTAngroveModel.startsFreshTopic(
                    latestQuestion: unrelated,
                    previousQuestion: "What is the Summa Theologiae?",
                    previousAnswer: answer
                ),
                "kept history for: \(unrelated)"
            )
        }
    }

    @Test("Direct-definition responses remain plain conversation")
    func directDefinitionDoesNotRenderInlineInsightCard() {
        let response = ModelResponse(
            text: "Prudence guides practical judgment.",
            evidenceBasis: .corpusGrounded
        )

        #expect(response.keyTerms.isEmpty)
        #expect(response.insight == nil)
        #expect(InlineInsightMarkup.insights(in: response.annotatedText).isEmpty)
        #expect(!response.annotatedText.contains("aq://"))
    }

    @Test("Ordinary responses never render an inline Insight card")
    func ordinaryResponseDoesNotRenderInlineCard() {
        let response = ModelResponse(
            text: "The council met in 381.",
            keyTerms: [KeyTerm(displayText: "council")]
        )

        #expect(InlineInsightMarkup.insights(in: response.annotatedText).isEmpty)
    }

    @MainActor
    @Test("Unrelated substantial questions start with fresh context")
    func topicShiftStartsFreshContext() {
        #expect(
            LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "What was the Peloponnesian War about?",
                previousQuestion: "Was the Didache written by the Apostle Paul?"
            )
        )
        #expect(
            LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "Can you write some JavaScript cursor tracker code?",
                previousQuestion: "What was the Peloponnesian War about?"
            )
        )
        #expect(
            !LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "Why was that council important?",
                previousQuestion: "What was the second ecumenical council?"
            )
        )
    }

    @Test("Follow-ups without a subject of their own keep the conversation")
    func subjectlessFollowUpsKeepContext() {
        let previous = "Think carefully about whether mercy can conflict with justice."
        for followUp in [
            "Can you give a concrete example?",
            "Explain more simply, please.",
            "Could you elaborate?",
            "Give me another example.",
            "Is it still taught today?",
            "What did he mean by those?"
        ] {
            #expect(
                !LiteRTAngroveModel.startsFreshTopic(
                    latestQuestion: followUp,
                    previousQuestion: previous
                ),
                "dropped history for: \(followUp)"
            )
        }
        #expect(
            LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "What's the capital of Portugal?",
                previousQuestion: previous
            )
        )
        #expect(
            LiteRTAngroveModel.startsFreshTopic(
                latestQuestion: "Can you explain quantum entanglement in physics?",
                previousQuestion: previous
            )
        )
    }

    @MainActor
    @Test("A text-only runtime sends image turns as text with a note, never image content")
    func imagesBecomeTextNotesWithoutVision() throws {
        try #require(!LiteRTAngroveRuntime.supportsVision)
        let upload = UploadedFile(
            name: "diagram.png",
            imageData: Data([0x89, 0x50]),
            rotationDegrees: 0
        )
        for isLatest in [true, false] {
            let message = try #require(
                LiteRTAngroveModel.engineMessage(
                    .user("What does this diagram show?", nil, [upload]),
                    isLatestUserRequest: isLatest
                )
            )
            #expect(message.contents.allSatisfy { content in
                if case .imageData = content { return false }
                return true
            })
            #expect(message.toString.contains("What does this diagram show?"))
            #expect(message.toString.contains("cannot view"))
        }
        let imageOnly = try #require(
            LiteRTAngroveModel.engineMessage(.user("", nil, [upload]))
        )
        #expect(imageOnly.toString.contains("cannot view"))
    }

    @MainActor
    @Test("Previous answers cannot be returned verbatim for a new turn")
    func repeatedPriorAnswerIsDetected() {
        let answer = "The Apostle Paul's letter to the elders is presented as a model of Christian teaching and living."
        let transcript: [ChatBlock] = [
            .user("Tell me about an early church letter.", nil, []),
            .text(answer),
            .user("Write some JavaScript cursor tracker code.", nil, [])
        ]

        #expect(
            LiteRTAngroveModel.repeatsEarlierAnswer(
                answer,
                transcript: transcript
            )
        )
        #expect(
            !LiteRTAngroveModel.repeatsEarlierAnswer(
                "A cursor tracker listens for pointer movement and updates coordinates.",
                transcript: transcript
            )
        )
    }

    @Test("Insight annotations cannot rewrite existing link markup")
    func insightAnnotationsDoNotNest() {
        let response = ModelResponse(
            text: "The deuterocanonical books form a wider canon.",
            keyTerms: [
                KeyTerm(displayText: "deuterocanonical"),
                KeyTerm(displayText: "canon")
            ]
        )

        #expect(
            response.annotatedText
                == "The [deuterocanonical](aq://deuterocanonical) books form a wider "
                    + "[canon](aq://canon)."
        )
        #expect(!response.annotatedText.contains("](["))
    }

    @MainActor
    @Test("Visible responses omit generated wrapper labels")
    func visibleResponsesOmitWrapperLabels() {
        #expect(
            LiteRTAngroveModel.visibleResponseText(
                from: "Answer: A good act can be corrupted by an evil intention."
            ) == "A good act can be corrupted by an evil intention."
        )
        #expect(
            LiteRTAngroveModel.visibleResponseText(
                from: "## **Response:**\nMercy perfects justice."
            ) == "Mercy perfects justice."
        )
        #expect(
            LiteRTAngroveModel.visibleResponseText(
                from: "The answer: prudence governs practical judgment."
            ) == "The answer: prudence governs practical judgment."
        )
        #expect(
            LiteRTAngroveModel.visibleResponseText(
                from: "<TASK:ANSWER_USER>Mercy perfects justice.</TASK:ANSWER_USER>"
            ) == "Mercy perfects justice."
        )
    }

    @MainActor
    @Test("Plain conversation output never exposes a legacy JSON wrapper")
    func plainConversationOutputRecoversLegacyJSON() {
        let raw = #"{"thinking_summary":["Hidden metadata"],"response":"Constantinople was the second ecumenical council.","key_terms":[]}"#

        #expect(
            LiteRTAngroveModel.plainConversationText(from: raw)
                == "Constantinople was the second ecumenical council."
        )
        #expect(!LiteRTAngroveModel.plainConversationText(from: raw).contains("key_terms"))
    }

    @MainActor
    @Test("Single-pass key-term metadata accepts only exact answer text")
    func singlePassKeyTermMetadataIsValidated() {
        let raw = #"{"response":"The First Council of Constantinople met in 381.","key_terms":[{"display_text":"First Council of Constantinople","canonical_term":"First Council of Constantinople","context_excerpt":"The First Council of Constantinople met in 381."},{"display_text":"Council of Adhesion","canonical_term":"Council of Adhesion","context_excerpt":"Council of Adhesion"}]}"#
        let response = LiteRTAngroveModel.conversationResponse(from: raw)

        #expect(response.text == "The First Council of Constantinople met in 381.")
        #expect(response.keyTerms.map(\.displayText) == ["First Council of Constantinople"])
    }

    @MainActor
    @Test("Inline markers become key terms with no separate recall step")
    func inlineMarkersBecomeKeyTerms() {
        let raw = "Aquinas distinguishes {{essence}} from {{existence}} to explain change."
        let (text, keyTerms) = LiteRTAngroveModel.inlineAnnotatedResponse(from: raw)

        #expect(text == "Aquinas distinguishes essence from existence to explain change.")
        #expect(keyTerms.map(\.displayText) == ["essence", "existence"])
        #expect(keyTerms.allSatisfy { text.contains($0.displayText) })
    }

    @MainActor
    @Test("Wikipedia-density inline annotation retains up to twelve distinct subjects")
    func wikipediaDensityInlineAnnotationsRetainTwelveSubjects() {
        let markedSubjects = (1...13).map { "{{Subject \($0)}}" }.joined(separator: ", ")
        let (_, keyTerms) = LiteRTAngroveModel.inlineAnnotatedResponse(from: markedSubjects)

        #expect(keyTerms.count == 12)
        #expect(keyTerms.first?.displayText == "Subject 1")
        #expect(keyTerms.last?.displayText == "Subject 12")
    }

    @MainActor
    @Test("An unterminated inline marker becomes plain prose without truncation")
    func unterminatedInlineMarkerPreservesProse() {
        let raw = "Aquinas distinguishes {{essence}} from exis{{tence"
        let (text, keyTerms) = LiteRTAngroveModel.inlineAnnotatedResponse(from: raw)

        #expect(text == "Aquinas distinguishes essence from existence")
        #expect(!text.contains("{{"))
        #expect(keyTerms.map(\.displayText) == ["essence"])
    }

    @MainActor
    @Test("Invalid inline metadata preserves its exact inner prose")
    func invalidInlineMarkerPreservesInnerProse() {
        let oversizedTerm = String(repeating: "word ", count: 20).trimmingCharacters(in: .whitespaces)
        let raw = "Before {{\(oversizedTerm)}} after."
        let (text, keyTerms) = LiteRTAngroveModel.inlineAnnotatedResponse(from: raw)

        #expect(text == "Before \(oversizedTerm) after.")
        #expect(keyTerms.isEmpty)
    }

    @MainActor
    @Test("Conversation card previews hide annotation markers and retain plain text")
    func conversationCardPreviewFlattensInsightMarkup() {
        let segments = ConversationCardAnswerFormatting.segments(
            from: "Aquinas joins {{prudence}} to *[right reason](aq://right-reason)*."
        )

        #expect(
            segments == [
                .plain("Aquinas joins prudence to right reason.")
            ]
        )
    }

    @MainActor
    @Test("Conversation card previews preserve prose after a dangling marker")
    func conversationCardPreviewPreservesDanglingMarkerText() {
        let segments = ConversationCardAnswerFormatting.segments(
            from: "Aquinas distinguishes {{essence}} from exis{{tence"
        )

        #expect(
            segments == [
                .plain("Aquinas distinguishes essence from existence")
            ]
        )
    }

    @Test("Untouched conversation drafts are discarded while insight context is retained")
    func conversationDraftRetention() {
        let emptyDraft = InquiryConversation()
        #expect(!ConversationDraftRetention.shouldKeep(emptyDraft))

        var insightDraft = InquiryConversation()
        insightDraft.branches[0].attachedConcept = ConceptDefinition(
            word: "Prudence",
            partOfSpeech: "noun",
            pronunciation: "",
            meaning: "Practical wisdom.",
            example: "",
            definitions: []
        )
        #expect(ConversationDraftRetention.shouldKeep(insightDraft))

        var textDraft = InquiryConversation()
        textDraft.branches[0].topQuestionText = "How does prudence guide action?"
        #expect(ConversationDraftRetention.shouldKeep(textDraft))
    }

    @Test("An unanswered Question of the Day draft is discarded, but typed text is kept")
    func unansweredQuestionOfTheDayDraftIsDiscarded() {
        var draft = InquiryConversation(title: "What is prudence?")
        draft.branches[0].pinnedHeaderQuestion = "What is prudence?"
        draft.branches[0].hiddenPromptContext = "<question of the day>"
        #expect(ConversationDraftRetention.isUntouchedPromptDraft(draft))
        #expect(!ConversationDraftRetention.shouldKeep(draft))

        draft.branches[0].topQuestionText = "Practical wisdom."
        #expect(ConversationDraftRetention.shouldKeep(draft))
    }

    @Test("Generation guard rejects exact repetitive loops")
    func generationGuardRejectsRepetitiveLoops() {
        let sentence = "Prudence directs practical reason toward the right action in a concrete circumstance"
        #expect(
            LiteRTGenerationGuard.hasDegenerateRepetition(
                in: "\(sentence). \(sentence)."
            )
        )
        #expect(
            !LiteRTGenerationGuard.hasDegenerateRepetition(
                in: "Prudence directs practical reason. Justice gives another person what is due."
            )
        )
    }

    @Test("Conversation decoding stays deterministic for the quantized checkpoint")
    func conversationSamplingStaysDeterministic() {
        let primary = LiteRTSampling.conversation

        #expect(primary.topK == 1)
        #expect(primary.topP == 1)
        #expect(primary.temperature == 0)
        #expect(primary.seed == 0)
        #expect(LiteRTSampling.structured.seed == 7)
    }

    @MainActor
    @Test("Quoted Insights precede the user question in model markup")
    func quotedInsightPromptMarkup() {
        let insight = ConceptDefinition(
            word: "Act & Potency",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "A capacity < ordered toward > actuality.",
            example: ""
        )

        let prompt = ConversationPromptMarkup.userPrompt(
            question: "How does this apply to change?",
            quotedInsight: insight
        )

        #expect(prompt.hasPrefix("<insight_quote>"))
        #expect(prompt.contains("<title>Act &amp; Potency</title>"))
        #expect(
            prompt.contains(
                "<definition>A capacity &lt; ordered toward &gt; actuality.</definition>"
            )
        )
        #expect(
            prompt.contains(
                "</insight_quote>\n\nUser question:\nHow does this apply to change?"
            )
        )
        #expect(!prompt.contains("<quoted_insight"))
    }

    @Test("Generation guard rejects mixed-script token corruption")
    func generationGuardRejectsMixedScriptCorruption() {
        let corrupted = String(
            repeating: "dynamは scotch 法 chim العربية 한글 磨 random_code ",
            count: 8
        )

        #expect(LiteRTGenerationGuard.hasDegenerateOutput(in: corrupted))
        #expect(
            !LiteRTGenerationGuard.hasDegenerateOutput(
                in: "Aquinas sometimes uses the Greek term phronesis, but the explanation remains coherent English prose."
            )
        )
    }

    @Test("Generation guard catches separated phrase loops")
    func generationGuardRejectsSeparatedPhraseLoops() {
        let phrase = "virtue directs a person toward the good through stable practical habits"
        let response = "\(phrase), especially in difficult choices. A separate thought appears. \(phrase)."

        #expect(LiteRTGenerationGuard.hasDegenerateRepetition(in: response))
        #expect(
            LiteRTGenerationGuard.responseBeforeRepetition(in: response)?
                .contains("A separate thought appears") == true
        )
        #expect(
            LiteRTGenerationGuard.responseBeforeRepetition(in: response)?
                .components(separatedBy: phrase).count == 2
        )
    }

    @MainActor
    @Test("Thinking summary matches a forgiveness question")
    func thinkingSummaryMatchesForgivenessQuestion() {
        let context = ConversationContext(
            transcript: [
                .user(
                    "How do I forgive myself when I keep making moral mistakes?",
                    nil,
                    []
                )
            ]
        )

        #expect(
            LiteRTAngroveModel.approachSummary(for: context) == [
                "Distinguishing forgiveness, repentance, guilt, and growth after repeated failure."
            ]
        )
    }

    @MainActor
    @Test("Thinking summary fallback avoids echoing the user's question")
    func thinkingSummaryFallbackAvoidsQuestionEcho() {
        let context = ConversationContext(
            transcript: [
                .user(
                    "How can friendship help a person become more patient?",
                    nil,
                    []
                )
            ]
        )

        let summary = LiteRTAngroveModel.approachSummary(for: context)
        #expect(
            summary == [
                "Working out the steps or mechanism the question is actually asking for."
            ]
        )
        #expect(!summary[0].contains("Focusing on"))
        for questionWord in ["friendship", "patient"] {
            #expect(!summary.joined().localizedCaseInsensitiveContains(questionWord))
        }
    }

    @Test("Local grounding distinguishes the first councils and icon council")
    func localGroundingRetrievesCouncilReferences() {
        let references = LocalAngroveGroundingProvider().references(
            for: "What were the first and second ecumenical councils?",
            limit: 3
        )
        let ids = Set(references.map(\.id))

        #expect(ids.contains("nicaea-325"))
        #expect(ids.contains("constantinople-381"))
        let constantinople = references.first { $0.id == "constantinople-381" }?.facts
        #expect(constantinople?.contains("second ecumenical council") == true)
        #expect(constantinople?.contains("Adhesion") == false)
    }

    @Test("Local grounding corrects Didache authorship")
    func localGroundingRetrievesDidacheAuthorship() {
        let references = LocalAngroveGroundingProvider().references(
            for: "Was the Didache written by Paul?",
            limit: 2
        )

        #expect(references.first?.id == "didache-authorship")
        #expect(references.first?.facts.contains("author is unknown") == true)
    }

    @Test("Local grounding retrieves the John 14 Scripture stopgap entry")
    func localGroundingRetrievesJohn14() {
        let references = LocalAngroveGroundingProvider().references(
            for: "Tell me about John Chapter 14",
            limit: 3
        )

        #expect(references.first?.id == "john-14")
        #expect(references.first?.facts.contains("Farewell Discourse") == true)
        #expect(references.first?.facts.contains("John 4") == false)
    }

    @Test("Local grounding retrieves other curated Scripture stopgap entries")
    func localGroundingRetrievesOtherScriptureEntries() {
        let romans = LocalAngroveGroundingProvider().references(
            for: "What does Romans chapter 8 say?",
            limit: 2
        )
        #expect(romans.first?.id == "romans-8")

        let psalm = LocalAngroveGroundingProvider().references(
            for: "Can you explain Psalm 23?",
            limit: 2
        )
        #expect(psalm.first?.id == "psalm-23")
    }

    @MainActor
    @Test("Structured local responses preserve exact key terms and public summaries")
    func structuredConversationResponseIsValidated() {
        let raw = #"""
        {
          "thinking_summary": ["Distinguishing Nicaea in 325 from Constantinople in 381."],
          "response": "The first council met at Nicaea in 325. The second met at Constantinople in 381.",
          "key_terms": [
            {
              "display_text": "The first council met at Nicaea",
              "canonical_term": "First Council of Nicaea",
              "context_excerpt": "The first council met at Nicaea in 325."
            },
            {
              "display_text": "Council of Adhesion",
              "canonical_term": "Council of Adhesion",
              "context_excerpt": "This excerpt does not occur in the response."
            }
          ]
        }
        """#

        let response = LiteRTAngroveModel.conversationResponse(from: raw)

        #expect(response.thinkingSummary.count == 1)
        #expect(response.keyTerms.count == 1)
        #expect(response.keyTerms.first?.displayText == "The first council met at Nicaea")
        #expect(
            response.annotatedText.contains(
                "[The first council met at Nicaea](aq://first-council-of-nicaea)"
            )
        )
        #expect(!response.annotatedText.contains("Council of Adhesion"))
    }

    @MainActor
    @Test("Truncated local JSON recovers the answer without exposing its wrapper")
    func truncatedConversationJSONRecoversAnswer() {
        let raw = #"""
        { "thinking_summary": ["A noisy plan."], "response": "The First Council of Constantinople (381) is called the second ecumenical council.
        """#
        let fallback = [
            "Comparing the established sequence: Nicaea in 325 was first, Constantinople in 381 was second, and Nicaea II in 787 was seventh."
        ]

        let response = LiteRTAngroveModel.conversationResponse(
            from: raw,
            fallbackThinkingSummary: fallback
        )

        #expect(
            response.text
                == "The First Council of Constantinople (381) is called the second ecumenical council."
        )
        #expect(response.thinkingSummary == fallback)
        #expect(!response.text.contains("thinking_summary"))
        // No heuristic fallback fills in key terms anymore — only the model's own inline
        // {{markers}} do, and truncated/malformed JSON never went through that path.
        #expect(response.keyTerms.isEmpty)
    }

    @MainActor
    @Test("Generic one-word annotation fragments are rejected")
    func genericKeyTermFragmentsAreRejected() {
        let raw = #"""
        {
          "thinking_summary": ["Checking the established historical sequence."],
          "response": "The First Council of Constantinople was the second ecumenical council.",
          "key_terms": [
            {
              "display_text": "second",
              "canonical_term": "second",
              "context_excerpt": "The First Council of Constantinople was the second ecumenical council."
            },
            {
              "display_text": "First Council of Constantinople",
              "canonical_term": "First Council of Constantinople",
              "context_excerpt": "The First Council of Constantinople was the second ecumenical council."
            }
          ]
        }
        """#

        let response = LiteRTAngroveModel.conversationResponse(from: raw)
        #expect(response.keyTerms.map(\.displayText) == ["First Council of Constantinople"])
    }

    @MainActor
    @Test("Generic model summaries are replaced by an inquiry-specific fallback")
    func genericStructuredThinkingSummaryUsesFallback() {
        let raw = #"""
        {
          "thinking_summary": ["Focusing on the user's question and the distinctions needed for a direct answer."],
          "response": "Prudence governs practical judgment.",
          "key_terms": []
        }
        """#
        let fallback = ["Distinguishing practical judgment from theoretical knowledge."]

        let response = LiteRTAngroveModel.conversationResponse(
            from: raw,
            fallbackThinkingSummary: fallback
        )

        #expect(response.thinkingSummary == fallback)
    }

    @MainActor
    @Test("Thinking summaries persist and older branches still decode")
    func responsePresentationMetadataPersistsCompatibly() throws {
        var branch = ChatBranch(startingConcept: nil)
        branch.setResponsePresentation(
            ResponsePresentationMetadata(
                responseIndex: 1,
                showsThinking: true,
                thinkingSummary: ["Comparing the two councils by date and doctrine."],
                evidenceBasis: .generalKnowledge
            )
        )

        let encoded = try JSONEncoder().encode(branch)
        let decoded = try JSONDecoder().decode(ChatBranch.self, from: encoded)
        #expect(
            decoded.responsePresentation(at: 1)?.thinkingSummary
                == ["Comparing the two councils by date and doctrine."]
        )
        #expect(decoded.responsePresentation(at: 1)?.evidenceBasis == .generalKnowledge)

        var presentationObject = try #require(
            (try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["responsePresentations"]
                as? [[String: Any]]
        )
        presentationObject[0].removeValue(forKey: "evidenceBasis")
        var noBasisObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        noBasisObject["responsePresentations"] = presentationObject
        let noBasisData = try JSONSerialization.data(withJSONObject: noBasisObject)
        let noBasisBranch = try JSONDecoder().decode(ChatBranch.self, from: noBasisData)
        #expect(noBasisBranch.responsePresentation(at: 1)?.evidenceBasis == nil)

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "responsePresentations")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyBranch = try JSONDecoder().decode(ChatBranch.self, from: legacyData)
        #expect(legacyBranch.responsePresentations == nil)
    }

    @MainActor
    @Test("Explicit authorship corrections reject contradictory drafts")
    func explicitAuthorshipCorrectionRejectsContradiction() {
        let correction = LiteRTAngroveModel.authorshipCorrectionDetails(
            in: "The Didache was not written by Paul; its author is unknown, right?"
        )
        #expect(correction?.subject == "The Didache")
        #expect(correction?.author == "Paul")

        #expect(
            !LiteRTAngroveModel.responseContradictsExplicitAuthorshipCorrection(
                question: "The Didache was not written by Paul.",
                response: "Paul is known to have written the Didache."
            )
        )
        #expect(
            LiteRTAngroveModel.responseContradictsExplicitAuthorshipCorrection(
                question: "The Didache was not written by Paul.",
                response: "Paul wrote the Didache, although its author is unknown."
            )
        )
        #expect(
            !LiteRTAngroveModel.responseContradictsExplicitAuthorshipCorrection(
                question: "The Didache was not written by Paul.",
                response: "Paul is not known to have written the Didache; its author is unknown."
            )
        )
    }

    @Test("Canvas collapses an Insight whose title matches its Node")
    func canvasCollapsesMatchingInsightTitle() {
        let matching = InsightModel(title: "Didache", definition: "An anonymous early Christian text.")
        let related = InsightModel(title: "Two Ways", definition: "A moral teaching within the text.")

        let collapsed = canvasInsightMembers(
            nodeLabel: "The Didache",
            insights: [matching, related],
            preservesMatchingTitle: false
        )
        #expect(collapsed.map(\.id) == [related.id])
        #expect(
            canvasInsightMembers(
                nodeLabel: "The Didache",
                insights: [matching],
                preservesMatchingTitle: true
            ).map(\.id) == [matching.id]
        )
    }

    @Test("Context budget compacts older turns while preserving the latest question verbatim")
    func contextBudgetPreservesLatestQuestion() throws {
        let latestQuestion = "Was the Didache written by Paul, or is its authorship unknown?"
        let context = ConversationContext(
            transcript: [
                .user("Explain early Christian writings.", nil, []),
                .text(String(repeating: "Earlier discussion with important context. ", count: 240)),
                .user(latestQuestion, nil, [])
            ]
        )

        #expect(AngroveContextBudget.totalTokenLimit == 4_096)
        #expect(AngroveContextBudget.shouldCompact(context))
        let split = try #require(AngroveContextBudget.historyAndLatestTurn(in: context))
        #expect(split.history.transcript.count == 2)
        #expect(split.latestTurn.count == 1)
        guard case .user(let preservedQuestion, _, _) = split.latestTurn[0] else {
            Issue.record("The latest turn was not preserved as a user question")
            return
        }
        #expect(preservedQuestion == latestQuestion)
    }

    @Test("Accuracy audit targets factual terms without delaying personal advice or ordinary questions")
    func factualAccuracyAuditSelection() {
        #expect(LiteRTAngroveModel.requiresFactualAccuracyAudit("Who wrote the Didache?"))
        #expect(LiteRTAngroveModel.requiresFactualAccuracyAudit("Explain the Council of Nicaea."))
        #expect(LiteRTAngroveModel.requiresFactualAccuracyAudit("How many ecumenical councils were there?"))
        #expect(!LiteRTAngroveModel.requiresFactualAccuracyAudit("I feel stuck and need some perspective."))
        #expect(!LiteRTAngroveModel.requiresFactualAccuracyAudit("Help me write a warm thank-you note."))
        // A generic question-word prefix alone no longer triggers the second-pass audit —
        // only a genuinely attribution/date/citation-sensitive term does. This avoids doubling
        // generation latency on nearly every question while still catching the risky ones.
        #expect(!LiteRTAngroveModel.requiresFactualAccuracyAudit("Tell me about John Chapter 14"))
        #expect(!LiteRTAngroveModel.requiresFactualAccuracyAudit("What is the Trinity?"))
    }

    @Test("Audit meta-commentary is detected so a confused audit reply falls back to the draft")
    func auditMetaCommentaryDetection() {
        #expect(
            LiteRTAngroveModel.isAuditMetaCommentary(
                """
                It seems there has been a mistake in the question you asked. You asked about \
                John chapter 14, but the draft answer refers to John chapter 4. Please clarify \
                which book or work you are referring to.
                """
            )
        )
        #expect(
            !LiteRTAngroveModel.isAuditMetaCommentary(
                """
                John chapter 14 is a pivotal moment in the Farewell Discourse, where Jesus \
                promises the disciples an Advocate and assures them of his continued presence.
                """
            )
        )
    }

    @MainActor
    private func definitionTerm(in request: String) -> String? {
        LiteRTAngroveModel.definitionRequestTerm(
            in: [.user(request, nil, [])]
        )
    }
}
