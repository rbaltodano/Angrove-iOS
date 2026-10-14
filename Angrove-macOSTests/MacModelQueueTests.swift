import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacModelQueueTests {
    @Test func idleAndEveryCompletionArePublished() async throws {
        let queue = ModelTaskQueue()
        #expect(queue.currentTask == nil)
        #expect(queue.upcomingTasks.isEmpty)
        var completed: [UUID] = []
        queue.onTaskCompleted = { completed.append($0.id) }
        let first = queue.enqueue(kind: .updateInsightTree) {}
        let second = queue.enqueue(kind: .studyBranch) {}
        try await wait { completed.count == 2 }
        #expect(completed == [first, second])
        #expect(queue.currentTask == nil)
    }

    @Test func upcomingTasksCanBeReorderedRemovedAndCurrentStopped() async throws {
        let queue = ModelTaskQueue()
        var started: [Int] = []
        var cancelled: [Int] = []
        queue.enqueue(kind: .studyBranch, onCancel: { cancelled.append(0) }) {
            started.append(0)
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
        try await wait { started == [0] }
        let first = queue.enqueue(kind: .createMidpoint, onCancel: { cancelled.append(1) }) { started.append(1) }
        let second = queue.enqueue(kind: .makeNode, onCancel: { cancelled.append(2) }) { started.append(2) }
        let third = queue.enqueue(kind: .updateInsightTree, onCancel: { cancelled.append(3) }) { started.append(3) }
        #expect(queue.upcomingTasks.map(\.id) == [first, second, third])
        #expect(queue.moveUpcoming(id: third, relativeTo: first, placeAfterTarget: false))
        #expect(queue.upcomingTasks.map(\.id) == [third, first, second])
        queue.removeUpcoming(id: first)
        #expect(cancelled == [1])
        queue.stopCurrent()
        try await wait { started.count == 3 && queue.currentTask == nil }
        #expect(started == [0, 3, 2])
        #expect(cancelled == [1, 0])
    }

    @Test func clearingOneConversationPreservesOtherJobs() async throws {
        let queue = ModelTaskQueue()
        let firstConversation = UUID(), otherConversation = UUID()
        var started = false, cancelled = 0, otherFinished = false
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0), conversationID: firstConversation,
            onCancel: { cancelled += 1 }) {
            started = true
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
        try await wait { started }
        queue.enqueue(kind: .updateInsightTree, conversationID: firstConversation, onCancel: { cancelled += 1 }) {}
        queue.enqueue(kind: .updateInsightTree, conversationID: otherConversation) { otherFinished = true }
        queue.cancelTasks { $0.conversationID == firstConversation }
        try await wait { otherFinished }
        #expect(cancelled == 2)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(predicate())
    }
}
