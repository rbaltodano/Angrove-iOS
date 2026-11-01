import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Question recall")
struct QuestionRecallTests {
    private let history = ["What is virtue?", "Is prudence a virtue?", "What is the mean?"]

    @Test("Steps back from the newest question and stops at the oldest")
    func stepsBackward() {
        var recall = QuestionRecall()
        var text = ""
        text = recall.older(in: history, current: text) ?? text
        #expect(text == "What is the mean?")
        text = recall.older(in: history, current: text) ?? text
        text = recall.older(in: history, current: text) ?? text
        #expect(text == "What is virtue?")
        #expect(recall.older(in: history, current: text) == nil)
    }

    @Test("Stepping forward past the newest question empties the field")
    func stepsForwardToEmpty() {
        var recall = QuestionRecall()
        var text = recall.older(in: history, current: "") ?? ""
        text = recall.older(in: history, current: text) ?? text
        text = recall.newer(in: history, current: text) ?? text
        #expect(text == "What is the mean?")
        #expect(recall.newer(in: history, current: text) == "")
        #expect(recall.newer(in: history, current: "") == nil)
    }

    @Test("Never replaces a typed draft or an edited recalled question")
    func protectsDrafts() {
        var recall = QuestionRecall()
        #expect(recall.older(in: history, current: "My own draft") == nil)
        _ = recall.older(in: history, current: "")
        #expect(recall.older(in: history, current: "What is the mean? Explain") == nil)
        #expect(recall.newer(in: history, current: "What is the mean? Explain") == nil)
    }

    @Test("Branch history includes the first question and follow-ups in order")
    func branchHistory() {
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is virtue?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("Answer"), .user("Is prudence a virtue?", [], []), .text("Answer")]
        #expect(branch.submittedQuestions == ["What is virtue?", "Is prudence a virtue?"])
    }
}
