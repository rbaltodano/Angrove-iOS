import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Conversation response state")
struct ConversationResponseStatePolicyTests {
    @Test("Switching to an empty or shorter conversation preserves an offscreen answer")
    func switchedConversationKeepsCompletion() {
        let original = UUID()
        for count in [0, 1, 2, 10] {
            #expect(ConversationResponseStatePolicy.completionDestination(
                isCancelled: false, isViewVisible: true,
                originalBranchID: original, displayedBranchID: UUID(),
                responseIndex: 3, displayedBlockCount: count
            ) == .detached)
        }
    }

    @Test("An unmounted column persists its answer even if its binding still has the old ID")
    func unmountedColumnKeepsCompletion() {
        let branchID = UUID()
        #expect(ConversationResponseStatePolicy.completionDestination(
            isCancelled: false, isViewVisible: false,
            originalBranchID: branchID, displayedBranchID: branchID,
            responseIndex: 1, displayedBlockCount: 0
        ) == .detached)
    }

    @Test("Explicit cancellation and a removed live response slot discard late results")
    func cancelledOrRemovedResponseDoesNotReturn() {
        let branchID = UUID()
        #expect(ConversationResponseStatePolicy.completionDestination(
            isCancelled: true, isViewVisible: false,
            originalBranchID: branchID, displayedBranchID: UUID(),
            responseIndex: 1, displayedBlockCount: 0
        ) == .discarded)
        #expect(ConversationResponseStatePolicy.completionDestination(
            isCancelled: false, isViewVisible: true,
            originalBranchID: branchID, displayedBranchID: branchID,
            responseIndex: 1, displayedBlockCount: 0
        ) == .discarded)
    }

    @Test("Completed text reveals while its queue task waits for the reveal gate")
    func responseTextBreaksRevealGateCycle() {
        let isAwaiting = ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: true,
            isLocallyPending: false,
            taskPhase: .current
        )

        #expect(!isAwaiting)
    }

    @Test("An empty response remains awaiting for current and queued tasks")
    func emptyResponseTracksQueueState() {
        #expect(ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: false,
            isLocallyPending: false,
            taskPhase: .current
        ))
        #expect(ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: false,
            isLocallyPending: false,
            taskPhase: .upcoming
        ))
    }

    @Test("An empty response without pending work is ready")
    func emptyResponseWithoutPendingWorkIsReady() {
        #expect(!ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: false,
            isLocallyPending: false,
            taskPhase: nil
        ))
    }
}
