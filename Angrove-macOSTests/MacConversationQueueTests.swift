import AppKit
import SwiftUI
import Observation
import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacConversationQueueTests {
    @Test func answerUpdateSignalWaitsForCompletionAndIncludesInsightQuestionsAndRegeneration() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        #expect(conversation.completedResponseCount == 0)
        #expect(conversation.send("First", runtime: runtime))
        try await wait { await model.requestCount == 1 }
        #expect(conversation.completedResponseCount == 0)
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(conversation.completedResponseCount == 1)

        conversation.attachQuote(ConceptDefinition(word: "Prudence", partOfSpeech: "", pronunciation: "",
            meaning: "Practical wisdom", example: ""))
        #expect(conversation.completedResponseCount == 1)
        #expect(conversation.send("How does this guide action?", runtime: runtime))
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(conversation.completedResponseCount == 2)

        conversation.regenerate(transcriptIndex: 3, runtime: runtime)
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(conversation.completedResponseCount == 3)
    }

    @Test func askAttachesInsightToTheQuestionAndKeepsItInModelContext() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        let insight = ConceptDefinition(word: "Prudence", partOfSpeech: "", pronunciation: "",
            meaning: "Practical wisdom", example: "")
        conversation.attachQuote(insight)
        let request = conversation.quoteRequest
        conversation.attachQuote(insight)
        #expect(conversation.quoteRequest == request + 1)
        #expect(conversation.quote == insight)
        #expect(conversation.activeBranch?.branchContextConcept == insight)
        conversation.removeQuote()
        #expect(conversation.quote == nil)
        #expect(conversation.activeBranch?.branchContextConcept == nil)
        conversation.attachQuote(insight)
        #expect(conversation.transcript.isEmpty)
        #expect(conversation.send("How does this guide action?", runtime: runtime))
        #expect(conversation.quote == nil)
        #expect(conversation.transcript.first == .user("How does this guide action?", insight, []))
        try await wait { await model.requestCount == 1 }
        #expect(await model.contexts.first?.transcript.last == .user("How does this guide action?", insight, []))
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        conversation.attachQuote(insight)
        #expect(conversation.activeBranch?.attachedConcept == insight)
        #expect(conversation.send("What about this case?", runtime: runtime))
        #expect(conversation.activeBranch?.attachedConcept == nil)
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(await model.contexts.last?.transcript.last == .user("What about this case?", insight, []))
    }

    @Test func openingDefinitionLeavesTranscriptAndTreeUnchangedUntilBookmarked() async throws {
        let runtime = MacApplicationRuntime(testModel: ScriptedMacConversationModel(), queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        conversation.branches[0].topQuestionSubmitted = true
        conversation.branches[0].topQuestionText = "What guides judgment?"
        let answer = "Prudence guides practical judgment."
        conversation.branches[0].activeChatBlocks = [.text(answer)]
        let history = conversation.transcript
        let existingConcepts = conversation.concepts

        conversation.define("Prudence", source: answer, runtime: runtime)
        try await wait { conversation.selectedDefinition != nil }
        let definition = try #require(conversation.selectedDefinition)
        #expect(conversation.transcript == history)
        #expect(conversation.concepts == existingConcepts)
        #expect(!conversation.savedIDs.contains(definition.id))

        conversation.toggleBookmark(definition)
        #expect(conversation.savedIDs.contains(definition.id))
        #expect(conversation.concepts.contains(definition))
        #expect(conversation.transcript == history)
        conversation.toggleBookmark(definition)
        #expect(!conversation.savedIDs.contains(definition.id))
        #expect(conversation.concepts == existingConcepts)
        #expect(conversation.transcript == history)
    }

    @Test func reopenedTreeExcludesUnbookmarkedInlineAndQuotedDefinitions() throws {
        let inline = ConceptDefinition(word: "Prudence", partOfSpeech: "", pronunciation: "", meaning: "Practical judgment.", example: "")
        let quoted = ConceptDefinition(word: "Justice", partOfSpeech: "", pronunciation: "", meaning: "Giving each their due.", example: "")
        let saved = ConceptDefinition(word: "Fortitude", partOfSpeech: "", pronunciation: "", meaning: "Courage in difficulty.", example: "")
        var branch = ChatBranch(startingConcept: quoted)
        branch.activeChatBlocks = [.text(InlineInsightMarkup.marker(for: inline))]
        // Exercise persisted markup, including records made by the former definition flow.
        let restored = try JSONDecoder().decode(ChatBranch.self, from: JSONEncoder().encode(branch))
        #expect(ChatBranch.resolvedConversationInsights(in: [restored], savedInsights: [], manuallySavedIDs: []).isEmpty)
        #expect(ChatBranch.resolvedConversationInsights(in: [restored], savedInsights: [inline, saved], manuallySavedIDs: [saved.id]) == [inline, saved])
        #expect(ChatBranch.resolvedConversationInsights(in: [restored], savedInsights: [saved], manuallySavedIDs: [saved.id]) == [saved])
    }

    @Test func designPreviewNeverReusesASavedTreeIdentity() {
        let saved = UUID()
        let preview = MacWorkspaceIdentity.initialConversationID(isPreview: true, savedID: saved)
        #expect(preview != saved)
        #expect(MacWorkspaceIdentity.initialConversationID(isPreview: true, savedID: saved) != preview)
        #expect(MacWorkspaceIdentity.initialConversationID(isPreview: false, savedID: saved) == saved)
    }

    @Test func waitingQuestionUsesTheCompletedAnswer() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        #expect(conversation.send("First", runtime: runtime))
        try await wait { await model.requestCount == 1 }
        #expect(conversation.send("Second", runtime: runtime))
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        let contexts = await model.contexts
        #expect(contexts.count == 2)
        #expect(contexts[1].transcript.contains(.text("Test answer 1")))
        #expect(contexts[1].transcript.last == .user("Second", nil, []))
    }

    @Test func removingWaitingQuestionRestoresItsDraft() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        conversation.send("First", runtime: runtime)
        try await wait { await model.requestCount == 1 }
        conversation.send("Keep this draft", runtime: runtime)
        let waiting = try #require(runtime.modelTasks.upcomingTasks.first)
        runtime.modelTasks.removeUpcoming(id: waiting.id)
        #expect(conversation.restoredDraft == "Keep this draft")
        #expect(conversation.activeBranch?.activeChatBlocks.count == 1)
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(await model.requestCount == 1)
    }

    @Test func stoppedResponseCannotReturnAfterClear() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        conversation.send("First", runtime: runtime)
        try await wait { await model.requestCount == 1 }
        let previousBranch = conversation.selectedBranch
        conversation.clear(runtime: runtime)
        await model.finishFirst()
        try await wait { await model.hasReturned }
        #expect(conversation.selectedBranch != previousBranch)
        #expect(conversation.transcript.isEmpty)
        #expect(conversation.pendingResponses.isEmpty)
        #expect(conversation.completedResponseCount == 0)
    }

    @Test func completedAnswerRevealsOnceAndRegenerationStartsANewReveal() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        #expect(conversation.isComposerReady)
        conversation.send("First", runtime: runtime)
        try await wait { await model.requestCount == 1 }
        let firstRun = try #require(conversation.responseRun(transcriptIndex: 1))
        #expect(conversation.shouldRevealResponse(transcriptIndex: 1))
        #expect(!conversation.isComposerReady)
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(conversation.shouldRevealResponse(transcriptIndex: 1))
        #expect(!conversation.usesIncrementalResponse(transcriptIndex: 1))
        #expect(!conversation.isComposerReady)
        conversation.finishResponseBodyReveal(run: firstRun)
        #expect(conversation.isComposerReady)
        #expect(conversation.shouldRevealResponse(transcriptIndex: 1))
        conversation.finishResponseReveal(run: firstRun)
        #expect(!conversation.shouldRevealResponse(transcriptIndex: 1))
        conversation.regenerate(transcriptIndex: 1, runtime: runtime)
        let nextRun = try #require(conversation.responseRun(transcriptIndex: 1))
        #expect(nextRun != firstRun)
        #expect(conversation.shouldRevealResponse(transcriptIndex: 1))
        #expect(!conversation.isComposerReady)
        // A late callback from the old renderer must not finish the new reveal.
        conversation.finishResponseBodyReveal(run: firstRun)
        conversation.finishResponseReveal(run: firstRun)
        #expect(conversation.shouldRevealResponse(transcriptIndex: 1))
        #expect(!conversation.isComposerReady)
        try await wait { runtime.modelTasks.currentTask == nil }
    }

    @Test func liveFormatterSurvivesCompletionAndRestoredAnswersDoNotAnimate() async throws {
        let model = ScriptedMacConversationModel(streams: true)
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        conversation.send("First", runtime: runtime)
        try await wait { conversation.usesIncrementalResponse(transcriptIndex: 1) }
        #expect(conversation.isPending(transcriptIndex: 1))
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(conversation.usesIncrementalResponse(transcriptIndex: 1))
        let restored = MacConversationState()
        restored.branches = conversation.branches
        restored.selectedBranch = conversation.selectedBranch
        #expect(!restored.shouldRevealResponse(transcriptIndex: 1))
        #expect(!restored.usesIncrementalResponse(transcriptIndex: 1))
        #expect(restored.isComposerReady)
    }

    @Test func generationProgressAndSourcesSurviveCompletionAndReopening() async throws {
        let model = ScriptedMacConversationModel(reportsProgress: true)
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        #expect(conversation.send("First", runtime: runtime))
        try await wait { conversation.liveThought(transcriptIndex: 1) != nil }
        #expect(await model.progressWasRequested)
        #expect(!conversation.isQueued(transcriptIndex: 1))
        #expect(conversation.summary(transcriptIndex: 1) == ["Approach: Check the retrieved passage."])
        #expect(conversation.sources(transcriptIndex: 1).first?.passage == "Original retrieved passage.")
        #expect(conversation.liveThought(transcriptIndex: 1) == "Actual model thought.")
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        #expect(conversation.summary(transcriptIndex: 1).contains("Actual model thought."))
        let restored = MacConversationState()
        restored.branches = conversation.branches
        restored.selectedBranch = conversation.selectedBranch
        #expect(restored.presentation(transcriptIndex: 1)?.showsThinking == true)
        #expect(restored.summary(transcriptIndex: 1).contains("Actual model thought."))
        #expect(restored.sources(transcriptIndex: 1).first?.passage == "Original retrieved passage.")
        #expect(restored.thinkingDuration(transcriptIndex: 1) != nil)
    }

    @Test func emptyContextIsZeroAndCompactionPreservesVisibleHistory() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        #expect(conversation.contextTokenCount == 0)
        #expect(!conversation.canCompactContext)
        conversation.branches[0].topQuestionText = "A question about the origins of an idea"
        conversation.branches[0].topQuestionSubmitted = true
        conversation.branches[0].activeChatBlocks = [.text(String(repeating: "An established distinction. ", count: 100))]
        let history = conversation.transcript
        let before = conversation.contextTokenCount
        #expect(conversation.canCompactContext)
        #expect(await conversation.compact(runtime: runtime))
        #expect(conversation.transcript == history)
        #expect(conversation.contextTokenCount < before)
        #expect(!conversation.canCompactContext)
        #expect(conversation.activeBranch?.compactedThroughBlockCount == 1)
        conversation.send("Continue from the checkpoint", runtime: runtime)
        try await wait { await model.requestCount == 1 }
        await model.finishFirst()
        try await wait { runtime.modelTasks.currentTask == nil }
        let request = try #require(await model.contexts.first)
        #expect(request.compactedContext == "Test summary 1")
        #expect(request.transcript == [.user("Continue from the checkpoint", nil, [])])
    }

    @Test func repeatCompactionOnlyProcessesNewTurns() async throws {
        let model = ScriptedMacConversationModel()
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        conversation.branches[0].topQuestionSubmitted = true
        conversation.branches[0].topQuestionText = "First question"
        conversation.branches[0].activeChatBlocks = [.text("First answer")]
        #expect(await conversation.compact(runtime: runtime))
        conversation.branches[0].activeChatBlocks += [.user("Second question", nil, []), .text("Second answer")]
        #expect(await conversation.compact(runtime: runtime))
        let request = try #require(await model.compactContexts.last)
        #expect(request.compactedContext == "Test summary 1")
        #expect(request.transcript == [.user("Second question", nil, []), .text("Second answer")])
        #expect(conversation.activeBranch?.compactedThroughBlockCount == 3)
    }

    @Test func clearDuringCompactionRejectsTheLateCheckpoint() async throws {
        let model = ScriptedMacConversationModel(delaysCompaction: true)
        let runtime = MacApplicationRuntime(testModel: model, queue: ModelTaskQueue())
        let conversation = MacConversationState()
        conversation.configure(preview: true)
        conversation.branches[0].topQuestionSubmitted = true
        conversation.branches[0].topQuestionText = "First question"
        conversation.branches[0].activeChatBlocks = [.text("First answer")]
        let task = Task { await conversation.compact(runtime: runtime) }
        try await wait { await model.compactContexts.count == 1 }
        conversation.clear(runtime: runtime)
        await model.finishCompaction()
        #expect(await task.value == false)
        try await wait { await model.compactionHasReturned }
        #expect(conversation.activeBranch?.compactedContext == nil)
        #expect(conversation.contextTokenCount == 0)
        #expect(conversation.transcript.isEmpty)
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await condition())
    }
}

/// Delayed answers exist only in this test target; no model weights or personal stores are used.
private actor ScriptedMacConversationModel: AngroveModel {
    private let streams: Bool
    private let reportsProgress: Bool
    var progressWasRequested = false
    init(streams: Bool = false, delaysCompaction: Bool = false, reportsProgress: Bool = false) {
        self.reportsProgress = reportsProgress
        self.streams = streams
        self.delaysCompaction = delaysCompaction
    }
    var contexts: [ConversationContext] = []
    var requestCount: Int { contexts.count }
    var hasReturned = false
    var compactContexts: [ConversationContext] = []
    var compactionHasReturned = false
    let delaysCompaction: Bool
    private var compactGate: CheckedContinuation<Void, Never>?
    func finishCompaction() { compactGate?.resume(); compactGate = nil }
    private var firstGate: CheckedContinuation<Void, Never>?
    func finishFirst() { firstGate?.resume(); firstGate = nil }
    func respond(to context: ConversationContext) async -> ModelResponse {
        contexts.append(context)
        let number = contexts.count
        if number == 1 { await withCheckedContinuation { firstGate = $0 } }
        hasReturned = true
        return ModelResponse(text: "Test answer \(number)")
    }
    func respond(to context: ConversationContext, thinkingEnabled: Bool,
                 onUpdate: @escaping (ModelResponseUpdate) -> Void) async -> ModelResponse {
        progressWasRequested = thinkingEnabled
        if reportsProgress && thinkingEnabled {
            onUpdate(.generationStarted)
            onUpdate(.thinkingSummary(["Approach: Check the retrieved passage."]))
            onUpdate(.groundingSources([GroundingSourceSummary(id: "test-source", title: "Test source", sourceName: "Test edition", passage: "Original retrieved passage.")]))
            onUpdate(.thought("Actual model thought."))
        }
        if streams { onUpdate(.responseText("Test")) }
        let response = await respond(to: context)
        if reportsProgress {
            return ModelResponse(text: response.text, thinkingSummary: ["Approach: Check the retrieved passage.", "Actual model thought."])
        }
        return response
    }
    func compact(_ context: ConversationContext) async -> String {
        compactContexts.append(context)
        if delaysCompaction { await withCheckedContinuation { compactGate = $0 } }
        compactionHasReturned = true
        return "Test summary \(compactContexts.count)"
    }
    func defineTerm(_ term: String, in context: ConversationContext) async throws -> ConceptDefinition {
        ConceptDefinition(word: term, partOfSpeech: "", pronunciation: "", meaning: "Test contextual definition.", example: "")
    }
    func labelSubject(forTitles titles: [String]) async throws -> String { throw AngroveModelActionError.unavailable }
    func blendConceptCandidates(_ concepts: [ConceptDefinition], weights: [Double]) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
}


@Suite(.serialized) @MainActor
struct MacResponseRevealTests {
    @Observable final class State {
        var text = "Prudence"
        var receiving = true
        var visible = 0
        var finished = false
        var reduceMotion: Bool?
    }
    struct Sample: View {
        let state: State
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            StreamingMessageView(fullText: state.text, shouldStream: true,
                isReceivingStream: state.receiving, usesIncrementalStream: true,
                showsResponseActions: false,
                onBodyRevealComplete: { state.finished = true },
                onRevealedWordCountChange: { state.visible = $0 })
                .onAppear { state.reduceMotion = reduceMotion }
        }
    }

    @Test func finalBatchContinuesRevealingBeforeReportingCompletion() async throws {
        let state = State()
        let host = NSHostingView(rootView: Sample(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let reduceMotion = try #require(state.reduceMotion)
        #expect(state.visible == 1)
        #expect(!state.finished)
        state.text = Array(repeating: "Prudence", count: 200).joined(separator: " ")
        state.receiving = false
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.visible > 1)
        if !reduceMotion {
            #expect(state.visible < 200)
            #expect(!state.finished)
        }
        // Completion includes a final animation callback. Wait for the observed
        // result rather than assuming the main actor runs it at an exact deadline.
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !state.finished && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.visible == 200)
        #expect(state.finished)
    }
}
