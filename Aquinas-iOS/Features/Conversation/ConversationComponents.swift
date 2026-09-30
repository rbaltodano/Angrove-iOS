//
//  ActiveInquiry.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI
import UIKit

private let questionCanceledResponseText = "Question canceled"

enum ConversationResponseStatePolicy {
    enum CompletionDestination: Equatable {
        case visible, detached, discarded
    }

    static func completionDestination(
        isCancelled: Bool,
        isViewVisible: Bool,
        originalBranchID: UUID,
        displayedBranchID: UUID,
        responseIndex: Int,
        displayedBlockCount: Int
    ) -> CompletionDestination {
        guard !isCancelled else { return .discarded }
        // A different (or unmounted) thread says nothing about the original response slot.
        guard isViewVisible, originalBranchID == displayedBranchID else { return .detached }
        return (0..<displayedBlockCount).contains(responseIndex) ? .visible : .discarded
    }

    static func isAwaitingResponse(
        hasResponseText: Bool,
        isLocallyPending: Bool,
        taskPhase: ModelTaskPhase?
    ) -> Bool {
        // A queue task intentionally remains current until the response begins revealing.
        // Once text exists, treating `.current` as awaiting would prevent that reveal from
        // starting and leave the task waiting on its own completion gate forever.
        guard !hasResponseText else { return false }
        return isLocallyPending || taskPhase == .current || taskPhase == .upcoming
    }
}

/// Keeps a model task current until its response actually begins revealing in the UI.
/// Generation completion alone is not the user-visible completion boundary.
@MainActor
private final class ResponseRevealGate {
    private(set) var hasStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilStarted() async {
        guard !hasStarted, !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !hasStarted, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeWaiter()
            }
        }
    }

    private func resumeWaiter() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ConversationResponseViewLifetime {
    var isVisible = false
}

// MARK: - Chat Thread Column

/// The actual vertical conversation: branch title, locked questions, model responses, and next input.
struct ChatThreadColumn: View {
    @Binding var branchData: ChatBranch
    /// The conversation this branch belongs to, so enqueued model tasks can be routed back
    /// to the exact conversation rather than whichever one happens to be active later.
    var conversationID: UUID? = nil
    let branchAnchor: String
    @Binding var targetSpawnY: CGFloat
    @Binding var uploadedFiles: [UploadedFile]
    let showsPendingUploads: Bool
    let quotedConcept: ConceptDefinition?
    @Binding var targetSpawnResponseIndex: Int?
    var externalSubmitTrigger: Int = 0
    var conversationFontSize: ConversationFontSizeOption = .large
    var conversationTextAlignment: ConversationTextAlignmentOption = .center
    var inputFont: ConversationFontOption = .serif
    var responseFont: ConversationFontOption = .sans
    var conversationTitlePolicy: ConversationTitleOption = .automatic
    var personality: ConversationPersonality = .balanced
    var loadingInsightKey: String? = nil
    var queuedInsightKeys: Set<String> = []
    var savedInsightIDs: Set<UUID> = []
    let modelTasks: ModelTaskQueue
    /// True when another serialized model task is already running at submit time.
    var isModelBusy: Bool = false
    /// Prevents a restored queued draft from focusing its hidden UIKit editor while the user
    /// is browsing another page. The draft remains ready when they return.
    var isPageVisible: Bool = true
    var emptyStateEyebrow: String = ""
    /// Height available above the bottom model controls. The pristine new-conversation
    /// prompt uses this to center its heading and composer as one unit.
    var newConversationViewportHeight: CGFloat = 0
    /// The conversation's study topic name, if it belongs to one — takes priority over
    /// `emptyStateEyebrow` in the header eyebrow, and makes it tappable to change the topic.
    var studyTopicTitle: String? = nil
    var onTapEyebrow: () -> Void = {}
    var emptyStatePromptQuestion: String = ""
    /// Optional paragraph shown beneath the header title on a fresh new-conversation prompt (e.g.
    /// the Today in History description) -- distinct from `hiddenPromptContext`, which feeds the
    /// model but never renders.
    var emptyStatePromptSubtitle: String = ""
    var showsThinkingIntro: Bool = true
    /// Live conversation title, shown as the root branch's heading (updates on rename).
    var conversationTitle: String = ""
    var onSpawnYChange: (Int, CGFloat) -> Void
    var onDuplicateResponse: (String, Int) -> Void
    var onDeleteBranch: () -> Void
    var onConversationTitleChange: (String) -> Void
    var onTopInputFocused: () -> Void = {}
    var onTopQuestionSubmitted: () -> Void = {}
    var onBottomInputFocused: () -> Void
    var onActiveInputTextChange: (String) -> Void = { _ in }
    /// Incremented by the parent to request inserting `commandToInsert` into whichever
    /// question field is currently focused (used by the slash-command picker).
    var insertCommandRequest: Int = 0
    var commandToInsert: String = ""
    var showsSlashCommandMenu: Bool = false
    var slashCommandQuery: SlashCommandQuery? = nil
    var onSelectSlashCommand: (SlashCommand) -> Void = { _ in }
    var onExecuteSlashCommand: (SlashCommandInvocation) -> Void = { _ in }
    var onQuoteHandled: () -> Void
    var onQuotedConceptRemoved: () -> Void = {}
    var onQuotedConceptSubmitted: () -> Void = {}
    var onQuotedConceptTap: (ConceptDefinition) -> Void = { _ in }
    var connectionConcepts: [ConceptDefinition]? = nil
    var onConnectionHandled: (() -> Void)? = nil
    var onResponseGenerated: (Int) -> Void = { _ in }
    /// Called when a response finishes after its conversation left the screen. Arguments are the
    /// originating conversation ID, branch ID, and response index.
    var onDetachedResponseGenerated: (UUID, UUID, Int) -> Void = { _, _, _ in }
    var onDetachedResponseCancelled: (UUID, UUID, Int) -> Void = { _, _, _ in }
    var onResponseCompleted: (Int) -> Void = { _ in }
    var onResponseStarted: () -> Void = {}
    var onResponseCancelled: () -> Void = {}
    var onInsightTap: (String, String) -> Void = { _, _ in }
    var onInlineInsightQuote: (ConceptDefinition) -> Void = { _ in }
    var onInlineInsightFork: (ConceptDefinition, Int) -> Void = { _, _ in }
    var onInlineInsightToggleSaved: (ConceptDefinition) -> Void = { _ in }
    private var modelResponseLineHeight: CGFloat {
        let fontName = responseFont == .sans
            ? "Figtree-Regular"
            : "LibreBaskerville-Regular"
        let font = UIFont(name: fontName, size: conversationFontSize.pointSize)
            ?? .systemFont(ofSize: conversationFontSize.pointSize)
        return ceil(font.lineHeight + 8)
    }

    /// Chat-bubble questions follow the paragraph size setting; the centered field stays fixed.
    private var questionFontSize: CGFloat {
        conversationTextAlignment == .left ? conversationFontSize.pointSize : QuestionInputField.fontSize
    }

    private var inputLineHeight: CGFloat {
        let fontName = inputFont == .sans
            ? "Figtree-Regular"
            : "LibreBaskerville-Regular"
        let font = UIFont(name: fontName, size: questionFontSize)
            ?? .systemFont(ofSize: questionFontSize)
        return ceil(font.lineHeight + 8)
    }

    private func funStatusText(for responseIndex: Int) -> String? {
        modelTasks.allTasks.first { task in
            guard case .userQuestion(let branchID, let taskResponseIndex) = task.kind else {
                return false
            }
            return branchID == branchData.id && taskResponseIndex == responseIndex
        }?.funStatusText
    }

    private func modelTask(for responseIndex: Int) -> ModelTaskSnapshot? {
        modelTasks.allTasks.first { task in
            guard case .userQuestion(let branchID, let taskResponseIndex) = task.kind else {
                return false
            }
            return branchID == branchData.id && taskResponseIndex == responseIndex
        }
    }

    private func isResponsePending(at responseIndex: Int, text: String) -> Bool {
        ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: !text.isEmpty,
            isLocallyPending: pendingResponseIndices.contains(responseIndex),
            taskPhase: modelTask(for: responseIndex)?.phase
        )
    }

    private func isResponseQueued(at responseIndex: Int) -> Bool {
        if modelQueuedResponseIndices.contains(responseIndex) {
            return true
        }
        return modelTask(for: responseIndex)?.phase == .upcoming
    }

    private func responseIdentitySuffix(at responseIndex: Int, text: String) -> String {
        if isResponsePending(at: responseIndex, text: text) {
            return "pending"
        }
        return text == questionCanceledResponseText ? "canceled" : "standard"
    }

    private func regenerateResponse(at responseIndex: Int) {
        guard pendingResponseIndices.isEmpty,
              !modelTasks.contains(where: { task in
                  guard case .userQuestion(let branchID, _) = task.kind else { return false }
                  return branchID == branchData.id
                      && (task.phase == .current || task.phase == .upcoming)
              }),
              branchData.activeChatBlocks.indices.contains(responseIndex),
              case .text(let response) = branchData.activeChatBlocks[responseIndex],
              !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response != questionCanceledResponseText else {
            return
        }

        appendSimulatedResponse(replacingResponseAt: responseIndex) {}
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aquinasModel) private var aquinasModel

    @State private var responseViewLifetime = ConversationResponseViewLifetime()
    @State private var animatedResponseIndices: Set<Int> = []
    @State private var pendingResponseIndices: Set<Int> = []
    @State private var streamingResponseIndices: Set<Int> = []
    @State private var modelQueuedResponseIndices: Set<Int> = []
    @State private var responseThinkingIntroByIndex: [Int: Bool] = [:]
    @State private var responseThinkingSummaryByIndex: [Int: [String]] = [:]
    /// Retrieved grounding passages per response index, held from the moment retrieval finishes
    /// so the loading state can show them, then persisted onto the response presentation so
    /// **Show Thinking** can list the same sources again later.
    @State private var responseGroundingSourcesByIndex: [Int: [GroundingSourceSummary]] = [:]
    @State private var responseRevealGatesByIndex: [Int: ResponseRevealGate] = [:]
    @State private var pendingGeneratedTitleQuestion: String? = nil
    @State private var localConnectionConcepts: [ConceptDefinition]?
    @Namespace private var quotedContextChipNamespace
    @FocusState private var isTopQuestionFocused: Bool
    @FocusState private var isBottomQuestionFocused: Bool
    /// Tracks UITextView buffer emptiness for placeholder visibility (not tied to binding).
    @State private var topFieldIsEmpty: Bool = true
    @State private var bottomFieldIsEmpty: Bool = true
    /// Relay references for reading live UITextView text at submit time without
    /// requiring per-keystroke binding writes (which would re-render the whole tree).
    @State private var topFieldRelay = TextInputRelay()
    @State private var bottomFieldRelay = TextInputRelay()
    /// Which question field last became focused — the target for command insertion.
    @State private var bottomFieldIsActive = false
    /// Manually crossfaded copy of `eyebrowDisplayText` — driven by `withAnimation` directly
    /// rather than `.id()` + `.transition()`, which doesn't reliably fire here (the Text sits
    /// inside a Button's label, and Button appears to swallow the transition on its content).
    @State private var displayedEyebrowText: String = ""
    @State private var isEyebrowTextHidden = false
    /// Inline rename of the big conversation title shown at the top of the root branch's VStack.
    @State private var isEditingBigTitle = false
    @State private var bigTitleDraft = ""
    @FocusState private var isBigTitleFocused: Bool

    /// Placeholder text color resolved directly from the SwiftUI color-scheme environment,
    /// bypassing the Color(UIColor(dynamicProvider:)) conversion which can freeze to the
    /// light-mode value inside UIViewRepresentable-hosted view hierarchies.
    private var placeholderColor: Color {
        AquinasTheme.Colors.placeholder(for: colorScheme)
    }

    @ViewBuilder
    private func slashCommandMenuOverlay(forBottomField: Bool, yOffset: CGFloat) -> some View {
        if showsSlashCommandMenu,
           bottomFieldIsActive == forBottomField,
           let slashCommandQuery {
            SlashCommandMenu(query: slashCommandQuery, maxHeight: nil, onSelect: onSelectSlashCommand)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: yOffset)
                .zIndex(50)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    let chatBubbleColor = AquinasTheme.Colors.background
    private var bottomInputAnchor: String {
        "bottom-input-anchor-\(branchData.id)"
    }

    // MARK: Editable Thread Values=
    // readingTopPadding controls how far the branch title sits from the top in Branch mode.
    private let readingTopPadding: CGFloat = 30

    // Branch title shown above the first question.
    private var displayBranchTitle: String {
        // The root branch's heading mirrors the live conversation title, so renaming the
        // conversation (or its auto-generated title) updates this in place. Child branches keep
        // their own generated branch title.
        if branchData.parentBranchID == nil {
            let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "New Conversation" : title
        }
        return branchData.generatedBranchTitle ?? "New Branch"
    }

    // Pending uploads only appear in the focused branch.
    private var visibleUploads: [UploadedFile] {
        showsPendingUploads ? uploadedFiles : []
    }

    // Title for a branch forked from an existing response.
    private var branchResponseTitle: String? {
        guard let response = branchData.duplicatedResponse else {
            return nil
        }
        return generatedContextTitle(from: response)
    }

    private var branchKeyword: String? {
        nil
    }

    private var usesNewConversationPromptHeader: Bool {
        branchData.parentBranchID == nil
            && branchData.startingConcept == nil
            && branchData.duplicatedResponse == nil
    }

    private var usesOnlyNewConversationPrompt: Bool {
        usesNewConversationPromptHeader
            && !branchData.topQuestionSubmitted
            && branchData.activeChatBlocks.isEmpty
            && !branchData.showBottomInput
            && visibleUploads.isEmpty
            && quotedConcept == nil
            && localConnectionConcepts == nil
    }

    private var trimmedEmptyStateEyebrow: String {
        emptyStateEyebrow.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmptyStatePromptSubtitle: String {
        emptyStatePromptSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eyebrowDisplayText: String {
        if let studyTopicTitle {
            let trimmed = studyTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.uppercased() }
        }
        // "Question of the Day" conversations get the same "add to study topic" eyebrow as
        // any other new conversation — no separate eyebrow copy for that state.
        return "ADD TO STUDY TOPIC"
    }

    private var emptyPromptQuestion: String {
        let trimmedQuestion = emptyStatePromptQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuestion.isEmpty ? "What Should We Study?" : trimmedQuestion
    }

    private var isQuestionOfTheDayPrompt: Bool {
        trimmedEmptyStateEyebrow.caseInsensitiveCompare("QUESTION OF THE DAY") == .orderedSame
            || branchData.hiddenPromptContext?.localizedCaseInsensitiveContains("<question of the day>") == true
    }

    /// The permanent record that this branch started from a Question of the Day — persisted on
    /// the branch itself (unlike `isQuestionOfTheDayPrompt`, which is driven by transient view
    /// state that resets on relaunch), so the header never drifts to the conversation's title.
    private var pinnedHeaderQuestion: String? {
        guard let pinned = branchData.pinnedHeaderQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pinned.isEmpty else {
            return nil
        }
        return pinned
    }

    private var todayInHistoryEntry: TodayInHistoryEntry? {
        guard let context = branchData.hiddenPromptContext else { return nil }
        return TodayInHistoryCatalog.entry(matchingPromptContext: context)
    }

    private var newConversationHeaderTitle: String {
        if isQuestionOfTheDayPrompt, pinnedHeaderQuestion != nil {
            return String(localized: "Question of the Day")
        }
        if pinnedHeaderQuestion != nil, let todayInHistoryEntry {
            return todayInHistoryEntry.title
        }
        if let pinnedHeaderQuestion {
            return pinnedHeaderQuestion
        }
        if !isQuestionOfTheDayPrompt, branchData.generatedBranchTitle != nil {
            return displayBranchTitle
        }
        return emptyPromptQuestion
    }

    private var newConversationHeaderSubtitle: String {
        if isQuestionOfTheDayPrompt, let pinnedHeaderQuestion {
            return pinnedHeaderQuestion
        }
        if let todayInHistoryEntry {
            return todayInHistoryEntry.description
        }
        return trimmedEmptyStatePromptSubtitle
    }

    private func generatedTitle(from question: String) -> String {
        ConversationTitlePolicy.title(for: question, option: .automatic)
            ?? "New Inquiry"
    }

    // Temporary branch-chip title generator for response forks.
    private func generatedContextTitle(from response: String) -> String {
        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "of", "to", "in", "for", "with", "as", "on"]
        let words = response
            .replacingOccurrences(of: "[^A-Za-z0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { String($0) }
            .filter { !stopWords.contains($0.lowercased()) }
            .prefix(3)
            .map { $0.capitalized }

        guard !words.isEmpty else {
            return "Response Branch"
        }

        return words.joined(separator: " ")
    }

    // Routes through the live AquinasModel for structured prose and tappable key terms.
    private func appendSimulatedResponse(
        replacingResponseAt replacementIndex: Int? = nil,
        connectionConcepts: [ConceptDefinition]? = nil,
        restoreQueuedQuestion: @escaping () -> Void
    ) {
        let responseIndex = replacementIndex ?? branchData.activeChatBlocks.count
        let context = modelContextForResponse(
            endingBefore: replacementIndex,
            connectionConcepts: connectionConcepts
        )
        let originalResponse: String?
        let originalPresentation: ResponsePresentationMetadata?
        if let replacementIndex,
           branchData.activeChatBlocks.indices.contains(replacementIndex),
           case .text(let text) = branchData.activeChatBlocks[replacementIndex] {
            originalResponse = text
            originalPresentation = branchData.responsePresentation(at: replacementIndex)
        } else {
            originalResponse = nil
            originalPresentation = nil
        }
        let thinkingEnabled = showsThinkingIntro
        let revealGate = ResponseRevealGate()
        // `branchData` is a binding into the shell's active branches. If the user starts or opens
        // another conversation while this job runs, the binding points at that other conversation's
        // branch, so completion must verify identity before touching it.
        let originalBranchID = branchData.id
        let responseLifetime = responseViewLifetime
        let model = aquinasModel

        animatedResponseIndices.insert(responseIndex)
        pendingResponseIndices.insert(responseIndex)
        responseRevealGatesByIndex[responseIndex] = revealGate
        if isModelBusy || !pendingResponseIndices.subtracting([responseIndex]).isEmpty {
            modelQueuedResponseIndices.insert(responseIndex)
        }
        responseThinkingIntroByIndex[responseIndex] = thinkingEnabled
        responseThinkingSummaryByIndex.removeValue(forKey: responseIndex)
        responseGroundingSourcesByIndex.removeValue(forKey: responseIndex)
        branchData.removeResponsePresentation(at: responseIndex)
        withAnimation(.springRelaxed) {
            if branchData.activeChatBlocks.indices.contains(responseIndex) {
                branchData.activeChatBlocks[responseIndex] = .text("")
            } else {
                branchData.activeChatBlocks.append(.text(""))
            }
            branchData.showBottomInput = false
        }

        // Persist the exact placeholder before the queue can finish on an unmounted page.
        onResponseStarted()
        modelTasks.enqueue(
            kind: .userQuestion(
                branchID: branchData.id,
                responseIndex: responseIndex
            ),
            originPage: .conversation,
            conversationID: conversationID,
            onStart: {
                _ = withAnimation(.easeInOut(duration: 0.25)) {
                    modelQueuedResponseIndices.remove(responseIndex)
                }
            },
            onCancel: {
                guard responseLifetime.isVisible, branchData.id == originalBranchID else {
                    if let conversationID {
                        InquiryPersistenceStore.completeDetachedResponse(
                            branchID: originalBranchID,
                            conversationID: conversationID,
                            responseIndex: responseIndex,
                            annotatedText: originalResponse ?? questionCanceledResponseText,
                            presentation: originalPresentation ?? ResponsePresentationMetadata(
                                responseIndex: responseIndex,
                                showsThinking: false,
                                thinkingSummary: []
                            )
                        )
                        onDetachedResponseCancelled(conversationID, originalBranchID, responseIndex)
                    }
                    return
                }
                if let originalResponse {
                    cancelRegeneration(
                        at: responseIndex,
                        restoring: originalResponse,
                        presentation: originalPresentation
                    )
                } else {
                    cancelResponse(
                        at: responseIndex,
                        restoreQueuedQuestion: restoreQueuedQuestion
                    )
                }
            }
        ) {
            var responseContext = context
            // Keep result metadata with the job; view-local State may be unmounted mid-generation.
            var generatedGroundingSources: [GroundingSourceSummary] = []
            if AquinasContextBudget.shouldCompact(context),
               let split = AquinasContextBudget.historyAndLatestTurn(in: context) {
                let summary = await model.compact(split.history)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty, !Task.isCancelled {
                    responseContext = ConversationContext(
                        compactedContext: summary,
                        transcript: split.latestTurn,
                        personality: context.personality
                    )
                    // The latest user question remains verbatim at `responseIndex - 1`; only the
                    // blocks before it are represented by the new checkpoint.
                    if responseLifetime.isVisible, branchData.id == originalBranchID {
                        branchData.compactedContext = summary
                        branchData.compactedThroughBlockCount = max(
                            branchData.compactedThroughBlockCount ?? 0,
                            max(responseIndex - 1, 0)
                        )
                    }
                }
            }
            let response = await model.respond(
                to: responseContext,
                thinkingEnabled: thinkingEnabled
            ) { update in
                guard !Task.isCancelled else { return }
                if case .groundingSources(let sources) = update {
                    generatedGroundingSources = sources
                }
                guard responseLifetime.isVisible,
                      branchData.id == originalBranchID,
                      branchData.activeChatBlocks.indices.contains(responseIndex) else {
                    return
                }
                _ = withAnimation(.easeInOut(duration: 0.25)) {
                    modelQueuedResponseIndices.remove(responseIndex)
                }
                switch update {
                case .generationStarted:
                    break
                case .thinkingSummary(let summary):
                    responseThinkingSummaryByIndex[responseIndex] = summary
                case .groundingSources(let sources):
                    responseGroundingSourcesByIndex[responseIndex] = sources
                case .responseText(let streamedText):
                    // Keep the stream buffered until the model returns the
                    // fully annotated response. This prevents unannotated text from
                    // flashing before its Insight links are ready, while still letting
                    // the thinking UI transition to "Writing response...".
                    guard !streamedText.isEmpty else { return }
                    streamingResponseIndices.insert(responseIndex)
                }
            }
            let destination = ConversationResponseStatePolicy.completionDestination(
                isCancelled: Task.isCancelled,
                isViewVisible: responseLifetime.isVisible,
                originalBranchID: originalBranchID,
                displayedBranchID: responseLifetime.isVisible ? branchData.id : originalBranchID,
                responseIndex: responseIndex,
                displayedBlockCount: responseLifetime.isVisible ? branchData.activeChatBlocks.count : 0
            )
            guard destination != .discarded else {
                modelQueuedResponseIndices.remove(responseIndex)
                pendingResponseIndices.remove(responseIndex)
                streamingResponseIndices.remove(responseIndex)
                responseRevealGatesByIndex.removeValue(forKey: responseIndex)
                return
            }
            guard destination == .visible else {
                // The originating conversation is no longer on screen. Write the answer into its
                // persisted branch by ID and leave whatever branch the binding now shows alone.
                modelQueuedResponseIndices.remove(responseIndex)
                pendingResponseIndices.remove(responseIndex)
                streamingResponseIndices.remove(responseIndex)
                responseRevealGatesByIndex.removeValue(forKey: responseIndex)
                if let conversationID {
                    let summary = thinkingEnabled ? response.thinkingSummary : []
                    let sources = thinkingEnabled ? generatedGroundingSources : []
                    InquiryPersistenceStore.completeDetachedResponse(
                        branchID: originalBranchID,
                        conversationID: conversationID,
                        responseIndex: responseIndex,
                        annotatedText: response.annotatedText,
                        presentation: ResponsePresentationMetadata(
                            responseIndex: responseIndex,
                            showsThinking: thinkingEnabled && !summary.isEmpty,
                            thinkingSummary: summary,
                            groundingSources: sources,
                            evidenceBasis: response.evidenceBasis
                        )
                    )
                    onDetachedResponseGenerated(conversationID, originalBranchID, responseIndex)
                }
                return
            }
            modelQueuedResponseIndices.remove(responseIndex)
            let persistedThinkingSummary = thinkingEnabled
                ? response.thinkingSummary
                : []
            responseThinkingSummaryByIndex[responseIndex] = persistedThinkingSummary
            let persistedGroundingSources = thinkingEnabled ? generatedGroundingSources : []
            let completedPresentation = ResponsePresentationMetadata(
                responseIndex: responseIndex,
                showsThinking: thinkingEnabled && !persistedThinkingSummary.isEmpty,
                thinkingSummary: persistedThinkingSummary,
                groundingSources: persistedGroundingSources,
                evidenceBasis: response.evidenceBasis
            )
            branchData.setResponsePresentation(completedPresentation)
            withAnimation(.springRelaxed) {
                branchData.activeChatBlocks[responseIndex] = .text(response.annotatedText)
                pendingResponseIndices.remove(responseIndex)
                streamingResponseIndices.remove(responseIndex)
                // The composer is functional state, so it must not depend on the
                // response's ornamental word/underline animation completing without
                // cancellation. The response reserves its final height while animating.
                branchData.showBottomInput = true
            }
            // Model completion is functional state and must not depend on this view remaining
            // mounted long enough to run the response card's reveal animation. Persist the title
            // and completed response now; `onFinish` below remains visual-only.
            finalizePendingGeneratedTitleIfNeeded()
            onResponseGenerated(responseIndex)
            if let conversationID {
                // This ID-addressed write does not depend on the originating view's `@State`
                // still being mounted. A newly mounted conversation can therefore reload the
                // completed branch even when generation began on a previous view instance.
                var durableBranch = branchData
                durableBranch.setResponsePresentation(completedPresentation)
                durableBranch.activeChatBlocks[responseIndex] = .text(response.annotatedText)
                durableBranch.showBottomInput = true
                InquiryPersistenceStore.saveCompletedBranch(
                    durableBranch,
                    conversationID: conversationID
                )
            }
            if response.annotatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                revealGate.markStarted()
            }
            // The reveal is only ornamental pacing. If the card is off screen (another page or
            // thread is showing) its animation never starts, and an unbounded wait would stall
            // the whole shared queue, including Insight Tree work such as midpoints.
            let revealTimeout = Task {
                try? await Task.sleep(for: .seconds(2))
                revealGate.markStarted()
            }
            await revealGate.waitUntilStarted()
            revealTimeout.cancel()
            responseRevealGatesByIndex.removeValue(forKey: responseIndex)
        }
    }

    private func cancelRegeneration(
        at responseIndex: Int,
        restoring response: String,
        presentation: ResponsePresentationMetadata?
    ) {
        responseRevealGatesByIndex.removeValue(forKey: responseIndex)
        modelQueuedResponseIndices.remove(responseIndex)
        pendingResponseIndices.remove(responseIndex)
        streamingResponseIndices.remove(responseIndex)
        animatedResponseIndices.remove(responseIndex)
        responseThinkingIntroByIndex.removeValue(forKey: responseIndex)
        responseThinkingSummaryByIndex.removeValue(forKey: responseIndex)
        responseGroundingSourcesByIndex.removeValue(forKey: responseIndex)

        guard branchData.activeChatBlocks.indices.contains(responseIndex) else {
            onResponseCancelled()
            return
        }

        withAnimation(.springStandard) {
            branchData.activeChatBlocks[responseIndex] = .text(response)
            branchData.showBottomInput = true
        }
        if let presentation {
            branchData.setResponsePresentation(presentation)
        }
        onResponseCancelled()
    }

    private func cancelResponse(
        at responseIndex: Int,
        restoreQueuedQuestion: () -> Void
    ) {
        // Upcoming questions keep the existing draft-restoration behavior. Once a question
        // is current, cancellation leaves a durable transcript marker and opens a fresh composer.
        let wasStillQueued = modelQueuedResponseIndices.contains(responseIndex)
        responseRevealGatesByIndex.removeValue(forKey: responseIndex)
        modelQueuedResponseIndices.remove(responseIndex)
        pendingResponseIndices.remove(responseIndex)
        streamingResponseIndices.remove(responseIndex)
        responseThinkingIntroByIndex.removeValue(forKey: responseIndex)
        responseThinkingSummaryByIndex.removeValue(forKey: responseIndex)
        responseGroundingSourcesByIndex.removeValue(forKey: responseIndex)
        branchData.removeResponsePresentation(at: responseIndex)

        guard branchData.activeChatBlocks.indices.contains(responseIndex) else {
            if wasStillQueued {
                restoreQueuedQuestion()
            } else {
                showFollowUpComposerAfterCancellation()
            }
            onResponseCancelled()
            return
        }

        withAnimation(.springStandard) {
            if wasStillQueued {
                if responseIndex == branchData.activeChatBlocks.count - 1 {
                    branchData.activeChatBlocks.removeLast()
                } else {
                    branchData.activeChatBlocks[responseIndex] = .text("Response stopped.")
                }
            } else {
                animatedResponseIndices.remove(responseIndex)
                responseThinkingIntroByIndex[responseIndex] = false
                branchData.activeChatBlocks[responseIndex] = .text(questionCanceledResponseText)
                branchData.showBottomInput = true
            }
        }
        if wasStillQueued {
            restoreQueuedQuestion()
        } else {
            showFollowUpComposerAfterCancellation()
            finalizePendingGeneratedTitleIfNeeded()
        }
        onResponseCancelled()
    }

    private func showFollowUpComposerAfterCancellation() {
        bottomFieldIsEmpty = true
        branchData.bottomQuestionText = ""
        branchData.showBottomInput = true
        bottomFieldRelay.replaceAll("")
        onActiveInputTextChange("")
    }

    private func restoreQueuedTopQuestion(
        _ question: String,
        uploads: [UploadedFile]
    ) {
        pendingGeneratedTitleQuestion = nil
        topFieldIsEmpty = question.isEmpty
        if showsPendingUploads {
            uploadedFiles = uploads
        }

        withAnimation(.springStandard) {
            branchData.topQuestionText = question
            branchData.topQuestionUploads = []
            branchData.topQuestionSubmitted = false
        }
        onActiveInputTextChange(question)

        guard isPageVisible else { return }
        Task { @MainActor in
            await Task.yield()
            topFieldRelay.replaceAll(question)
            bottomFieldIsActive = false
            isBottomQuestionFocused = false
            isTopQuestionFocused = true
            topFieldRelay.focus()
        }
    }

    private func restoreQueuedBottomQuestion(
        _ question: String,
        quotedConcept: ConceptDefinition?,
        uploads: [UploadedFile],
        connectionConcepts: [ConceptDefinition]?
    ) {
        if showsPendingUploads {
            uploadedFiles = uploads
        }
        bottomFieldIsEmpty = question.isEmpty

        withAnimation(.springStandard) {
            if case .user(let text, _, _) = branchData.activeChatBlocks.last,
               text == question {
                branchData.activeChatBlocks.removeLast()
            }
            branchData.bottomQuestionText = question
            branchData.attachedConcept = quotedConcept
            localConnectionConcepts = connectionConcepts
            branchData.showBottomInput = true
        }
        onActiveInputTextChange(question)

        guard isPageVisible else { return }
        Task { @MainActor in
            await Task.yield()
            bottomFieldRelay.replaceAll(question)
            bottomFieldIsActive = true
            isTopQuestionFocused = false
            isBottomQuestionFocused = true
            bottomFieldRelay.focus()
        }
    }

    private func modelContextForResponse(
        endingBefore responseIndex: Int? = nil,
        connectionConcepts: [ConceptDefinition]? = nil
    ) -> ConversationContext {
        let transcriptEndIndex = min(
            responseIndex ?? branchData.activeChatBlocks.count,
            branchData.activeChatBlocks.count
        )
        let storedCompactedBlockCount = min(
            branchData.compactedThroughBlockCount ?? 0,
            branchData.activeChatBlocks.count
        )
        let usesCompactedContext = branchData.compactedContext != nil
            && transcriptEndIndex >= storedCompactedBlockCount
        let transcriptStartIndex = usesCompactedContext ? storedCompactedBlockCount : 0

        var transcript: [ChatBlock] = []
        if let hiddenPromptContext = branchData.hiddenPromptContext?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !hiddenPromptContext.isEmpty {
            transcript.append(.user(hiddenPromptContext, nil, []))
        }
        if !usesCompactedContext {
            let topQuestion = branchData.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if branchData.topQuestionSubmitted, !topQuestion.isEmpty {
                transcript.append(.user(topQuestion, branchData.branchContextConcept, branchData.topQuestionUploads))
            }
        }
        transcript.append(
            contentsOf: branchData.activeChatBlocks[transcriptStartIndex..<transcriptEndIndex]
                .filter { block in
                    guard case .text(let text) = block else { return true }
                    return text != questionCanceledResponseText
                }
        )
        if let connectionConcepts,
           connectionConcepts.count >= 2,
           let userIndex = transcript.lastIndex(where: { block in
               if case .user = block { return true }
               return false
           }),
           case .user(let question, let concept, let uploads) = transcript[userIndex] {
            transcript[userIndex] = .user(
                connectionInquiryPrompt(
                    concepts: connectionConcepts,
                    question: question
                ),
                concept,
                uploads
            )
        }
        return ConversationContext(
            compactedContext: usesCompactedContext ? branchData.compactedContext : nil,
            transcript: transcript,
            personality: personality
        )
    }

    private func connectionInquiryPrompt(
        concepts: [ConceptDefinition],
        question: String
    ) -> String {
        let conceptLines = concepts.map { concept in
            let title = concept.word.replacingOccurrences(of: "<", with: "‹")
            let definition = concept.semanticDefinition
                .replacingOccurrences(of: "<", with: "‹")
            return "- \(title): \(definition)"
        }
        return """
        <inquire_connection>
        Selected concepts:
        \(conceptLines.joined(separator: "\n"))
        </inquire_connection>

        User's connection inquiry:
        \(question)
        """
    }

    private func responseShowsThinkingIntro(at index: Int, text: String) -> Bool {
        guard text != questionCanceledResponseText else { return false }
        return responseThinkingIntroByIndex[index]
            ?? branchData.responsePresentation(at: index)?.showsThinking
            ?? true
    }

    private func responseGroundingSources(at index: Int) -> [GroundingSourceSummary] {
        responseGroundingSourcesByIndex[index]
            ?? branchData.responsePresentation(at: index)?.groundingSources
            ?? []
    }

    private func responseThinkingSummary(at index: Int) -> [String] {
        responseThinkingSummaryByIndex[index]
            ?? branchData.responsePresentation(at: index)?.thinkingSummary
            ?? []
    }

    private func responseEvidenceBasis(at index: Int) -> ResponseEvidenceBasis? {
        branchData.responsePresentation(at: index)?.evidenceBasis
    }

    private func quotedConceptMatchID(
        _ conceptID: UUID,
        responseIndex: Int
    ) -> String {
        "\(branchData.id)-quoted-concept-\(responseIndex)-\(conceptID)"
    }

    private func finalizePendingGeneratedTitleIfNeeded() {
        // A pinned header (Question of the Day, Today in History) already fixed both the
        // in-conversation heading and the conversation's title at creation time -- an
        // auto-generated title from the user's typed answer must not overwrite either.
        guard branchData.pinnedHeaderQuestion == nil,
              conversationTitlePolicy == .automatic,
              branchData.generatedBranchTitle == nil,
              let pendingQuestion = pendingGeneratedTitleQuestion else { return }
        let title = generatedTitle(from: pendingQuestion)
        pendingGeneratedTitleQuestion = nil
        withAnimation(.springRelaxed) {
            branchData.generatedBranchTitle = title
        }
        if branchData.parentBranchID == nil {
            onConversationTitleChange(title)
        }
    }

    // Locks the first branch question, uploads, and context chip.
    private func submitTopQuestionIfNeeded() {
        // Flush the UITextView's live buffer into the binding synchronously.
        // Because we stopped per-keystroke binding writes, the relay is the only
        // way to read text that was typed but not yet blurred.
        branchData.topQuestionText = topFieldRelay.currentText()
        let submittedQuestion = branchData.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = SlashCommand.invocation(for: submittedQuestion) {
            topFieldRelay.replaceAll("")
            branchData.topQuestionText = ""
            topFieldIsEmpty = true
            onActiveInputTextChange("")
            onExecuteSlashCommand(command)
            return
        }
        guard !submittedQuestion.isEmpty, !branchData.topQuestionSubmitted else {
            branchData.topQuestionText = submittedQuestion
            return
        }

        let submittedUploads = visibleUploads
        branchData.topQuestionText = submittedQuestion
        branchData.topQuestionUploads = submittedUploads
        if showsPendingUploads {
            uploadedFiles.removeAll()
        }
        switch conversationTitlePolicy {
        case .automatic:
            // Title the conversation as soon as the question is asked, not after the answer:
            // the title must not depend on this view still being mounted at completion.
            pendingGeneratedTitleQuestion = submittedQuestion
            finalizePendingGeneratedTitleIfNeeded()
        case .firstQuestion:
            pendingGeneratedTitleQuestion = nil
            if branchData.pinnedHeaderQuestion == nil,
               branchData.generatedBranchTitle == nil,
               let title = ConversationTitlePolicy.title(
                for: submittedQuestion,
                option: .firstQuestion
               ) {
                branchData.generatedBranchTitle = title
                if branchData.parentBranchID == nil {
                    onConversationTitleChange(title)
                }
            }
        case .manual:
            pendingGeneratedTitleQuestion = nil
        }
        withAnimation(.springLively) {
            branchData.topQuestionSubmitted = true
        }
        onTopQuestionSubmitted()
        appendSimulatedResponse {
            restoreQueuedTopQuestion(
                submittedQuestion,
                uploads: submittedUploads
            )
        }
    }

    // Adds a follow-up question lower in the thread and locks its attachments/context.
    private func submitBottomQuestionIfNeeded() {
        // Flush live UITextView text to binding before reading (relay avoids per-keystroke writes).
        branchData.bottomQuestionText = bottomFieldRelay.currentText()
        let submittedQuestion = branchData.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = SlashCommand.invocation(for: submittedQuestion) {
            bottomFieldRelay.replaceAll("")
            branchData.bottomQuestionText = ""
            bottomFieldIsEmpty = true
            onActiveInputTextChange("")
            onExecuteSlashCommand(command)
            return
        }
        guard !submittedQuestion.isEmpty else {
            branchData.bottomQuestionText = submittedQuestion
            return
        }

        let quotedConcept = branchData.attachedConcept
        let submittedUploads = visibleUploads
        let submittedConnectionConcepts = localConnectionConcepts
        withAnimation(.springQuick) {
            branchData.showBottomInput = false
            branchData.activeChatBlocks.append(.user(submittedQuestion, quotedConcept, submittedUploads))
        }
        if quotedConcept != nil {
            onQuotedConceptSubmitted()
        }
        if showsPendingUploads {
            uploadedFiles.removeAll()
        }
        branchData.attachedConcept = nil
        localConnectionConcepts = nil
        branchData.bottomQuestionText = ""
        appendSimulatedResponse(connectionConcepts: submittedConnectionConcepts) {
            restoreQueuedBottomQuestion(
                submittedQuestion,
                quotedConcept: quotedConcept,
                uploads: submittedUploads,
                connectionConcepts: submittedConnectionConcepts
            )
        }
    }

    /// Headline-to-body rhythm shared with Home's Today in History card: 8pt from eyebrow to
    /// title, 14pt from title to the subtitle and the question field.
    static let promptHeadlineSpacing: CGFloat = 14

    private var newConversationPromptHeader: some View {
        VStack(
            alignment: conversationTextAlignment.horizontalAlignment,
            spacing: Self.promptHeadlineSpacing
        ) {
            VStack(alignment: conversationTextAlignment.horizontalAlignment, spacing: 8) {
                Button(action: onTapEyebrow) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack")
                            .font(AquinasTheme.Typography.uiLabel)
                        Text(displayedEyebrowText)
                            .font(AquinasTheme.Typography.uiLabel)
                            .opacity(isEyebrowTextHidden ? 0 : 1)
                            .blur(radius: isEyebrowTextHidden ? 4 : 0)
                    }
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .multilineTextAlignment(conversationTextAlignment.textAlignment)
                    .frame(maxWidth: .infinity, alignment: conversationTextAlignment.frameAlignment)
                }
                .buttonStyle(.plain)
                .onAppear { displayedEyebrowText = eyebrowDisplayText }
                .onChange(of: eyebrowDisplayText) { _, newValue in
                    withAnimation(.easeIn(duration: 0.2)) {
                        isEyebrowTextHidden = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // Animate the text swap together with the reveal, so the icon
                        // (repositioned by the HStack re-centering on the new width)
                        // glides into place instead of snapping.
                        withAnimation(.springLively) {
                            displayedEyebrowText = newValue
                            isEyebrowTextHidden = false
                        }
                    }
                }

                if isEditingBigTitle {
                    TextField("Conversation title", text: $bigTitleDraft)
                        .font(AquinasTheme.Typography.titleXLarge)
                        .foregroundColor(AquinasTheme.Colors.headingText)
                        .lineSpacing(14)
                        .multilineTextAlignment(conversationTextAlignment.textAlignment)
                        .frame(maxWidth: .infinity, alignment: conversationTextAlignment.frameAlignment)
                        .focused($isBigTitleFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isEditingBigTitle = false
                            onConversationTitleChange(bigTitleDraft)
                        }
                } else {
                    Text(newConversationHeaderTitle)
                        .font(AquinasTheme.Typography.titleXLarge)
                        .foregroundColor(AquinasTheme.Colors.headingText)
                        .lineSpacing(14)
                        .multilineTextAlignment(conversationTextAlignment.textAlignment)
                        .frame(maxWidth: .infinity, alignment: conversationTextAlignment.frameAlignment)
                        .id(newConversationHeaderTitle)
                        .transition(.blurredTitleReplacement)
                        .onTapGesture {
                            // A Question of the Day is pinned permanently — not renameable,
                            // since it isn't the conversation's title to begin with.
                            guard pinnedHeaderQuestion == nil else { return }
                            bigTitleDraft = newConversationHeaderTitle
                            isEditingBigTitle = true
                            isBigTitleFocused = true
                        }
                }
            }

            if !isEditingBigTitle, !newConversationHeaderSubtitle.isEmpty {
                Text(newConversationHeaderSubtitle)
                    .paragraphFont()
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineSpacing(7)
                    .multilineTextAlignment(conversationTextAlignment.textAlignment)
                    .frame(maxWidth: .infinity, alignment: conversationTextAlignment.frameAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var newConversationQuestionField: some View {
        VStack(spacing: 12) {
            QuestionInputField(
                placeholder: "Ask a question...",
                text: $branchData.topQuestionText,
                isLocked: branchData.topQuestionSubmitted,
                isEmpty: topFieldIsEmpty && !branchData.topQuestionSubmitted,
                lineHeight: inputLineHeight,
                fontSize: questionFontSize,
                textAlignment: conversationTextAlignment,
                fontOption: inputFont,
                relay: topFieldRelay,
                onFocusChange: { focused in
                    isTopQuestionFocused = focused
                    if focused {
                        bottomFieldIsActive = false
                        isBottomQuestionFocused = false
                        onTopInputFocused()
                    }
                },
                onTextChange: { text in
                    topFieldIsEmpty = text.isEmpty
                    onActiveInputTextChange(text)
                },
                onSubmit: submitTopQuestionIfNeeded,
                onTapToFocus: {
                    guard !branchData.topQuestionSubmitted else { return }
                    bottomFieldIsActive = false
                    isTopQuestionFocused = true
                    isBottomQuestionFocused = false
                    topFieldRelay.focus()
                }
            )
            .overlay(alignment: .top) {
                slashCommandMenuOverlay(forBottomField: false, yOffset: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .zIndex(showsSlashCommandMenu && !bottomFieldIsActive ? 50 : 0)
    }

    var body: some View {
        Group {
            if usesOnlyNewConversationPrompt {
                ZStack(alignment: .top) {
                    Color.clear
                        .frame(height: 1)
                        .id(branchAnchor)

                    VStack(alignment: .center, spacing: Self.promptHeadlineSpacing) {
                        newConversationPromptHeader

                        newConversationQuestionField
                            .id("top-input-anchor-\(branchData.id)")
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(newConversationViewportHeight, 1),
                        alignment: .center
                    )
                }
            } else {
                VStack(alignment: .center, spacing: 48) {
            // MARK: Branch Header
            // Cross, branch title, starting context chip, and the first editable/locked question.
            // The new-conversation headline keeps its prompt spacing to the question after
            // submission, so the question doesn't drift away from it.
            VStack(spacing: usesNewConversationPromptHeader ? Self.promptHeadlineSpacing : 48) {
                if usesNewConversationPromptHeader {
                    newConversationPromptHeader
                        .padding(.top, 84)
                } else {
                    VStack(spacing: 16) {
                        Image("cross-1")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(AquinasTheme.Colors.accent)

                        if let branchKeyword {
                            Text(createEditorialTitle(
                                fullText: displayBranchTitle,
                                keyword: branchKeyword,
                                fontSize: 34,
                                baseColor: AquinasTheme.Colors.primaryReadable,
                                keywordColor: AquinasTheme.Colors.linkGreen
                            ))
                            .multilineTextAlignment(conversationTextAlignment.textAlignment)
                            .frame(maxWidth: .infinity, alignment: conversationTextAlignment.frameAlignment)
                        } else {
                            Text(displayBranchTitle)
                                .font(.custom("LibreBaskerville-Regular", size: 34))
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                .multilineTextAlignment(conversationTextAlignment.textAlignment)
                                .frame(maxWidth: .infinity, alignment: conversationTextAlignment.frameAlignment)
                                .id(displayBranchTitle)
                                .transition(.blurredTitleReplacement)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, readingTopPadding)
                }

                VStack(spacing: 16) {
                    UploadedFileStrip(
                        files: branchData.topQuestionSubmitted ? branchData.topQuestionUploads : visibleUploads,
                        onRemove: branchData.topQuestionSubmitted ? nil : { file in
                            uploadedFiles.removeAll { $0.id == file.id }
                        }
                    )

                    if let concept = branchData.branchContextConcept {
                        BranchContextChip(
                            title: concept.word.capitalized,
                            icon: branchData.topQuestionSubmitted ? "text.bubble.fill" : "text.bubble",
                            animationKey: branchData.topQuestionSubmitted ? "submitted" : "pending",
                            isFilled: branchData.topQuestionSubmitted,
                            appearDelay: 0.25,
                            showRemove: branchData.parentBranchID != nil && !branchData.topQuestionSubmitted,
                            onTap: { onQuotedConceptTap(concept) },
                            onRemove: onDeleteBranch
                        )
                        .matchedGeometryEffect(
                            id: quotedConceptMatchID(concept.id, responseIndex: 0),
                            in: quotedContextChipNamespace
                        )
                    } else if let branchResponseTitle {
                        BranchContextChip(
                            title: branchResponseTitle,
                            icon: "arrow.triangle.branch",
                            animationKey: branchData.topQuestionSubmitted ? "submitted" : "pending",
                            isFilled: branchData.topQuestionSubmitted,
                            appearDelay: 0.25,
                            showRemove: branchData.parentBranchID != nil && !branchData.topQuestionSubmitted,
                            onRemove: onDeleteBranch
                        )
                    }

                    Group {
                        if usesNewConversationPromptHeader {
                            newConversationQuestionField
                        } else {
                            VStack(spacing: 12) {
                                QuestionInputField(
                                    placeholder: "Ask a question...",
                                    text: $branchData.topQuestionText,
                                    isLocked: branchData.topQuestionSubmitted,
                                    isEmpty: topFieldIsEmpty && !branchData.topQuestionSubmitted,
                                    lineHeight: inputLineHeight,
                                    fontSize: questionFontSize,
                                    textAlignment: conversationTextAlignment,
                                    fontOption: inputFont,
                                    placeholderColor: placeholderColor,
                                    relay: topFieldRelay,
                                    onFocusChange: { focused in
                                        isTopQuestionFocused = focused
                                        if focused {
                                            bottomFieldIsActive = false
                                            isBottomQuestionFocused = false
                                            onTopInputFocused()
                                        }
                                    },
                                    onTextChange: { text in
                                        topFieldIsEmpty = text.isEmpty
                                        onActiveInputTextChange(text)
                                    },
                                    onSubmit: submitTopQuestionIfNeeded,
                                    onTapToFocus: {
                                        guard !branchData.topQuestionSubmitted else { return }
                                        bottomFieldIsActive = false
                                        isTopQuestionFocused = true
                                        isBottomQuestionFocused = false
                                        topFieldRelay.focus()
                                    }
                                )
                                .overlay(alignment: .top) {
                                    slashCommandMenuOverlay(forBottomField: false, yOffset: 72)
                                }
                            }
                        }
                    }
                    .id("top-input-anchor-\(branchData.id)")
                }
                .frame(maxWidth: .infinity)
            }

            if branchData.topQuestionSubmitted {
                ConversationSeparator()
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }

            // MARK: Conversation Blocks
            // Alternates between user questions and model response cards.
            ForEach(Array(branchData.activeChatBlocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .text(let textContent):
                    TrackedResponseCard(
                                textContent: textContent,
                                responseIndex: index,
                                shouldAnimateOnAppear: animatedResponseIndices.contains(index),
                                showsThinkingIntro: responseShowsThinkingIntro(at: index, text: textContent),
                                isAwaitingResponse: isResponsePending(at: index, text: textContent),
                                isReceivingStream: streamingResponseIndices.contains(index),
                                isQueuedForModel: isResponseQueued(at: index),
                                usesIncrementalStream: false,
                                thinkingSummary: responseThinkingSummary(at: index),
                                groundingSources: responseGroundingSources(at: index),
                                evidenceBasis: responseEvidenceBasis(at: index),
                                funStatusText: funStatusText(for: index),
                                targetSpawnY: $targetSpawnY,
                                targetSpawnResponseIndex: $targetSpawnResponseIndex,
                                columnSpaceName: "ColumnContent-\(branchData.id)",
                                responseTextAlignment: conversationTextAlignment,
                                responseFont: responseFont,
                                conversationFontSize: conversationFontSize,
                                loadingInsightKey: loadingInsightKey,
                                queuedInsightKeys: queuedInsightKeys,
                                savedInsightIDs: savedInsightIDs,
                                onCenterChange: onSpawnYChange,
                                onRegenerate: {
                                    regenerateResponse(at: index)
                                },
                                onDuplicateBranch: {
                                    onDuplicateResponse(textContent, index)
                                },
                                onInsightTap: onInsightTap,
                                onInlineInsightQuote: onInlineInsightQuote,
                                onInlineInsightFork: { insight in
                                    onInlineInsightFork(insight, index)
                                },
                                onInlineInsightToggleSaved: onInlineInsightToggleSaved,
                                showsResponseActions: !textContent.isEmpty
                                    && textContent != questionCanceledResponseText,
                                onRevealStart: {
                                    responseRevealGatesByIndex[index]?.markStarted()
                                },
                                onFinish: {
                                    animatedResponseIndices.remove(index)
                                    withAnimation(.springLively) { branchData.showBottomInput = true }
                                    onResponseCompleted(index)
                                }
                    )
                    .id(
                        "\(branchData.id)-response-\(index)-"
                            + responseIdentitySuffix(at: index, text: textContent)
                    )
                    .transition(
                        animatedResponseIndices.contains(index)
                        ? .opacity.combined(with: .scale(scale: 0.5))
                        : .identity
                    )

                case .user(let questionText, let concept, let attachments):
                    ConversationSeparator()

                    VStack(spacing: 16) {
                        UploadedFileStrip(files: attachments)

                        if let concept {
                            BranchContextChip(
                                title: concept.word.capitalized,
                                icon: "text.bubble.fill",
                                isFilled: true,
                                animatesAppearance: false,
                                showRemove: false,
                                onTap: { onQuotedConceptTap(concept) }
                            )
                            .matchedGeometryEffect(
                                id: quotedConceptMatchID(
                                    concept.id,
                                    responseIndex: index + 1
                                ),
                                in: quotedContextChipNamespace
                            )
                        }

                        // Same plain field the top question uses, locked after submission
                        // so follow-up questions render consistently.
                        QuestionInputField(
                            placeholder: "",
                            text: .constant(questionText),
                            isLocked: true,
                            isEmpty: false,
                            lineHeight: inputLineHeight,
                            fontSize: questionFontSize,
                            textAlignment: conversationTextAlignment,
                            fontOption: inputFont,
                            relay: TextInputRelay(),
                            onFocusChange: { _ in },
                            onTextChange: { _ in }
                        )
                    }
                    .frame(maxWidth: .infinity)

                    ConversationSeparator()
                }
            }

            // MARK: Follow-up Input
            // Appears after the latest model response finishes.
            if branchData.showBottomInput {
                ConversationSeparator()

                VStack(spacing: 16) {
                        UploadedFileStrip(files: visibleUploads) { file in
                            uploadedFiles.removeAll { $0.id == file.id }
                        }

                        if let concept = branchData.attachedConcept {
                            BranchContextChip(
                                title: concept.word.capitalized,
                                icon: "text.bubble",
                                isFilled: false,
                                showRemove: true,
                                onTap: { onQuotedConceptTap(concept) },
                                onRemove: {
                                    withAnimation {
                                        branchData.attachedConcept = nil
                                    }
                                    onQuotedConceptRemoved()
                                }
                            )
                            .matchedGeometryEffect(
                                id: quotedConceptMatchID(
                                    concept.id,
                                    responseIndex:
                                        branchData.activeChatBlocks.count + 1
                                ),
                                in: quotedContextChipNamespace
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        if let concepts = localConnectionConcepts {
                            ConnectionContextChip(
                                concepts: concepts,
                                onRemove: {
                                    withAnimation(.springLively) {
                                        localConnectionConcepts = nil
                                    }
                                }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        VStack(spacing: 12) {
                            QuestionInputField(
                                placeholder: "Ask a question...",
                                text: $branchData.bottomQuestionText,
                                isEmpty: bottomFieldIsEmpty,
                                lineHeight: inputLineHeight,
                                fontSize: questionFontSize,
                                textAlignment: conversationTextAlignment,
                                fontOption: inputFont,
                                placeholderColor: placeholderColor,
                                relay: bottomFieldRelay,
                                onFocusChange: { focused in
                                    isBottomQuestionFocused = focused
                                    if focused {
                                        bottomFieldIsActive = true
                                        isTopQuestionFocused = false
                                        onBottomInputFocused()
                                    }
                                },
                                onTextChange: { text in
                                    bottomFieldIsEmpty = text.isEmpty
                                    onActiveInputTextChange(text)
                                },
                                onSubmit: submitBottomQuestionIfNeeded,
                                onTapToFocus: { bottomFieldRelay.focus() }
                            )
                            .overlay(alignment: .top) {
                                slashCommandMenuOverlay(forBottomField: true, yOffset: 72)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .id(bottomInputAnchor)
                .frame(maxWidth: .infinity)
                .onAppear {
                    // Reset placeholder state every time this section reappears.
                    // bottomFieldIsEmpty is driven by onTextChange callbacks, so it
                    // stays stale at `false` when showBottomInput cycles false→true
                    // (the UITextView is destroyed and recreated with empty text, but
                    // no change event fires). Re-syncing here restores the placeholder.
                    bottomFieldIsEmpty = branchData.bottomQuestionText.isEmpty
                }
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
            }
                }
                .overlay(alignment: .top) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(branchAnchor)
                }
            }
        }
        .padding(.bottom, 40)
        .coordinateSpace(name: "ColumnContent-\(branchData.id)")
        .onAppear {
            responseViewLifetime.isVisible = true
            if let concept = branchData.startingConcept {
                branchData.branchContextConcept = concept
            }
            // A brand-new branch (e.g. from the "Ask" flow) can mount with `quotedConcept`
            // already populated at construction time, rather than it changing later while this
            // view is on screen — `.onChange` below never fires for that case (there's no
            // old→new transition to observe on a first render), so the chip would silently never
            // appear. Handle that arrives-already-set case here; `.onChange` still covers quoting
            // into an already-mounted branch (e.g. an insight tapped mid-conversation).
            if let concept = quotedConcept {
                branchData.attachedConcept = concept
                branchData.showBottomInput = true
                onQuoteHandled()
            }
            // Sync placeholder visibility with any pre-filled text (e.g. restored branch)
            topFieldIsEmpty    = branchData.topQuestionText.isEmpty
            bottomFieldIsEmpty = branchData.bottomQuestionText.isEmpty
        }
        .onChange(of: modelTasks.latestCompletedTask) { _, completedTask in
            guard let completedTask,
                  case .userQuestion(let branchID, let responseIndex) = completedTask.kind,
                  branchID == branchData.id else {
                return
            }
            pendingResponseIndices.remove(responseIndex)
            modelQueuedResponseIndices.remove(responseIndex)
            streamingResponseIndices.remove(responseIndex)
        }
        .onChange(of: quotedConcept) { oldValue, newValue in
            if let concept = newValue {
                withAnimation(.springLively) {
                    branchData.attachedConcept = concept
                    branchData.showBottomInput = true
                }
                onQuoteHandled()
            }
        }
        .onChange(of: connectionConcepts?.map(\.id)) { _, _ in
            guard let concepts = connectionConcepts else { return }
            withAnimation(.springLively) {
                localConnectionConcepts = concepts
                branchData.showBottomInput = true
            }
            onConnectionHandled?()
        }
        // Top field focus → notify parent so it can scroll the field to the top.
        .onChange(of: isTopQuestionFocused) { _, focused in
            if focused { onTopInputFocused() }
        }
        // Dock arrow button fires externalSubmitTrigger → submit whichever input is active.
        .onChange(of: externalSubmitTrigger) { _, _ in
            if branchData.showBottomInput {
                submitBottomQuestionIfNeeded()
            } else {
                submitTopQuestionIfNeeded()
            }
        }
        // Slash-command picker tapped → insert the command into the focused field.
        .onChange(of: insertCommandRequest) { _, _ in
            insertCommandIntoActiveField()
        }
        .onDisappear {
            responseViewLifetime.isVisible = false
            // Navigating away removes the response renderer, so no reveal callback can arrive.
            // Release only the presentation gates; the shell-owned model task keeps running and
            // will still write its answer through `onResponseGenerated`.
            responseRevealGatesByIndex.values.forEach { $0.markStarted() }
        }
    }

    /// Writes `commandToInsert` into whichever question field is currently focused,
    /// keeping the field first responder, and bubbles the change up so the placeholder
    /// and send-button state track it.
    private func insertCommandIntoActiveField() {
        guard !commandToInsert.isEmpty else { return }
        if bottomFieldIsActive {
            bottomFieldRelay.replaceAll(commandToInsert)
            bottomFieldIsEmpty = commandToInsert.isEmpty
        } else {
            topFieldRelay.replaceAll(commandToInsert)
            topFieldIsEmpty = commandToInsert.isEmpty
        }
        onActiveInputTextChange(commandToInsert)
    }
}

private struct ConversationSeparator: View {
    var verticalPadding: CGFloat = 0
    @State private var isExpanded = false

    var body: some View {
        Rectangle()
            .fill(AquinasTheme.Colors.brownBorder)
            .frame(width: 84, height: 1)
            .scaleEffect(x: isExpanded ? 1 : 0.5, y: 1, anchor: .center)
            .padding(.vertical, verticalPadding)
            .onAppear {
                withAnimation(.springStandard) {
                    isExpanded = true
                }
            }
    }
}

/// The single "Ask a question" input box shared by every question field in the thread (the
/// brand-new-conversation prompt, a forked/continuing branch's top question, and the follow-up
/// field). It intentionally uses a plain placeholder with no extra icon, hint animation, or
/// container chrome.
private struct QuestionInputField: View {
    static let plainMaxWidth: CGFloat = 321
    static let bubbleMaxWidth: CGFloat = 285
    static let bubbleCornerRadius: CGFloat = 28
    static let bubblePadding: CGFloat = 24
    static let bubblePressedScale: CGFloat = 1.05
    static let fontSize: CGFloat = 14

    let placeholder: String
    @Binding var text: String
    var isLocked: Bool = false
    let isEmpty: Bool
    let lineHeight: CGFloat
    var fontSize: CGFloat = QuestionInputField.fontSize
    let textAlignment: InputTextAlignmentOption
    let fontOption: ConversationFontOption
    var placeholderColor: Color = AquinasTheme.Colors.placeholderText
    let relay: TextInputRelay
    var onFocusChange: (Bool) -> Void
    var onTextChange: (String) -> Void
    var onSubmit: (() -> Void)? = nil
    var onTapToFocus: (() -> Void)? = nil

    @State private var isBubblePressed = false

    private var inputFont: UIFont {
        let fontName = fontOption == .sans
            ? "Figtree-Regular"
            : "LibreBaskerville-Regular"
        return UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    private var placeholderFont: Font {
        let fontName = fontOption == .sans
            ? "Figtree-Regular"
            : "LibreBaskerville-Regular"
        return .custom(fontName, size: fontSize)
    }

    private var uiTextAlignment: NSTextAlignment {
        switch textAlignment {
        case .center:
            .center
        case .left:
            .natural
        }
    }

    private var questionEditor: some View {
        // Left-aligned bubbles trim the first line's top leading, so the placeholder sits on
        // the text view's bottom edge to line up with typed glyphs.
        ZStack(alignment: textAlignment == .left ? .bottomLeading : textAlignment.frameAlignment) {
            if isEmpty {
                Text(placeholder)
                    .font(placeholderFont)
                    .foregroundStyle(placeholderColor)
                    .multilineTextAlignment(textAlignment.textAlignment)
                    .frame(maxWidth: .infinity, alignment: textAlignment.frameAlignment)
                    .allowsHitTesting(false)
            }

            ListAwareTextField(
                text: $text,
                font: inputFont,
                lineHeight: lineHeight,
                isLocked: isLocked,
                textColor: .aquinasPrimaryReadable,
                textAlignment: uiTextAlignment,
                onFocusChange: onFocusChange,
                relay: relay,
                onTextChange: onTextChange,
                onSubmit: onSubmit,
                hugsContentWidth: hugsText
            )
            .frame(maxWidth: hugsText ? nil : .infinity, minHeight: 22, alignment: textAlignment.frameAlignment)
        }
        .frame(maxWidth: hugsText ? nil : .infinity, minHeight: 22, alignment: textAlignment.frameAlignment)
    }

    /// The fixed line height adds its extra leading above the first line's glyphs;
    /// the bubble trims that from its top padding so the text sits visually centered.
    private var firstLineLeading: CGFloat {
        max(0, lineHeight - inputFont.lineHeight)
    }

    /// Submitted questions in the left-aligned chat layout shrink their bubble to the text.
    private var hugsText: Bool {
        isLocked && textAlignment == .left
    }

    var body: some View {
        switch textAlignment {
        case .center:
            questionEditor
                .frame(maxWidth: Self.plainMaxWidth, alignment: textAlignment.frameAlignment)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { onTapToFocus?() }
        case .left:
            chatBubble
        }
    }

    /// Left alignment reads as a chat: the question sits in a trailing card-style bubble
    /// inline with the thread. Locked questions hug their text; live fields keep full width.
    private var chatBubble: some View {
        let shape = RoundedRectangle(cornerRadius: Self.bubbleCornerRadius, style: .continuous)
        return questionEditor
            .padding(.horizontal, Self.bubblePadding)
            .padding(.bottom, Self.bubblePadding)
            .padding(.top, max(0, Self.bubblePadding - firstLineLeading))
            // Like the context chips: outlined while drafting, filled once submitted.
            .background(isLocked ? AquinasTheme.Colors.canvasSecondary : Color.clear, in: shape)
            .overlay(shape.stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            .contentShape(shape)
            .onTapGesture { onTapToFocus?() }
            // Draft bubbles swell slightly under the finger; submitted ones stay still.
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: 12,
                perform: {},
                onPressingChanged: { pressing in isBubblePressed = pressing && !isLocked }
            )
            .scaleEffect(isBubblePressed ? Self.bubblePressedScale : 1)
            .animation(.springBouncy, value: isBubblePressed)
            .frame(maxWidth: Self.bubbleMaxWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Response Geometry Tracker

/// Wraps a response card and reports its visual center Y so child branch connector lines stay attached.
struct TrackedResponseCard: View {
    let textContent: String
    let responseIndex: Int
    let shouldAnimateOnAppear: Bool
    let showsThinkingIntro: Bool
    let isAwaitingResponse: Bool
    let isReceivingStream: Bool
    let isQueuedForModel: Bool
    let usesIncrementalStream: Bool
    let thinkingSummary: [String]
    let groundingSources: [GroundingSourceSummary]
    let evidenceBasis: ResponseEvidenceBasis?
    let funStatusText: String?
    @Binding var targetSpawnY: CGFloat
    @Binding var targetSpawnResponseIndex: Int?
    let columnSpaceName: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let savedInsightIDs: Set<UUID>
    var onCenterChange: (Int, CGFloat) -> Void = { _, _ in }
    var onRegenerate: () -> Void = {}
    var onDuplicateBranch: () -> Void = {}
    var onInsightTap: (String, String) -> Void = { _, _ in }
    var onInlineInsightQuote: (ConceptDefinition) -> Void = { _ in }
    var onInlineInsightFork: (ConceptDefinition) -> Void = { _ in }
    var onInlineInsightToggleSaved: (ConceptDefinition) -> Void = { _ in }
    var showsResponseActions: Bool = true
    var onRevealStart: () -> Void = {}
    var onFinish: () -> Void

    @State private var myYCenter: CGFloat = 0
    @State private var hasFinishedStreaming: Bool = false
    @Environment(\.openURL) var parentOpenURL
    private let responseChromeHeight: CGFloat = 46

    private func updateCenter(from geo: GeometryProxy, notifyParent: Bool) {
        let localY = geo.frame(in: .named(columnSpaceName)).minY
        let responseBodyHeight = max(0, geo.size.height - responseChromeHeight)
        myYCenter = localY + responseChromeHeight + (responseBodyHeight / 2)
        if notifyParent {
            let center = myYCenter
            DispatchQueue.main.async { onCenterChange(responseIndex, center) }
        }
    }

    var body: some View {
        ModelResponseCard(
            title: "",
            fullText: textContent,
            shouldAnimateOnAppear: shouldAnimateOnAppear,
            showsThinkingIntro: showsThinkingIntro,
            isAwaitingResponse: isAwaitingResponse,
            isReceivingStream: isReceivingStream,
            isQueuedForModel: isQueuedForModel,
            usesIncrementalStream: usesIncrementalStream,
            thinkingSummary: thinkingSummary,
            groundingSources: groundingSources,
            evidenceBasis: evidenceBasis,
            funStatusText: funStatusText,
            responseTextAlignment: responseTextAlignment,
            responseFont: responseFont,
            conversationFontSize: conversationFontSize,
            loadingInsightKey: loadingInsightKey,
            queuedInsightKeys: queuedInsightKeys,
            savedInsightIDs: savedInsightIDs,
            onRegenerate: onRegenerate,
            onDuplicateBranch: onDuplicateBranch,
            onInsightTap: onInsightTap,
            onInlineInsightQuote: onInlineInsightQuote,
            onInlineInsightFork: { insight in
                targetSpawnY = myYCenter
                targetSpawnResponseIndex = responseIndex
                onInlineInsightFork(insight)
            },
            onInlineInsightToggleSaved: onInlineInsightToggleSaved,
            showsResponseActions: showsResponseActions,
            onRevealStart: onRevealStart,
            onFinish: {
                hasFinishedStreaming = true
                onCenterChange(responseIndex, myYCenter)
                onFinish()
            }
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .named(columnSpaceName)).minY) { _, _ in
                        updateCenter(from: geo, notifyParent: hasFinishedStreaming || !shouldAnimateOnAppear)
                    }
                    .onChange(of: geo.size.height) { _, _ in
                        updateCenter(from: geo, notifyParent: hasFinishedStreaming || !shouldAnimateOnAppear)
                    }
                    .onAppear { updateCenter(from: geo, notifyParent: true) }
            }
        )
        .environment(\.openURL, OpenURLAction { url in
            targetSpawnY = myYCenter
            targetSpawnResponseIndex = responseIndex
            parentOpenURL(url)
            return .handled
        })
    }
}

// MARK: - Insight Sheet Content

struct InsightSheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Bottom sheet shown when a generated insight link is tapped.
struct ConceptSheetContent: View {
    let concept: ConceptDefinition
    @Binding var collectedDefinitions: [ConceptDefinition]
    var onInquireFurther: (() -> Void)? = nil
    var onNewConversation: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    let brandDarkText = AquinasTheme.Colors.primaryReadable

    var body: some View {
        let isSaved = collectedDefinitions.contains(where: { $0.word == concept.word })

        InsightLibraryCard(
            insight: concept,
            isSaved: isSaved,
            maxWidth: .infinity,
            onQuote: {
                onInquireFurther?()
                dismiss()
            },
            onFork: {
                onNewConversation?()
                dismiss()
            },
            onToggleSaved: {
                withAnimation(.springBouncy) {
                    if isSaved { collectedDefinitions.removeAll(where: { $0.word == concept.word }) }
                    else { collectedDefinitions.append(concept) }
                }
            }
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AquinasTheme.Colors.canvas)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InsightSheetContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
    }

}
