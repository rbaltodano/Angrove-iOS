import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacSidebarConversationActionsTests {
    @Test func renameTrimsAndPreservesConversationHistoryAndOtherConversations() throws {
        let first = InquiryConversation(title: "First")
        let second = InquiryConversation(title: "Second")
        let snapshot = InquiryPersistenceSnapshot(conversations: [first, second], activeConversationID: second.id)
        let updated = try #require(MacSidebarConversationActions.applying(.rename("  Renamed\n"), to: first.id, in: snapshot))
        #expect(updated.conversations[0].title == "Renamed")
        #expect(updated.conversations[0].branches == first.branches)
        #expect(updated.conversations[1] == second)
        #expect(updated.activeConversationID == second.id)
        #expect(MacSidebarConversationActions.applying(.rename(" \n"), to: first.id, in: snapshot) == nil)
        #expect(MacSidebarConversationActions.applying(.rename("Name"), to: UUID(), in: snapshot) == nil)
    }

    @Test func pinAndTopicActionsPreserveHistoryAndChangeMenuChoices() throws {
        let conversation = InquiryConversation(title: "A question")
        let topicID = UUID()
        let snapshot = InquiryPersistenceSnapshot(conversations: [conversation], activeConversationID: conversation.id)
        let pinned = try #require(MacSidebarConversationActions.applying(.setPinned(true), to: conversation.id, in: snapshot))
        let assigned = try #require(MacSidebarConversationActions.applying(.assignTopic(topicID), to: conversation.id, in: pinned))
        #expect(assigned.conversations[0].isPinned)
        #expect(assigned.conversations[0].studyTopicID == topicID)
        #expect(assigned.conversations[0].branches == conversation.branches)
        #expect(MacSidebarConversationMenuAction.pin.symbol(for: assigned.conversations[0]) == "pin.slash")
        let detached = try #require(MacSidebarConversationActions.applying(.assignTopic(nil), to: conversation.id, in: assigned))
        #expect(detached.conversations[0].studyTopicID == nil)
        let unpinned = try #require(MacSidebarConversationActions.applying(.setPinned(false), to: conversation.id, in: detached))
        #expect(!unpinned.conversations[0].isPinned)
    }

    @Test func pinnedRowsComeFirstWithStableRecencyAndNoTopicContainers() {
        let first = InquiryConversation(title: "Older", isPinned: true)
        let second = InquiryConversation(title: "Newer")
        let third = InquiryConversation(title: "Newest", isPinned: true)
        let topic = InquiryConversation(title: "Topic", isStudyTopic: true)
        #expect(MacSidebarConversationActions.sorted([first, second, third, topic]).map(\.id) == [third.id, first.id, second.id])
    }

    @Test func deletionSelectsAnotherConversationAndPreservesUnrelatedContent() {
        let first = InquiryConversation(title: "Delete")
        let second = InquiryConversation(title: "Keep")
        let snapshot = InquiryPersistenceSnapshot(conversations: [first, second], activeConversationID: first.id)
        let updated = MacSidebarConversationActions.deleting(first.id, in: snapshot)
        #expect(updated.conversations == [second])
        #expect(updated.activeConversationID == second.id)
        let empty = MacSidebarConversationActions.deleting(second.id, in: updated)
        #expect(empty.conversations.isEmpty)
        #expect(empty.activeConversationID == nil)
        let inactive = InquiryPersistenceSnapshot(conversations: [first, second], activeConversationID: second.id)
        #expect(MacSidebarConversationActions.deleting(first.id, in: inactive).activeConversationID == second.id)
    }

    @Test func backgroundSessionReceivesMetadataAndDeletionWithoutAMountedWorkspace() {
        let session = MacConversationState()
        let other = MacConversationState()
        let updated = InquiryConversation(id: session.id, title: "Renamed", studyTopicID: UUID())
        NotificationCenter.default.post(name: .macConversationMetadataChanged, object: updated)
        #expect(session.title == "Renamed")
        #expect(session.studyTopicID == updated.studyTopicID)
        #expect(other.title == "New Conversation")
        NotificationCenter.default.post(name: .macConversationDeleted, object: session.id)
        #expect(session.isDeleted)
        #expect(!other.isDeleted)
    }
}
