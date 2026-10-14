import Foundation

// Synthesized `Decodable` requires every non-optional key, even when the property declares a
// default. Saved conversations and imported exports must keep decoding as fields are added, so
// these decoders fall back to each property's default for any missing key. Encoding stays
// synthesized; the key names below must match the property names.
//
// When adding a stored property to either type, decode it here too. The round-trip regression
// test in `InquiryModelsDecodingTests` fails if a populated field is dropped.

extension ChatBranch {
    private enum DecodingKeys: String, CodingKey {
        case id, startingConcept, parentBranchID, parentResponseIndex, duplicatedResponse, yOffset
        case activeChatBlocks, topQuestionText, topQuestionUploads, topQuestionSubmitted
        case bottomQuestionText, showBottomInput, attachedConcept, branchContextConcept
        case generatedBranchTitle, compactedContext, compactedThroughBlockCount
        case hiddenPromptContext, pinnedHeaderQuestion, responsePresentations
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            startingConcept: try c.decodeIfPresent(ConceptDefinition.self, forKey: .startingConcept),
            parentBranchID: try c.decodeIfPresent(UUID.self, forKey: .parentBranchID),
            parentResponseIndex: try c.decodeIfPresent(Int.self, forKey: .parentResponseIndex),
            duplicatedResponse: try c.decodeIfPresent(String.self, forKey: .duplicatedResponse),
            yOffset: try c.decodeIfPresent(CGFloat.self, forKey: .yOffset) ?? 0,
            hiddenPromptContext: try c.decodeIfPresent(String.self, forKey: .hiddenPromptContext)
        )
        activeChatBlocks = try c.decodeIfPresent([ChatBlock].self, forKey: .activeChatBlocks) ?? []
        topQuestionText = try c.decodeIfPresent(String.self, forKey: .topQuestionText) ?? ""
        topQuestionUploads = try c.decodeIfPresent([UploadedFile].self, forKey: .topQuestionUploads) ?? []
        topQuestionSubmitted = try c.decodeIfPresent(Bool.self, forKey: .topQuestionSubmitted) ?? false
        bottomQuestionText = try c.decodeIfPresent(String.self, forKey: .bottomQuestionText) ?? ""
        showBottomInput = try c.decodeIfPresent(Bool.self, forKey: .showBottomInput) ?? false
        attachedConcept = try c.decodeIfPresent(ConceptDefinition.self, forKey: .attachedConcept)
        branchContextConcept = try c.decodeIfPresent(ConceptDefinition.self, forKey: .branchContextConcept)
        generatedBranchTitle = try c.decodeIfPresent(String.self, forKey: .generatedBranchTitle)
        compactedContext = try c.decodeIfPresent(String.self, forKey: .compactedContext)
        compactedThroughBlockCount = try c.decodeIfPresent(Int.self, forKey: .compactedThroughBlockCount)
        pinnedHeaderQuestion = try c.decodeIfPresent(String.self, forKey: .pinnedHeaderQuestion)
        responsePresentations = try c.decodeIfPresent(
            [ResponsePresentationMetadata].self, forKey: .responsePresentations
        )
    }
}

extension InquiryConversation {
    private enum DecodingKeys: String, CodingKey {
        case id, title, isStudyTopic, studyTopicID, isPinned, branches, promotedInsightIDs, createdAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "New Conversation",
            isStudyTopic: try c.decodeIfPresent(Bool.self, forKey: .isStudyTopic) ?? false,
            studyTopicID: try c.decodeIfPresent(UUID.self, forKey: .studyTopicID),
            isPinned: try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            branches: try c.decodeIfPresent([ChatBranch].self, forKey: .branches)
                ?? [ChatBranch(startingConcept: nil)],
            promotedInsightIDs: try c.decodeIfPresent([UUID].self, forKey: .promotedInsightIDs) ?? [],
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        )
    }
}
