import Foundation

/// Shared-queue work owns its captured turn even after the originating page is unmounted.
@MainActor
enum ConversationTreeAnalysisScheduling {
    typealias Step = @MainActor () async -> Void

    /// Steps that finished survive preemption: a foreground question cancels this background job
    /// and the queue restarts it later, and only unfinished model calls should run again.
    private final class Steps {
        var remaining: [Step]
        init(_ steps: [Step]) { remaining = steps }
    }

    static func enqueue(
        on queue: ModelTaskQueue,
        conversationID: UUID,
        steps: [Step]
    ) {
        guard !steps.isEmpty else { return }
        let work = Steps(steps)
        // Another turn's mapping job must never suppress this one. The queue serializes them.
        queue.enqueue(
            kind: .updateInsightTree,
            originPage: .conversation,
            conversationID: conversationID,
            priority: .background
        ) {
            while let step = work.remaining.first {
                await step()
                guard !Task.isCancelled else { return }
                work.remaining.removeFirst()
            }
        }
    }
}
