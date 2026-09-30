import Foundation
import Testing
@testable import Aquinas_iOS

@MainActor
@Suite("Insight Tree label queue", .serialized)
struct InsightTreeLabelQueueTests {
    @Test("Cold foreground question precedes visible labels in both trees", arguments: [false, true])
    func questionFirst(conversation: Bool) async throws {
        let driver = LabelLoadingDriver()
        let queue = ModelTaskQueue(runtimeLifecycle: ModelRuntimeLifecycleManager(driver: driver))
        let model = LabelRecordingModel()
        let scope = conversation ? UUID() : nil
        #expect(!queue.isBusy)
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            model.events.append("question")
        }
        try await eventually { await driver.started }
        #expect(queue.pendingCount == 1)
        let concept = concept()
        let tree = makeTree([concept], model: model, queue: queue, scope: scope)
        #expect(queue.pendingCount == 2)
        #expect(queue.currentTask?.kind.userQuestionBranchID != nil)
        #expect(queue.upcomingTasks.first?.kind == .labelInsightTree)
        #expect(queue.upcomingTasks.first?.title == "Update Insight Tree")
        #expect(queue.upcomingTasks.first?.originPage == (conversation ? .conversation : .insights))
        #expect(queue.upcomingTasks.first?.conversationID == scope)
        tree.updateInsights([concept])
        #expect(queue.pendingCount == 2)
        #expect(model.events.isEmpty)
        await driver.open()
        try await eventually { !queue.isBusy }
        #expect(model.events == ["question", "label", "definition"])
        #expect(tree.nodes.first?.conceptLabel == "Generated Subject")
        #expect(tree.nodes.first?.definition == "Generated definition")
        #expect(queue.latestCompletedTask?.kind == .labelInsightTree)
        let reopened = makeTree([concept], model: model, queue: queue, scope: scope)
        #expect(reopened.nodes.first?.conceptLabel == "Generated Subject")
        #expect(reopened.nodes.first?.definition == "Generated definition")
        #expect(!queue.isBusy)
    }

    @Test("Blank clusters and suggestions do not generate labels or definitions", arguments: [false, true])
    func blankInput(conversation: Bool) async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let blank = concept(word: " \n", meaning: "\t ")
        let tree = makeTree([blank], model: model, queue: queue, scope: conversation ? UUID() : nil)
        #expect(!queue.isBusy)
        let node = try #require(tree.nodes.first)
        tree.generateSuggestedNode(between: node, and: node)
        #expect(!queue.isBusy)
        #expect(model.events.isEmpty)
        // A definition alone is useful input, and must remain eligible.
        let valid = ConceptDefinition(id: blank.id, word: " ", partOfSpeech: "",
                                      pronunciation: "", meaning: "Useful meaning", example: "")
        tree.updateInsights([valid])
        try await eventually { !queue.isBusy }
        #expect(model.inputs == [["Useful meaning"]])
        #expect(model.events == ["label", "definition"])
    }

    @Test("Pending label cancellation releases dedupe; reordered trees execute in UI order")
    func pendingCancellationAndReorder() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let gate = LabelGate()
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) { await gate.wait() }
        let a = concept(word: "First")
        let treeA = makeTree([a], model: model, queue: queue)
        let treeB = makeTree([concept(word: "Second")], model: model, queue: queue, scope: UUID())
        let firstID = try #require(queue.upcomingTasks.first?.id)
        queue.removeUpcoming(id: firstID)
        treeA.updateInsights([a])
        #expect(queue.upcomingTasks.count == 2)
        let secondID = try #require(queue.upcomingTasks.first?.id)
        let retryID = try #require(queue.upcomingTasks.last?.id)
        #expect(queue.moveUpcoming(id: retryID, relativeTo: secondID, placeAfterTarget: false))
        #expect(queue.upcomingTasks.map(\.id) == [retryID, secondID])
        gate.open()
        try await eventually { !queue.isBusy }
        #expect(model.inputs.map { $0.first! } == ["First: Meaning", "Second: Meaning"])
        #expect(treeA.nodes.first?.definition == "Generated definition")
        #expect(treeB.nodes.first?.definition == "Generated definition")
    }

    @Test("Stopping a running label ignores late output and permits retry")
    func stopRunningLabel() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let gate = LabelGate()
        model.labelGate = gate
        let source = concept()
        let tree = makeTree([source], model: model, queue: queue)
        try await eventually { model.inputs.count == 1 }
        queue.stopCurrent()
        #expect(!queue.isBusy)
        tree.updateInsights([source])
        #expect(queue.pendingCount == 1)
        gate.open()
        try await eventually { !queue.isBusy }
        #expect(model.inputs.count == 2)
        #expect(model.events.filter { $0 == "definition" }.count == 1)
        #expect(tree.nodes.first?.conceptLabel == "Generated Subject")
    }

    @Test("Foreground preemption keeps dedupe until background retry completes")
    func preemption() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let gate = LabelGate()
        model.labelGate = gate
        let source = concept()
        let tree = makeTree([source], model: model, queue: queue)
        try await eventually { model.inputs.count == 1 }
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            model.events.append("question")
        }
        tree.updateInsights([source])
        #expect(queue.pendingCount == 2)
        gate.open()
        try await eventually { !queue.isBusy }
        #expect(model.events == ["label", "question", "label", "definition"])
        #expect(tree.nodes.first?.definition == "Generated definition")
    }

    @Test("Preempted definitions resume without relabelling the cluster")
    func definitionPreemption() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let gate = LabelGate()
        model.definitionGate = gate
        let source = concept()
        let tree = makeTree([source], model: model, queue: queue)
        try await eventually { model.events.contains("definition") }
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            model.events.append("question")
        }
        tree.updateInsights([source])
        #expect(queue.pendingCount == 2)
        gate.open()
        try await eventually { !queue.isBusy }
        #expect(model.events == ["label", "definition", "question", "definition"])
        #expect(tree.nodes.first?.definition == "Generated definition")
    }

    @Test("A tree without the shared queue cannot bypass scheduling")
    func missingQueue() throws {
        let model = LabelRecordingModel()
        let tree = InsightTreeViewModel(insights: [concept()], model: model)
        let node = try #require(tree.nodes.first)
        tree.generateSuggestedNode(between: node, and: node)
        #expect(model.events.isEmpty)
    }

    @Test("Definitions remain queued and cancelled definitions never publish")
    func definitionCancellation() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let gate = LabelGate()
        model.definitionGate = gate
        let tree = makeTree([concept()], model: model, queue: queue)
        try await eventually { model.events.contains("definition") }
        #expect(queue.currentTask?.kind == .labelInsightTree)
        queue.stopCurrent()
        gate.open()
        // Wait for the deliberately cancellation-ignoring model to return.
        try await eventually { model.definitionsReturned == 1 }
        #expect(tree.nodes.first?.definition == "")
        #expect(!queue.isBusy)
    }

    @Test("Suggestion labels wait behind questions and ignore cancellation")
    func suggestions() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        let tree = makeTree([concept()], model: model, queue: queue)
        try await eventually { !queue.isBusy }
        model.events.removeAll()
        let questionGate = LabelGate()
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) {
            await questionGate.wait()
            model.events.append("question")
        }
        let node = try #require(tree.nodes.first)
        tree.generateSuggestedNode(between: node, and: node)
        #expect(queue.upcomingTasks.first?.kind == .labelInsightTree)
        #expect(model.events.isEmpty)
        questionGate.open()
        try await eventually { !queue.isBusy }
        #expect(model.events == ["question", "label"])
        let suggestion = try #require(tree.nodes.first(where: { $0.isSuggested }))
        tree.dismissSuggestedNode(suggestion)
        let labelGate = LabelGate()
        model.labelGate = labelGate
        let previousCount = model.inputs.count
        tree.generateSuggestedNode(between: node, and: node)
        try await eventually { model.inputs.count == previousCount + 1 }
        queue.stopCurrent()
        labelGate.open()
        try await eventually { model.labelsReturned == model.inputs.count }
        #expect(!tree.nodes.contains(where: { $0.isSuggested }))
    }

    @Test("Existing duplicate labels are repaired without replacing Nodes", arguments: [false, true])
    func repairsExistingLabel(conversation: Bool) async throws {
        let source = concept(word: "Prudence", meaning: "Practical judgment in choosing how to act.")
        let scope = conversation ? UUID() : nil
        let seeds: [LocalInsightTreeSeed] = conversation ? [LocalInsightTreeSeed(
            id: UUID(), label: "Prudence", summary: "Old same-subject definition",
            embedding: computeEmbedding(for: "\(source.word). \(source.meaning)"), createdAt: Date()
        )] : []
        let initial = InsightTreeViewModel(insights: [source], localSeedAnchors: seeds, midpointStoreScope: scope)
        let originalNode = try #require(initial.nodes.first)
        if !conversation {
            let key = "aquinas.insight-tree.cluster-labels.v1"
            var stored = InsightTreeLocalStateStore.load([String: String].self, key: key) ?? [:]
            stored[originalNode.id.uuidString] = "The PRUDENCE!"
            InsightTreeLocalStateStore.save(stored, key: key)
            let definitionsKey = "aquinas.insight-tree.cluster-definitions.v1"
            var definitions = InsightTreeLocalStateStore.load([String: String].self, key: definitionsKey) ?? [:]
            definitions[originalNode.id.uuidString] = "Old same-subject definition"
            InsightTreeLocalStateStore.save(definitions, key: definitionsKey)
        }
        let queue = ModelTaskQueue()
        let gate = LabelGate()
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 0)) { await gate.wait() }
        let model = LabelRecordingModel()
        model.label = "Moral Virtues"
        let tree = InsightTreeViewModel(insights: [source], model: model, modelTasks: queue,
                                        localSeedAnchors: seeds, midpointStoreScope: scope)
        #expect(queue.upcomingTasks.count == 1)
        #expect(tree.nodes.first?.id == originalNode.id)
        #expect(tree.nodes.first?.conceptLabel == "Exploring Prudence")
        #expect(tree.nodes.first?.definition == "")
        tree.selectNode(try #require(tree.nodes.first))
        gate.open()
        try await eventually { !queue.isBusy }
        #expect(model.events == ["label", "definition"])
        #expect(tree.nodes.first?.id == originalNode.id)
        #expect(tree.nodes.first?.position == originalNode.position)
        #expect(tree.nodes.first?.insights.map(\.id) == [source.id])
        #expect(tree.nodes.first?.conceptLabel == "Moral Virtues")
        #expect(tree.selectedNode?.conceptLabel == "Moral Virtues")
        #expect(tree.nodes.first?.definition == "Generated definition")
        let reopened = InsightTreeViewModel(insights: [source], model: model, modelTasks: queue,
                                            localSeedAnchors: seeds, midpointStoreScope: scope)
        #expect(reopened.nodes.first?.conceptLabel == "Moral Virtues")
        #expect(reopened.nodes.first?.definition == "Generated definition")
        #expect(!queue.isBusy)
    }

    @Test("Rejected duplicate labels never trigger definitions")
    func duplicateResult() async throws {
        let queue = ModelTaskQueue()
        let model = LabelRecordingModel()
        model.label = "The Prudence"
        let tree = makeTree([concept(word: "Prudence")], model: model, queue: queue)
        try await eventually { !queue.isBusy }
        #expect(model.events == ["label"])
        #expect(tree.nodes.first?.conceptLabel == "Exploring Prudence")
        #expect(tree.nodes.first?.definition == "")
    }

    private func concept(word: String = "Subject", meaning: String = "Meaning") -> ConceptDefinition {
        ConceptDefinition(word: word, partOfSpeech: "", pronunciation: "", meaning: meaning, example: "")
    }

    private func makeTree(_ insights: [ConceptDefinition], model: LabelRecordingModel,
                          queue: ModelTaskQueue, scope: UUID? = nil) -> InsightTreeViewModel {
        InsightTreeViewModel(insights: insights, showsAllClusterInsights: scope == nil,
                             model: model, modelTasks: queue,
                             modelTaskOriginPage: scope == nil ? .insights : .conversation,
                             midpointStoreScope: scope)
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for queue state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class LabelGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor LabelLoadingDriver: ModelRuntimeDriver {
    nonisolated let supportsUnloading = true
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func loadModelWeights() async throws {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { continuation?.resume(); continuation = nil }
    func unloadModelWeights() async {}
}

@MainActor
private final class LabelRecordingModel: AquinasModel {
    var events: [String] = []
    var inputs: [[String]] = []
    var label = "Generated subject"
    var labelGate: LabelGate?
    var definitionGate: LabelGate?
    var labelsReturned = 0
    var definitionsReturned = 0
    func labelSubject(forTitles titles: [String]) async throws -> String {
        events.append("label")
        inputs.append(titles)
        await labelGate?.wait()
        labelsReturned += 1
        return label
    }
    func defineTerm(_ term: String, in context: ConversationContext) async throws -> ConceptDefinition {
        events.append("definition")
        await definitionGate?.wait()
        definitionsReturned += 1
        return ConceptDefinition(word: term, partOfSpeech: "", pronunciation: "",
                                 meaning: "Generated definition", example: "")
    }
    func respond(to context: ConversationContext) async -> ModelResponse { ModelResponse(text: "Answer") }
    func compact(_ context: ConversationContext) async -> String { "" }
    func blendConceptCandidates(_ concepts: [ConceptDefinition], weights: [Double]) async throws -> [ConceptDefinition] { [] }
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] { [] }
}
