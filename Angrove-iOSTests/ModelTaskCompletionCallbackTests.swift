import Foundation
import Testing
@testable import Angrove_iOS

@MainActor
@Suite("Model task completion callback")
struct ModelTaskCompletionCallbackTests {
    @Test("Every completed task reaches the callback, without relying on SwiftUI observation")
    func callbackRunsForEachCompletion() async throws {
        let queue = ModelTaskQueue()
        var completed: [UUID] = []
        queue.onTaskCompleted = { completed.append($0.id) }
        let first = queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {}
        let second = queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {}
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while completed.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(completed == [first, second])
    }
}
