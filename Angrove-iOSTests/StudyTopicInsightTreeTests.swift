import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Study Topic Insight Tree")
struct StudyTopicInsightTreeTests {
    @Test("Snapshot includes only saved Insights attached to conversations in the topic")
    func snapshotIsTopicScoped() {
        let topicID = UUID()
        let otherTopicID = UUID()
        let includedConversationID = UUID()
        let otherConversationID = UUID()
        let includedInsight = concept("Grace")
        let otherInsight = concept("Justice")

        let snapshot = StudyTopicInsightTreeBuilder.snapshot(
            topicID: topicID,
            conversations: [
                InquiryConversation(
                    id: includedConversationID,
                    studyTopicID: topicID
                ),
                InquiryConversation(
                    id: otherConversationID,
                    studyTopicID: otherTopicID
                )
            ],
            savedInsights: [otherInsight, includedInsight],
            insightIDs: { conversationID in
                conversationID == includedConversationID
                    ? [includedInsight.id]
                    : [otherInsight.id]
            }
        )

        #expect(snapshot.map(\.id) == [includedInsight.id])
    }

    @Test("Snapshot combines memberships, removes duplicate terms, and sorts by title")
    func snapshotCombinesMemberships() {
        let topicID = UUID()
        let firstConversationID = UUID()
        let secondConversationID = UUID()
        let grace = concept("Grace")
        let duplicateGrace = concept("grace")
        let beatitude = concept("Beatitude")

        let snapshot = StudyTopicInsightTreeBuilder.snapshot(
            topicID: topicID,
            conversations: [
                InquiryConversation(
                    id: firstConversationID,
                    studyTopicID: topicID
                ),
                InquiryConversation(
                    id: secondConversationID,
                    studyTopicID: topicID
                )
            ],
            savedInsights: [grace, duplicateGrace, beatitude],
            insightIDs: { conversationID in
                conversationID == firstConversationID
                    ? [grace.id, beatitude.id]
                    : [duplicateGrace.id]
            }
        )

        #expect(snapshot.map(\.word) == ["Beatitude", "Grace"])
    }

    @Test("Snapshot includes bookmarked Insights that appear in topic transcripts")
    func snapshotIncludesTranscriptInsights() {
        let topicID = UUID()
        let grace = concept("Grace")
        let chipCharity = concept("Charity")
        let savedCharity = concept("charity")
        let unsaved = concept("Prudence")
        let unrelated = concept("Justice")

        var branch = ChatBranch(startingConcept: grace)
        branch.activeChatBlocks = [
            .user("What is charity?", chipCharity, []),
            .user("And prudence?", unsaved, [])
        ]

        let snapshot = StudyTopicInsightTreeBuilder.snapshot(
            topicID: topicID,
            conversations: [
                InquiryConversation(studyTopicID: topicID, branches: [branch])
            ],
            savedInsights: [unrelated, savedCharity, grace],
            insightIDs: { _ in [] }
        )

        // Bookmarked only (Prudence is not saved); matched by id or by term.
        #expect(snapshot.map(\.word) == ["charity", "Grace"])
    }

    @Test("Topic refresh detects changed definitions with stable IDs and ignores ordering")
    func refreshComparesContent() {
        let grace = concept("Grace"), justice = concept("Justice")
        let revisedGrace = ConceptDefinition(id: grace.id, word: grace.word, partOfSpeech: "noun",
            pronunciation: "", meaning: "A revised definition.", example: "")
        #expect(!StudyTopicInsightTreeBuilder.needsUpdate(accepted: [justice, grace], incoming: [grace, justice]))
        #expect(StudyTopicInsightTreeBuilder.needsUpdate(accepted: [grace], incoming: [revisedGrace]))
        #expect(StudyTopicInsightTreeBuilder.needsUpdate(accepted: [], incoming: [grace]))
        #expect(StudyTopicInsightTreeBuilder.needsUpdate(accepted: [grace], incoming: []))
    }

    private func concept(_ word: String) -> ConceptDefinition {
        ConceptDefinition(
            word: word,
            partOfSpeech: "noun",
            pronunciation: "",
            meaning: "A contextual definition of \(word).",
            example: ""
        )
    }
}
