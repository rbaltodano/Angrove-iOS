import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacStudyTopicsTests {
    @Test func deletingATopicUnfilesOnlyItsConversations() throws {
        let topicID = UUID()
        let otherTopicID = UUID()
        let filed = InquiryConversation(title: "Filed", studyTopicID: topicID)
        let elsewhere = InquiryConversation(title: "Elsewhere", studyTopicID: otherTopicID)
        let loose = InquiryConversation(title: "Loose")
        let snapshot = InquiryPersistenceSnapshot(conversations: [filed, elsewhere, loose], activeConversationID: filed.id)
        let updated = try #require(MacSidebarConversationActions.unfiling(topic: topicID, in: snapshot))
        #expect(updated.conversations[0].studyTopicID == nil)
        #expect(updated.conversations[0].branches == filed.branches)
        #expect(updated.conversations[1] == elsewhere)
        #expect(updated.conversations[2] == loose)
        #expect(updated.activeConversationID == filed.id)
        #expect(MacSidebarConversationActions.unfiling(topic: UUID(), in: snapshot) == nil)
    }

    @Test func titlesFallBackFromCustomTitleToQuestionThenUntitled() {
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "  What is prudence?  "
        #expect(MacStudyTopicsView.title(of: InquiryConversation(title: "Virtue", branches: [branch])) == "Virtue")
        #expect(MacStudyTopicsView.title(of: InquiryConversation(branches: [branch])) == "What is prudence?")
        #expect(MacStudyTopicsView.title(of: InquiryConversation(branches: [ChatBranch(startingConcept: nil)])) == "New Conversation")
        #expect(MacStudyTopicsView.displayTitle(StudyTopic(title: " \n")) == "Untitled Study Topic")
        #expect(MacStudyTopicsView.displayTitle(StudyTopic(title: " Grace ")) == "Grace")
    }
}
