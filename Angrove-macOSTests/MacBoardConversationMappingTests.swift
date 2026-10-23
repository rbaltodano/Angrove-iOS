import Foundation
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardConversationMappingTests {
    @Test func streamingAnswersCannotBeCopiedAsCompletedHistory() {
        let session = MacConversationState()
        session.configure(preview: true)
        session.branches = [branch(["Grace"])]
        session.selectedBranch = session.branches[0].id
        session.pendingResponses = ["\(session.selectedBranch):0"]
        let board = WorktreeBoard()
        var item = WorktreeBoard.Item(origin: .zero)
        item.session = session
        board.items = [item]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        board.dropOnSidebar(item.id, runtime: runtime)
        #expect(board.errorMessage != nil)
        #expect(board.pendingReplacement == nil)
        #expect(board.items[0].sourceConversationID == nil)
        #expect(!runtime.modelTasks.isBusy)
    }

    @Test func firstTransferMapsEveryCompletedTurnAndRepeatedTransfersDoNotRepeatWork() async throws {
        let fixture = Fixture(branches: [branch(["Grace", "Grace", "Justice"]), branch(["Hope"])])
        fixture.enqueue()
        fixture.enqueue() // Same drop while its first mapping is still running.
        try await fixture.finish()
        #expect(await fixture.model.answers == ["Grace", "Grace", "Justice", "Hope"])
        #expect(fixture.store.seeds.count == 3)
        #expect(fixture.store.checkpoints.count == 4, "Covered turns need checkpoints too")
        // A fresh service reads the same durable checkpoint shape after a relaunch.
        fixture.store.checkpoints = try JSONDecoder().decode([String: String].self,
            from: JSONEncoder().encode(fixture.store.checkpoints))
        fixture.mapper = MacConversationTreeMapping(storage: fixture.store.storage)
        fixture.enqueue()
        try await fixture.finish()
        #expect(await fixture.model.answers.count == 4)
        #expect(fixture.store.seeds.count == 3)
    }

    @Test func returnPreservesExistingSeedsAndAddsOnlyNewSubjects() async throws {
        let oldBranch = branch(["Grace"])
        let baseline = MacConversationMappingTurn.fingerprints(in: [oldBranch])
        var continued = oldBranch
        append("Grace", to: &continued)
        append("Justice", to: &continued)
        let fixture = Fixture(branches: [continued])
        let original = LocalInsightTreeSeed(id: UUID(), label: "Grace", summary: "Grace",
            embedding: [1, 0, 0], embeddingVersion: "mapping-test-v1", createdAt: .distantPast)
        fixture.store.seeds = [original]
        fixture.enqueue(baseline: baseline)
        try await fixture.finish()
        #expect(await fixture.model.answers == ["Grace", "Justice"])
        #expect(fixture.store.seeds.first == original, "Existing subject identity and metadata must survive")
        #expect(fixture.store.seeds.count == 2)
        append("Hope", to: &fixture.store.conversation!.branches[0])
        fixture.enqueue(baseline: baseline)
        try await fixture.finish()
        #expect(await fixture.model.answers == ["Grace", "Justice", "Hope"])
        #expect(fixture.store.seeds.count == 3)
        #expect(fixture.store.seeds.first == original)
    }

    @Test func changedTurnIsCheckedAgainWithoutReplacingItsOldSubject() async throws {
        let fixture = Fixture(branches: [branch(["Grace"])])
        fixture.enqueue()
        try await fixture.finish()
        let oldSeed = try #require(fixture.store.seeds.first)
        fixture.store.conversation!.branches[0].activeChatBlocks[0] = .text("Justice")
        fixture.enqueue()
        try await fixture.finish()
        #expect(await fixture.model.answers == ["Grace", "Justice"])
        #expect(fixture.store.seeds.first == oldSeed)
        #expect(fixture.store.seeds.count == 2)
    }

    @Test func cancellationAndFailedExtractionRemainRetryable() async throws {
        let fixture = Fixture(branches: [branch(["Grace"])])
        await fixture.model.hold(true)
        fixture.enqueue()
        try await wait { await fixture.model.answers.count == 1 }
        fixture.runtime.modelTasks.cancelTasks { $0.kind == .updateInsightTree }
        await fixture.model.hold(false)
        #expect(fixture.store.checkpoints.isEmpty)
        #expect(fixture.store.seeds.isEmpty)
        await fixture.model.failNext()
        fixture.enqueue()
        try await fixture.finish()
        #expect(fixture.store.checkpoints.isEmpty)
        fixture.enqueue()
        try await fixture.finish()
        #expect(fixture.store.checkpoints.count == 1)
        #expect(fixture.store.seeds.count == 1)
    }

    @Test func deletingOrEditingDuringAnalysisDiscardsLateResult() async throws {
        for deletes in [false, true] {
            let fixture = Fixture(branches: [branch(["Grace"])])
            await fixture.model.hold(true)
            fixture.enqueue()
            try await wait { await fixture.model.answers.count == 1 }
            if deletes { fixture.store.conversation = nil }
            else { fixture.store.conversation!.branches[0].activeChatBlocks[0] = .text("Justice") }
            await fixture.model.hold(false)
            try await fixture.finish()
            #expect(fixture.store.seeds.isEmpty)
            #expect(fixture.store.checkpoints.isEmpty)
        }
    }

    @Test func oldEmbeddingSpaceIsRefreshedWithoutDuplicatingTheSubject() async throws {
        let fixture = Fixture(branches: [branch(["Grace"])])
        let id = UUID()
        fixture.store.seeds = [LocalInsightTreeSeed(id: id, label: "Grace", summary: "Grace",
            embedding: [0, 1], embeddingVersion: "retired-space", createdAt: .distantPast)]
        fixture.enqueue()
        try await fixture.finish()
        #expect(fixture.store.seeds.count == 1)
        #expect(fixture.store.seeds[0].id == id)
        #expect(fixture.store.seeds[0].createdAt == .distantPast)
        #expect(fixture.store.seeds[0].embeddingVersion == "mapping-test-v1")
        #expect(fixture.store.checkpoints.count == 1)
    }

    @Test func transferMappingFinishesBeforeAFollowingQuestionAndKeepsTurnOrder() async throws {
        let fixture = Fixture(branches: [branch(["Grace", "Justice"])])
        fixture.enqueue()
        var seedsWhenQuestionStarted = 0
        fixture.runtime.modelTasks.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            seedsWhenQuestionStarted = fixture.store.seeds.count
        }
        try await fixture.finish()
        #expect(seedsWhenQuestionStarted == 2)
        #expect(await fixture.model.answers == ["Grace", "Justice"])
    }

    @Test func backgroundMappingSurvivesForegroundPreemption() async throws {
        let fixture = Fixture(branches: [branch(["Grace"])])
        await fixture.model.hold(true)
        fixture.enqueue(priority: .background)
        try await wait { await fixture.model.answers.count == 1 }
        fixture.runtime.modelTasks.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            await fixture.model.hold(false)
        }
        try await fixture.finish()
        #expect(fixture.store.seeds.count == 1)
        #expect(fixture.store.checkpoints.count == 1)
        fixture.enqueue()
        try await fixture.finish()
        #expect(fixture.store.seeds.count == 1)
    }

    @Test func explicitQueueReorderingCanMoveAQuestionAheadOfPendingMapping() async throws {
        let fixture = Fixture(branches: [branch(["Grace"])])
        await fixture.model.hold(true)
        fixture.runtime.modelTasks.enqueue(kind: .labelWorktreeItem) {
            while await fixture.model.isHolding { try? await Task.sleep(for: .milliseconds(10)) }
        }
        fixture.enqueue()
        let mappingID = try #require(fixture.runtime.modelTasks.upcomingTasks.first?.id)
        var seedsAtQuestion = -1
        let questionID = fixture.runtime.modelTasks.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            seedsAtQuestion = fixture.store.seeds.count
        }
        #expect(fixture.runtime.modelTasks.moveUpcoming(id: questionID, relativeTo: mappingID, placeAfterTarget: false))
        await fixture.model.hold(false)
        try await fixture.finish()
        #expect(seedsAtQuestion == 0)
        #expect(fixture.store.seeds.count == 1)
    }

    @Test func completionFilterExcludesFailedCancelledEmptyAndUnsupportedEvidence() {
        var branch = branch(["Grace", "Justice", "Hope", "", questionCanceledResponseText])
        branch.setResponsePresentation(ResponsePresentationMetadata(responseIndex: 2, showsThinking: false,
            thinkingSummary: [], evidenceBasis: .generalKnowledge, outcome: .completed))
        branch.setResponsePresentation(ResponsePresentationMetadata(responseIndex: 4, showsThinking: false,
            thinkingSummary: [], evidenceBasis: .corpusGrounded, outcome: .failed))
        let turns = MacConversationMappingTurn.completed(in: [branch])
        #expect(turns.map(\.answer) == ["Grace"])
        #expect(turns[0].question == "Question 0")
        #expect(turns[0].responseIndex == 0)
    }

    @Test func boardCheckpointIsBackwardCompatibleAndSurvivesSerialization() throws {
        let source = branch(["Grace"])
        let fingerprints = MacConversationMappingTurn.fingerprints(in: [source])
        var item = WorktreeStoredItem(id: UUID(), origin: .zero, text: "", isHeading: false)
        item.sourceConversationID = UUID()
        item.sourceMappedTurns = fingerprints
        let encoded = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(WorktreeStoredItem.self, from: encoded)
        #expect(restored.sourceMappedTurns == fingerprints)
        #expect(restored.sourceConversationID == item.sourceConversationID)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "sourceMappedTurns")
        #expect(try JSONDecoder().decode(WorktreeStoredItem.self,
            from: JSONSerialization.data(withJSONObject: legacy)).sourceMappedTurns == nil)
    }

    private func branch(_ answers: [String]) -> ChatBranch {
        var value = ChatBranch(startingConcept: nil)
        value.topQuestionSubmitted = true
        value.topQuestionText = "Question 0"
        for answer in answers { append(answer, to: &value) }
        return value
    }

    private func append(_ answer: String, to branch: inout ChatBranch) {
        if !branch.activeChatBlocks.isEmpty {
            branch.activeChatBlocks.append(.user("Question \(branch.activeChatBlocks.count)", nil, []))
        }
        let index = branch.activeChatBlocks.count
        branch.activeChatBlocks.append(.text(answer))
        branch.setResponsePresentation(ResponsePresentationMetadata(responseIndex: index,
            showsThinking: false, thinkingSummary: [], evidenceBasis: .corpusGrounded, outcome: .completed))
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await predicate())
    }

    @MainActor private final class Fixture {
        let store: MemoryStore
        let model = MappingModel()
        let runtime: MacApplicationRuntime
        var mapper: MacConversationTreeMapping
        init(branches: [ChatBranch]) {
            store = MemoryStore(conversation: InquiryConversation(branches: branches))
            mapper = MacConversationTreeMapping(storage: store.storage)
            runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue(), testEmbeddingProvider: MappingEmbeddings())
        }
        func enqueue(baseline: [String: String] = [:], priority: ModelTaskPriority = .foreground) {
            guard let conversation = store.conversation else { return }
            mapper.enqueue(conversationID: conversation.id,
                turns: MacConversationMappingTurn.completed(in: conversation.branches), baseline: baseline, runtime: runtime, priority: priority)
        }
        func finish() async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while runtime.modelTasks.isBusy, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!runtime.modelTasks.isBusy)
        }
    }

    @MainActor private final class MemoryStore {
        var conversation: InquiryConversation?
        var seeds: [LocalInsightTreeSeed] = []
        var checkpoints: [String: String] = [:]
        init(conversation: InquiryConversation) { self.conversation = conversation }
        var storage: MacConversationTreeMapping.Storage {
            .init(conversation: { [self] id in conversation?.id == id ? conversation : nil },
                  seeds: { [self] _ in seeds }, saveSeeds: { [self] _, value in seeds = value },
                  checkpoints: { [self] _ in checkpoints }, saveCheckpoints: { [self] _, value in checkpoints = value },
                  didAddSeed: { _ in })
        }
    }
}

private struct MappingEmbeddings: EmbeddingProvider {
    var version: String { "mapping-test-v1" }
    func embed(_ text: String) async -> [Double]? {
        if text.contains("Grace") { return [1, 0, 0] }
        if text.contains("Justice") { return [0, 1, 0] }
        return [0, 0, 1]
    }
}

private actor MappingModel: AngroveModel {
    private(set) var answers: [String] = []
    private var isHeld = false
    var isHolding: Bool { isHeld }
    private var fails = false
    func hold(_ value: Bool) { isHeld = value }
    func failNext() { fails = true }
    func insightTreeSeedCandidate(question: String, response: String) async throws -> (label: String, summary: String)? {
        answers.append(response)
        while isHeld { try await Task.sleep(for: .milliseconds(10)) }
        if fails { fails = false; throw AngroveModelActionError.unavailable }
        return (response, response)
    }
    func respond(to context: ConversationContext) async -> ModelResponse { ModelResponse(text: "Test answer") }
    func compact(_ context: ConversationContext) async -> String { "" }
    func defineTerm(_ term: String, in context: ConversationContext) async throws -> ConceptDefinition { throw AngroveModelActionError.unavailable }
    func labelSubject(forTitles titles: [String]) async throws -> String { throw AngroveModelActionError.unavailable }
    func blendConceptCandidates(_ concepts: [ConceptDefinition], weights: [Double]) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
}
