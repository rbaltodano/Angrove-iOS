import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Conversation passage picker")
struct ConversationPassagePickerTests {
    private func passage(_ text: String) -> ConceptDefinition {
        ConceptDefinition(word: "The same work", partOfSpeech: "", pronunciation: "", meaning: text, example: "", isLibraryQuote: true)
    }

    @Test("Includes draft and submitted quotes, excludes Insights, and preserves distinct excerpts")
    func findsPassagesAcrossThread() {
        let first = passage("First excerpt")
        let second = passage("Second excerpt")
        let third = passage("Third excerpt")
        let insight = ConceptDefinition(word: "Virtue", partOfSpeech: "", pronunciation: "", meaning: "A moral habit", example: "")
        var root = ChatBranch(startingConcept: nil)
        root.branchContextConcept = first
        root.attachedConcept = second
        root.activeChatBlocks = [.user("A question", first, []), .user("An insight question", insight, [])]
        var child = ChatBranch(startingConcept: third, parentBranchID: root.id)
        child.activeChatBlocks = [.user("Another question", second, [])]

        let results = ChatBranch.quotedLibraryPassages(in: [root, child])
        #expect(results.map(\.id) == [first.id, second.id, third.id])
    }

    @Test("Only passages belonging to the supplied conversation are listed")
    func keepsConversationsSeparate() {
        let clip = passage("Saved globally, but not added to this conversation")
        let unrelated = ChatBranch(startingConcept: clip)
        let current = ChatBranch(startingConcept: nil)
        #expect(ChatBranch.quotedLibraryPassages(in: [current]).isEmpty)
        #expect(ChatBranch.quotedLibraryPassages(in: [unrelated]).map(\.id) == [clip.id])
    }
}
