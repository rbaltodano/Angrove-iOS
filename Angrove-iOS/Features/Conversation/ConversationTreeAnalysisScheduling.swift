import Foundation

/// Shared-queue work owns its captured turn even after the originating page is unmounted.
@MainActor
enum ConversationTreeAnalysisScheduling {
    static func enqueue(
        on queue: ModelTaskQueue,
        conversationID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        // Another turn's mapping job must never suppress this one. The queue serializes them.
        queue.enqueue(
            kind: .updateInsightTree,
            originPage: .conversation,
            conversationID: conversationID,
            priority: .background,
            operation: operation
        )
    }
}
