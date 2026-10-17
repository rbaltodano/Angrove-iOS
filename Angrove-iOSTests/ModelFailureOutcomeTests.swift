import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Failed model task outcomes")
@MainActor struct ModelFailureOutcomeTests {
    @Test("A reported failure does not publish a successful completion and the next task runs")
    func failedTaskDoesNotCompleteSuccessfully() async throws {
        let queue = ModelTaskQueue()
        let branchID = UUID()
        var succeeded = 0
        queue.onTaskCompleted = { _ in succeeded += 1 }
        queue.enqueue(kind: .userQuestion(branchID: branchID, responseIndex: 0)) {
            queue.reportCurrentFailure()
        }
        for _ in 0..<1000 {
            if !queue.isBusy { break }
            await Task.yield()
        }
        #expect(!queue.isBusy)
        #expect(queue.latestCompletedTask == nil)
        #expect(queue.completedUserQuestionBranchIDs.isEmpty)
        #expect(succeeded == 0)
        queue.enqueue(kind: .userQuestion(branchID: branchID, responseIndex: 1)) {}
        for _ in 0..<1000 {
            if !queue.isBusy { break }
            await Task.yield()
        }
        #expect(!queue.isBusy)
        #expect(succeeded == 1)
        #expect(queue.completedUserQuestionBranchIDs.contains(branchID))
    }

    @Test("Unavailable responses retain failure status through response adapters")
    func unavailableOutcome() async {
        let model = UnavailableAngroveModel()
        let response = await model.respond(to: ConversationContext(), thinkingEnabled: false, onUpdate: { _ in })
        #expect(response.outcome == .failed)
        #expect(response.withEvidenceBasis(.generalKnowledge).outcome == .failed)
    }
}
