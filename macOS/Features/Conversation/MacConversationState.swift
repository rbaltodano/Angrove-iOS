import Foundation
import Combine
import Observation
import SwiftUI

@MainActor @Observable final class MacConversationState {
    var id = UUID()
    var title = "New Conversation"
    var studyTopicID: UUID?
    let scroll = MacConversationScrollState()
    private var hasCustomTitle = false
    private(set) var isDeleted = false
    @ObservationIgnored private var sidebarSubscriptions: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: .macConversationMetadataChanged)
            .sink { [weak self] notification in
                if let conversation = notification.object as? InquiryConversation {
                    self?.applySidebarMetadata(conversation)
                }
            }
            .store(in: &sidebarSubscriptions)
        NotificationCenter.default.publisher(for: .macConversationDeleted)
            .sink { [weak self] notification in
                if let self, notification.object as? UUID == self.id { self.markDeleted() }
            }
            .store(in: &sidebarSubscriptions)
    }

    func applySidebarMetadata(_ conversation: InquiryConversation) {
        guard conversation.id == id, !isDeleted else { return }
        if title != conversation.title {
            title = conversation.title
            hasCustomTitle = true
        }
        studyTopicID = conversation.studyTopicID
    }

    func markDeleted() { isDeleted = true }

    func rename(to value: String) {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        title = name
        hasCustomTitle = true
        persistConversation()
    }

    func assignTopic(_ topicID: UUID?) {
        studyTopicID = topicID
        persistConversation()
    }
    var selectedDefinition: ConceptDefinition?
    var definingTerms: Set<String> = []
    var concepts: [ConceptDefinition] = [] {
        didSet {
            if hasConfigured, oldValue != concepts { insightUpdateCount += 1 }
        }
    }
    /// Restoring saved Insights establishes the baseline; only subsequent edits notify the dock.
    private(set) var insightUpdateCount = 0
    @ObservationIgnored private var hasConfigured = false
    var savedIDs: Set<UUID> = []
    var promotedIDs: [UUID] = []
    var connectionConcepts: [ConceptDefinition] = []
    var quote: ConceptDefinition?
    var quoteRequest = 0
    /// Images chosen for the next question; cleared once it is submitted.
    var uploads: [UploadedFile] = []

    func attach(_ files: [UploadedFile]) {
        uploads.append(contentsOf: files)
        quoteRequest += 1
    }
    func removeUpload(_ id: UUID) { uploads.removeAll { $0.id == id } }

    func attachQuote(_ concept: ConceptDefinition) {
        quote = concept
        if !isGlobalTree, let index = branches.firstIndex(where: { $0.id == selectedBranch }) {
            // The Mac composer holds one quote, so a new quote replaces the current one.
            if !branches[index].topQuestionSubmitted { branches[index].branchContextConcepts = [] }
            branches[index].attachedConcepts = []
            branches[index].attachQuote(concept)
            persistConversation()
        }
        quoteRequest += 1
    }
    func removeQuote() {
        quote = nil
        if !isGlobalTree, let index = branches.firstIndex(where: { $0.id == selectedBranch }) {
            if !branches[index].topQuestionSubmitted { branches[index].branchContextConcepts = [] }
            branches[index].attachedConcepts = []
            persistConversation()
        }
    }
    var selectedBranch = UUID()
    var branches: [ChatBranch] = []
    var errorMessage: String?
    var showsError = false
    var isPreview = false
    /// Off for Worktree conversation windows, which live on their canvas rather than in the sidebar.
    var savesConversation = true
    private var isGlobalTree = false

    func configure(preview: Bool, conversationID: UUID? = nil, global: Bool = false) {
        guard branches.isEmpty else { return }
        defer { hasConfigured = true }
        isPreview = preview
        isGlobalTree = global
        if let conversationID { id = conversationID }
        let branch = ChatBranch(startingConcept: nil)
        selectedBranch = branch.id
        branches = [branch]
        #if DEBUG
        if preview { concepts = MacTreePreviewData.concepts; return }
        #endif
        let library = InsightLibraryStore.load()
        savedIDs = Set(library.map(\.id))
        if let restored = CurrentConversationsStore.load()?.conversations.first(where: { $0.id == id }) {
            title = restored.title
            studyTopicID = restored.studyTopicID
            let question = restored.branches.first?.topQuestionText ?? ""
            hasCustomTitle = title != "New Conversation" && title != String(question.prefix(80))
                && title != Self.automaticTitle(for: question)
            branches = restored.branches
            selectedBranch = branches.first?.id ?? branch.id
            promotedIDs = restored.promotedInsightIDs
        }
        quote = activeBranch?.topQuestionSubmitted == false
            ? activeBranch?.branchContextConcept ?? activeBranch?.startingConcept
            : activeBranch?.attachedConcept
        let members = ConversationInsightMembershipStore.insightIDs(for: id)
        concepts = global ? GlobalInsightTreeStore.load() : ChatBranch.resolvedConversationInsights(in: branches, savedInsights: library, manuallySavedIDs: members)
    }
    func toggleBookmark(_ concept: ConceptDefinition) {
        if savedIDs.contains(concept.id) {
            savedIDs.remove(concept.id)
            if !isGlobalTree {
                concepts.removeAll { $0.id == concept.id }
                if !isPreview { ConversationInsightMembershipStore.remove(insightID: concept.id, from: id) }
            }
        }
        else { savedIDs.insert(concept.id); if !isPreview { ConversationInsightMembershipStore.add(insightID: concept.id, to: id) }; if !concepts.contains(where: { $0.id == concept.id }) { concepts.append(concept) } }
        persistInsights()
    }
    func bookmark(_ values: [ConceptDefinition]) {
        for concept in values {
            savedIDs.insert(concept.id)
            if !isPreview { ConversationInsightMembershipStore.add(insightID: concept.id, to: id) }
            if !concepts.contains(where: { $0.id == concept.id }) { concepts.append(concept) }
        }
        persistInsights()
    }
    func remove(_ concept: ConceptDefinition) {
        concepts.removeAll { $0.id == concept.id }
        savedIDs.remove(concept.id)
        persistInsights()
    }
    func restore(_ concept: ConceptDefinition) {
        if !concepts.contains(where: { $0.id == concept.id }) { concepts.append(concept) }
        persistInsights()
    }
    func persistInsights() {
        guard !isPreview, !isDeleted else { return }
        let retained = InsightLibraryStore.load().filter { savedIDs.contains($0.id) }
        InsightLibraryStore.save(retained + concepts.filter { savedIDs.contains($0.id) })
    }
    func fork(_ concept: ConceptDefinition) {
        let branch = ChatBranch(startingConcept: concept, parentBranchID: selectedBranch)
        branches.append(branch)
        selectedBranch = branch.id
        attachQuote(concept)
        persistConversation()
    }
    var activeBranch: ChatBranch? { branches.first { $0.id == selectedBranch } }
    var transcript: [ChatBlock] {
        guard let branch = activeBranch, branch.topQuestionSubmitted else { return [] }
        return [.user(branch.topQuestionText, branch.branchContextConcepts, branch.topQuestionUploads)] + branch.activeChatBlocks
    }
    /// Mac transcript indices include the initial question; ChatBranch indices do not.
    func feedbackReport(transcriptIndex: Int) -> ResponseFeedbackReport? {
        guard let branch = activeBranch, branch.topQuestionSubmitted,
              transcriptIndex == branch.activeChatBlocks.count,
              let last = branch.activeChatBlocks.last, case .text(let text) = last,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text != questionCanceledResponseText, !isPending(transcriptIndex: transcriptIndex) else { return nil }
        return branch.feedbackReport(flaggedResponseIndex: transcriptIndex - 1)
    }

    var pendingResponses: Set<String> = []
    private(set) var completedResponseCount = 0
    var startedResponses: Set<String> = []
    var restoredDraft: String?
    private var isCompactingContext = false
    private var responseRuns: [String: UUID] = [:]
    private var streamedResponseRuns: Set<UUID> = []
    private var revealedResponseRuns: Set<UUID> = []
    private var bodyRevealedResponseRuns: Set<UUID> = []
    var responseSources: [String: [GroundingSourceSummary]] = [:]
    var responseSummaries: [String: [String]] = [:]
    private var responseThoughts: [String: String] = [:]
    private var responseStartedAt: [String: Date] = [:]
    private var responseThinkingDurations: [String: TimeInterval] = [:]

    func send(_ prompt: String, runtime: MacApplicationRuntime) -> Bool {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDeleted, !question.isEmpty, let index = branches.firstIndex(where: { $0.id == selectedBranch }) else { return false }
        guard runtime.modelIsAvailable else { report(UnavailableAngroveModel.unavailableMessage); return false }
        guard !PersonalDataProtection.isBlocked else { report("Saved data could not be verified. Your question has been kept in the editor."); return false }
        var branch = branches[index]
        if !branch.topQuestionSubmitted, !isPreview { MacDailyPrompt.markAnswered(branch) }
        if !branch.topQuestionSubmitted {
            branch.branchContextConcepts = quote.map { [$0] } ?? []
            branch.topQuestionText = question
            branch.topQuestionUploads = uploads
            branch.topQuestionSubmitted = true
        } else { branch.activeChatBlocks.append(.user(question, quote.map { [$0] } ?? [], uploads)) }
        let responseIndex = branch.activeChatBlocks.count
        branch.attachedConcepts = []
        branch.activeChatBlocks.append(.text(""))
        branches[index] = branch
        quote = nil
        uploads = []
        let submitted = connectionConcepts
        connectionConcepts = []
        enqueueResponse(branch: branch, responseIndex: responseIndex, question: question, submittedConnectionConcepts: submitted, runtime: runtime)
        return true
    }
    func regenerate(transcriptIndex: Int, runtime: MacApplicationRuntime) {
        guard runtime.modelIsAvailable, let i = branches.firstIndex(where: { $0.id == selectedBranch }) else { return }
        let slot = transcriptIndex - 1
        guard branches[i].activeChatBlocks.indices.contains(slot), case .text(let old) = branches[i].activeChatBlocks[slot], !isPending(transcriptIndex: transcriptIndex) else { return }
        let question = branches[i].activeChatBlocks.prefix(slot).reversed().compactMap { block -> String? in if case .user(let value, _, _) = block { return value }; return nil }.first ?? branches[i].topQuestionText
        branches[i].activeChatBlocks[slot] = .text("")
        branches[i].removeResponsePresentation(at: slot)
        enqueueResponse(branch: branches[i], responseIndex: slot, question: question, submittedConnectionConcepts: [], runtime: runtime, originalResponse: old)
    }
    private func enqueueResponse(branch: ChatBranch, responseIndex: Int, question: String,
                                 submittedConnectionConcepts: [ConceptDefinition], runtime: MacApplicationRuntime,
                                 originalResponse: String? = nil) {
        let branchID = branch.id
        let key = "\(branchID):\(responseIndex)"
        let runID = UUID()
        responseRuns[key] = runID
        pendingResponses.insert(key)
        responseSummaries.removeValue(forKey: key)
        responseSources.removeValue(forKey: key)
        responseThoughts.removeValue(forKey: key)
        responseStartedAt.removeValue(forKey: key)
        responseThinkingDurations.removeValue(forKey: key)
        persistConversation()
        let model = runtime.model
        runtime.modelTasks.enqueue(kind: .userQuestion(branchID: branchID, responseIndex: responseIndex),
                                   originPage: .conversation, conversationID: id,
                                   onStart: { [self] in startedResponses.insert(key) },
                                   onCancel: { [self] in
                                       guard responseRuns[key] == runID else { return }
                                       revealedResponseRuns.insert(runID)
                                       pendingResponses.remove(key)
                                       if let originalResponse { setResponse(originalResponse, branchID: branchID, index: responseIndex) }
                                       else if startedResponses.contains(key) { setResponse(questionCanceledResponseText, branchID: branchID, index: responseIndex) }
                                       else if let i = branches.firstIndex(where: { $0.id == branchID }), responseIndex == branches[i].activeChatBlocks.count - 1 {
                                           branches[i].activeChatBlocks.removeLast()
                                           if case .user(let value, let quoted, _) = branches[i].activeChatBlocks.last, value == question {
                                               branches[i].activeChatBlocks.removeLast()
                                               if selectedBranch == branchID { quote = quoted.first; restoredDraft = question }
                                           } else if responseIndex == 0 {
                                               branches[i].topQuestionSubmitted = false
                                               if selectedBranch == branchID { restoredDraft = question }
                                           }
                                       } else { setResponse("Response stopped.", branchID: branchID, index: responseIndex) }
                                       startedResponses.remove(key)
                                       persistConversation()
                                   }) { [self] in
            guard var latestBranch = branches.first(where: { $0.id == branchID }), pendingResponses.contains(key) else { return }
            latestBranch.activeChatBlocks = Array(latestBranch.activeChatBlocks.prefix(responseIndex))
            var context = modelContext(for: latestBranch, personality: runtime.modelTasks.personality)
            if submittedConnectionConcepts.count >= 2,
               let userIndex = context.transcript.lastIndex(where: { if case .user = $0 { return true }; return false }),
               case .user(let question, let concept, let uploads) = context.transcript[userIndex] {
                var transcript = context.transcript
                transcript[userIndex] = .user(ConversationPromptMarkup.connectionInquiryPrompt(concepts: submittedConnectionConcepts, question: question), concept, uploads)
                context = ConversationContext(compactedContext: context.compactedContext, transcript: transcript, personality: context.personality)
            }
            if AngroveContextBudget.shouldCompact(context),
               let split = AngroveContextBudget.historyAndLatestTurn(in: context) {
                let summary = await model.compact(split.history).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled, !isDeleted, responseRuns[key] == runID,
                      let index = branches.firstIndex(where: { $0.id == branchID }) else { return }
                if !summary.isEmpty, summary != split.history.compactedContext {
                    context = ConversationContext(compactedContext: summary, transcript: split.latestTurn, personality: context.personality)
                    branches[index].compactedContext = summary
                    branches[index].compactedThroughBlockCount = max(responseIndex - 1, 0)
                    persistConversation()
                }
            }
            let response = await model.respond(to: context, thinkingEnabled: true) { update in
                Task { @MainActor [self] in
                    guard self.responseRuns[key] == runID, self.pendingResponses.contains(key) else { return }
                    switch update {
                    case .generationStarted:
                        self.responseStartedAt[key] = Date()
                    case .thought(let thought):
                        self.responseThoughts[key] = ModelThought.currentLine(in: thought)
                    case .responseText(let text):
                        if !text.isEmpty {
                            self.streamedResponseRuns.insert(runID)
                            if self.responseThinkingDurations[key] == nil, let started = self.responseStartedAt[key] {
                                self.responseThinkingDurations[key] = Date().timeIntervalSince(started)
                            }
                            self.responseThoughts.removeValue(forKey: key)
                        }
                        self.setResponse(text, branchID: branchID, index: responseIndex)
                    case .thinkingSummary(let lines): self.responseSummaries[key] = lines
                    case .groundingSources(let sources): self.responseSources[key] = sources
                    }
                }
            }
            guard !isDeleted, !Task.isCancelled, responseRuns[key] == runID, pendingResponses.contains(key) else { return }
            if response.outcome == .failed { runtime.modelTasks.reportCurrentFailure() }
            pendingResponses.remove(key)
            startedResponses.remove(key)
            responseSummaries[key] = response.thinkingSummary
            responseThoughts.removeValue(forKey: key)
            setResponse(response.annotatedText, branchID: branchID, index: responseIndex)
            let presentation = ResponsePresentationMetadata(responseIndex: responseIndex, showsThinking: true,
                                                           thinkingSummary: response.thinkingSummary,
                                                           thinkingDurationSeconds: responseThinkingDurations[key] ?? responseStartedAt[key].map { Date().timeIntervalSince($0) },
                                                           groundingSources: responseSources[key], evidenceBasis: response.evidenceBasis, outcome: response.outcome)
            if let i = branches.firstIndex(where: { $0.id == branchID }) { branches[i].setResponsePresentation(presentation) }
            persistConversation()
            if !isPreview && savesConversation {
                InquiryPersistenceStore.completeDetachedResponse(branchID: branchID, conversationID: id,
                    responseIndex: responseIndex, annotatedText: response.annotatedText, presentation: presentation)
            }
            if response.outcome == .completed { completedResponseCount += 1 }
            if response.outcome == .completed, response.evidenceBasis?.canSeedInsightTree == true,
               !LiteRTAngroveModel.isCorpusScopeAbstention(response.text) {
                enqueueSeed(question: question, answer: response.text, branchID: branchID, responseIndex: responseIndex, runtime: runtime)
            }
        }
    }
    private func setResponse(_ text: String, branchID: UUID, index: Int) {
        guard let i = branches.firstIndex(where: { $0.id == branchID }), branches[i].activeChatBlocks.indices.contains(index) else { return }
        branches[i].activeChatBlocks[index] = .text(text)
    }
    private func persistConversation() {
        guard !isPreview, !isDeleted, savesConversation else { return }
        var snapshot = CurrentConversationsStore.load() ?? InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
        if !hasCustomTitle {
            title = Self.automaticTitle(for: branches.first?.topQuestionText ?? "") ?? "New Conversation"
        }
        var conversation = snapshot.conversations.first(where: { $0.id == id }) ?? InquiryConversation(id: id)
        conversation.title = title
        conversation.branches = branches
        conversation.promotedInsightIDs = promotedIDs
        conversation.studyTopicID = studyTopicID
        if let i = snapshot.conversations.firstIndex(where: { $0.id == id }) { snapshot.conversations[i] = conversation }
        else { snapshot.conversations.append(conversation) }
        snapshot.activeConversationID = id
        CurrentConversationsStore.save(snapshot)
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }
    private func enqueueSeed(question: String, answer: String, branchID: UUID, responseIndex: Int, runtime: MacApplicationRuntime) {
        guard !isPreview, savesConversation else { return }
        runtime.conversationTreeMapping.enqueue(conversationID: id,
            turns: [MacConversationMappingTurn(branchID: branchID, responseIndex: responseIndex,
                question: question, answer: InlineInsightMarkup.plainText(from: answer).trimmingCharacters(in: .whitespacesAndNewlines))],
            runtime: runtime, priority: .background,
            onFailure: { [weak self] in self?.report(String(localized: "The Insight Tree couldn’t finish updating. Your conversation and existing tree are saved.")) })
    }

    func isPending(transcriptIndex: Int) -> Bool {
        pendingResponses.contains("\(selectedBranch):\(transcriptIndex - 1)")
    }
    func responseRun(transcriptIndex: Int) -> UUID? {
        responseRuns["\(selectedBranch):\(transcriptIndex - 1)"]
    }
    func shouldRevealResponse(transcriptIndex: Int) -> Bool {
        guard let run = responseRun(transcriptIndex: transcriptIndex) else { return false }
        return !revealedResponseRuns.contains(run)
    }
    func usesIncrementalResponse(transcriptIndex: Int) -> Bool {
        guard let run = responseRun(transcriptIndex: transcriptIndex) else { return false }
        // Keep the live formatter mounted after generation finishes. Switching to the
        // completed renderer here replaces its reveal state with the entire answer.
        return streamedResponseRuns.contains(run)
    }
    func finishResponseReveal(run: UUID) {
        revealedResponseRuns.insert(run)
    }
    /// The next empty question field enters with the footer, rather than waiting for
    /// the staggered buttons and disclaimer to finish their animations.
    var isComposerReady: Bool {
        guard let index = transcript.indices.last,
              case .text = transcript[index],
              let run = responseRun(transcriptIndex: index) else { return true }
        return bodyRevealedResponseRuns.contains(run) || revealedResponseRuns.contains(run)
    }
    func finishResponseBodyReveal(run: UUID) {
        bodyRevealedResponseRuns.insert(run)
    }
    private func modelContext(for branch: ChatBranch, personality: ConversationPersonality) -> ConversationContext {
        let hasCompaction = branch.compactedContext?.isEmpty == false
        var blocks: [ChatBlock] = hasCompaction ? [] : [.user(branch.topQuestionText, branch.branchContextConcepts, branch.topQuestionUploads)]
        // Home prompts carry hidden context ahead of the visible question, as on iPhone.
        if let hidden = branch.hiddenPromptContext?.trimmingCharacters(in: .whitespacesAndNewlines), !hidden.isEmpty {
            blocks.insert(.user(hidden, [], []), at: 0)
        }
        blocks += branch.activeChatBlocks.dropFirst(hasCompaction ? min(branch.compactedThroughBlockCount ?? 0, branch.activeChatBlocks.count) : 0).filter { $0 != .text(questionCanceledResponseText) }
        return ConversationContext(compactedContext: branch.compactedContext, transcript: blocks, personality: personality)
    }
    func isQueued(transcriptIndex: Int) -> Bool {
        let key = "\(selectedBranch):\(transcriptIndex - 1)"
        return pendingResponses.contains(key) && !startedResponses.contains(key)
    }
    func liveThought(transcriptIndex: Int) -> String? {
        responseThoughts["\(selectedBranch):\(transcriptIndex - 1)"]
    }
    func thinkingDuration(transcriptIndex: Int) -> TimeInterval? {
        responseThinkingDurations["\(selectedBranch):\(transcriptIndex - 1)"] ?? presentation(transcriptIndex: transcriptIndex)?.thinkingDurationSeconds
    }
    func presentation(transcriptIndex: Int) -> ResponsePresentationMetadata? { activeBranch?.responsePresentation(at: transcriptIndex - 1) }
    func summary(transcriptIndex: Int) -> [String] {
        responseSummaries["\(selectedBranch):\(transcriptIndex - 1)"] ?? presentation(transcriptIndex: transcriptIndex)?.thinkingSummary ?? []
    }
    func sources(transcriptIndex: Int) -> [GroundingSourceSummary] {
        responseSources["\(selectedBranch):\(transcriptIndex - 1)"] ?? presentation(transcriptIndex: transcriptIndex)?.groundingSources ?? []
    }
    var contextTokenCount: Int {
        guard let branch = activeBranch else { return 0 }
        var parts: [String] = []
        if let checkpoint = branch.compactedContext, !checkpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(checkpoint)
        } else if branch.topQuestionSubmitted { parts.append(branch.topQuestionText) }
        for block in branch.activeChatBlocks.dropFirst(min(branch.compactedThroughBlockCount ?? 0, branch.activeChatBlocks.count)) {
            switch block {
            case .text(let text): parts.append(InlineInsightMarkup.plainText(from: text))
            case .user(let text, _, _): parts.append(text)
            }
        }
        return AngroveContextBudget.estimatedTokenCount(in: parts.joined(separator: "\n"))
    }
    var canCompactContext: Bool {
        guard !isCompactingContext, pendingResponses.isEmpty, let branch = activeBranch else { return false }
        if branch.compactedContext == nil && branch.topQuestionSubmitted && !branch.topQuestionText.isEmpty { return true }
        return branch.activeChatBlocks.dropFirst(min(branch.compactedThroughBlockCount ?? 0, branch.activeChatBlocks.count)).contains { block in
            switch block {
            case .text(let text): return !InlineInsightMarkup.plainText(from: text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != questionCanceledResponseText
            case .user(let text, _, _): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
    func clear(runtime: MacApplicationRuntime) {
        runtime.modelTasks.cancelTasks { $0.conversationID == id }
        pendingResponses.removeAll()
        guard let index = branches.firstIndex(where: { $0.id == selectedBranch }) else { return }
        let replacement = ChatBranch(startingConcept: nil)
        branches[index] = replacement
        selectedBranch = replacement.id
        quote = nil
        uploads = []
        connectionConcepts = []
        restoredDraft = nil
        persistConversation()
    }
    func define(_ term: String, source: String, runtime: MacApplicationRuntime,
                onCompletion: (@MainActor (ConceptDefinition) -> Void)? = nil) {
        guard runtime.modelIsAvailable else { report(UnavailableAngroveModel.unavailableMessage); return }
        let definitionBranchID = selectedBranch
        let key = term.lowercased()
        guard definingTerms.insert(key).inserted else { return }
        let context = ConversationContext(transcript: [.text(source)], personality: runtime.modelTasks.personality)
        runtime.modelTasks.enqueue(kind: .defineInsight(key: key, name: term), originPage: .conversation, conversationID: id,
            onCancel: { [self] in definingTerms.remove(key) }) { [self] in
            defer { definingTerms.remove(key) }
            do {
                let concept = try await runtime.model.defineTerm(term, in: context, conversationID: isPreview ? nil : id)
                guard !Task.isCancelled else { return }
                if let onCompletion { onCompletion(concept) }
                else if selectedBranch == definitionBranchID { selectedDefinition = concept }
            } catch { if !Task.isCancelled { report(error.localizedDescription) } }
        }
    }
    func compact(runtime: MacApplicationRuntime) async -> Bool {
        guard canCompactContext, let branch = activeBranch else { return false }
        isCompactingContext = true
        defer { isCompactingContext = false }
        let branchID = branch.id
        let count = branch.activeChatBlocks.count
        let context = modelContext(for: branch, personality: runtime.modelTasks.personality)
        return await withCheckedContinuation { continuation in
            var resumed = false
            let finish: (Bool) -> Void = { result in
                guard !resumed else { return }; resumed = true; continuation.resume(returning: result)
            }
            runtime.modelTasks.enqueue(kind: .userQuestion(branchID: branchID, responseIndex: -1), conversationID: id,
                onCancel: { finish(false) }) { [self] in
                let summary = await runtime.model.compact(context).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled, !summary.isEmpty, summary != context.compactedContext, let i = branches.firstIndex(where: { $0.id == branchID }), Array(branches[i].activeChatBlocks.prefix(count)) == branch.activeChatBlocks else { finish(false); return }
                branches[i].compactedContext = summary
                branches[i].compactedThroughBlockCount = count
                persistConversation()
                finish(true)
            }
        }
    }
    /// Follows Settings › Conversation Titles, as the iPhone does: a short headline, the first
    /// question, or nothing until the person renames the conversation.
    static func automaticTitle(for question: String) -> String? {
        let raw = UserDefaults.standard.string(forKey: SettingsStorageKey.conversationTitles) ?? ""
        return ConversationTitlePolicy.title(for: question, option: ConversationTitleOption(rawValue: raw) ?? .automatic)
    }

    func report(_ message: String) { errorMessage = message; showsError = true }

}

#if DEBUG
private enum MacTreePreviewData {
    static let concepts = ["Friedrich Nietzsche", "Thomism", "Aristotle", "Nihilism", "Eudaimonia", "Augustine of Hippo", "Thomas Aquinas", "Melito of Sardis"].map {
        ConceptDefinition(id: stableUUID(from: "mac-design-insight:\($0)"), word: $0, partOfSpeech: "", pronunciation: "",
                          meaning: "Design preview · Sample label from Figma. This is not a saved or generated Insight.", example: "")
    }
}
#endif

extension Notification.Name {
    static let macConversationSaved = Notification.Name("angrove.mac.conversation.saved")
    static let macConversationMetadataChanged = Notification.Name("angrove.mac.conversation.metadata.changed")
    static let macConversationDeleted = Notification.Name("angrove.mac.conversation.deleted")
}

/// Question of the Day and Today in History are spent by asking, not by opening the card.
enum MacDailyPrompt {
    static func markAnswered(_ branch: ChatBranch) {
        guard let context = branch.hiddenPromptContext else { return }
        if context.contains("<question of the day>"), let question = HomeQuestionOfTheDayStore.loadPending() {
            HomeQuestionOfTheDayStore.save(question.markingAnswered())
        } else if context.contains("<today in history>") {
            HomeTodayInHistoryStore.markAnswered()
        }
    }

    /// Reopens the untouched conversation a card already created instead of adding another.
    static func conversation(for request: NewConversationRequest, in snapshot: InquiryPersistenceSnapshot) -> InquiryPersistenceSnapshot {
        var snapshot = snapshot
        if let existing = snapshot.conversations.first(where: {
            ConversationDraftRetention.isUntouchedPromptDraft($0) && $0.branches.first?.pinnedHeaderQuestion == request.question
        }) {
            snapshot.activeConversationID = existing.id
            return snapshot
        }
        var branch = ChatBranch(startingConcept: nil, hiddenPromptContext: request.promptContext.isEmpty ? nil : request.promptContext)
        if !request.question.isEmpty { branch.pinnedHeaderQuestion = request.question }
        var conversation = InquiryConversation(studyTopicID: request.topicID, branches: [branch])
        if !request.question.isEmpty { conversation.title = request.question }
        snapshot.conversations.append(conversation)
        snapshot.activeConversationID = conversation.id
        return snapshot
    }
}

