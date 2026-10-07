//
//  CurrentConversation.swift
//  Angrove-iOS
//
//  Conversation tab — horizontal branch layout.
//  Each branch is a full-screen vertical ScrollView of ChatThreadColumn.
//  Swipe left / right to move between branches (TabView pager).
//  Swipe left from anywhere to enter Canvas Mode (InsightTreeView).
//

import CryptoKit
import PhotosUI
import SwiftUI
import UIKit
import Observation

private final class MiniScrollButtonVisibilityRelay {
    var isAtBottom: Bool = true
}

struct ConversationInsightWord: Identifiable, Equatable {
    let text: String
    let sourceResponseBlock: String?

    var id: String {
        Self.key(for: text, sourceResponseBlock: sourceResponseBlock)
    }

    static func key(for text: String, sourceResponseBlock: String?) -> String {
        "\(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\n\(sourceResponseBlock ?? "")"
    }
}

@MainActor
@Observable
final class ConversationDefinitionState {
    var activeWord: ConversationInsightWord?
    var loadingWord: ConversationInsightWord?
    var completedWords: [ConversationInsightWord] = []
    var definitionsByKey: [String: ConceptDefinition] = [:]
    var lookupKeys: Set<String> = []
    var sheetContentHeight: CGFloat = 178
    var failedWord: ConversationInsightWord?

    func reset() {
        loadingWord = nil
        completedWords.removeAll()
        definitionsByKey.removeAll()
        lookupKeys.removeAll()
        activeWord = nil
        failedWord = nil
        sheetContentHeight = 178
    }

    func present(_ word: ConversationInsightWord) {
        if activeWord == nil {
            activeWord = word
        } else if activeWord != word,
                  !completedWords.contains(where: { $0.id == word.id }) {
            completedWords.append(word)
        }
    }

    func takeNextCompletedWord() -> ConversationInsightWord? {
        guard activeWord == nil, !completedWords.isEmpty else { return nil }
        return completedWords.removeFirst()
    }
}

struct CurrentConversationView: View {
    @AppStorage(SettingsStorageKey.conversationBackground) private var conversationBackground: CanvasBackgroundOption = .system
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var insightTreeBackground: CanvasBackgroundOption = .system
    var onOpenMenu: () -> Void = {}
    var onCanvasModeChange: (Bool) -> Void = { _ in }
    /// Reports whether the Insight drawer is up so the shell can ignore swipes that land on it.
    var onInsightLibraryVisibilityChange: (Bool) -> Void = { _ in }
    var onRequestConversationPage: () -> Void = {}
    var onReturnToStudyTopicTree: (StudyTopicTreeSelectionRequest) -> Void = { _ in }
    /// Mirrors `onReturnToStudyTopicTree` for an Insight quoted from the global Insight Tree
    /// (`topicID == nil`) rather than a Study Topic's — removing the quoted chip should land
    /// back on that same tree with the Insight hovered, not just clear the composer.
    var onReturnToGlobalInsights: (ConceptDefinition) -> Void = { _ in }
    var onQuestionOfTheDayAnswered: () -> Void = {}
    var onTodayInHistoryAnswered: () -> Void = {}
    @Binding var collectedDefinitions:         [ConceptDefinition]
    @Binding var clippedPassages: [ConceptDefinition]
    @Binding var sideMenuConversations:        [InquiryConversation]
    @Binding var sideMenuCurrentTitle:         String
    @Binding var sideMenuActiveConversationID: UUID?
    @Binding var requestedConversationID:      UUID?
    let newConversationRequests: NewConversationRequests
    @Binding var deletedConversationID:        UUID?
    @Binding var requestedForkConcept:         ConceptDefinition?
    @Binding var insightConversationQuoteRequest: InsightConversationQuoteRequest?
    @Binding var conversationNodeFocusRequest: ConversationNodeFocusRequest?
    let conversationFontSize: ConversationFontSizeOption
    let conversationTextAlignment: ConversationTextAlignmentOption
    let inputFont: ConversationFontOption
    let responseFont: ConversationFontOption
    let conversationTitlePolicy: ConversationTitleOption
    @Binding var conversationPersonality: ConversationPersonality
    let isPageVisible: Bool
    /// App-shell-owned task state. Keeping these references above page navigation lets model
    /// work continue and keeps one shared popup/status surface throughout the app.
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState

    @Environment(\.angroveModel) private var angroveModel
    @Environment(\.embeddingProvider) private var embeddingProvider
    @Environment(\.modelCompletionNotifications) private var modelCompletionNotifications
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // MARK: - Conversation session and presentation
    @State private var session = ConversationSession()
    @State private var pendingFocusBranchID: UUID? = nil

    // MARK: Quoted insight chip
    @State private var attachedConcept: ConceptDefinition? = nil
    @State private var pendingStudyTopicQuoteReturn: InsightConversationQuoteRequest? = nil

    // MARK: Scroll / upload helpers
    @State private var externalSubmitTrigger: Int = 0
    @State private var scrollToBottomRequest: Int = 0
    @State private var scrollToTopRequest: Int = 0
    // Stores the scroll anchor that was most recently focused so the
    // keyboardDidShow handler can re-scroll after the system auto-scroll fires.
    @State private var lastFocusedAnchor: String? = nil
    @State private var miniScrollButtonVisibilityRelay = MiniScrollButtonVisibilityRelay()
    @State private var isBranchScrolledToTop: Bool = true
    @State private var isKeyboardOpen: Bool = false
    @State private var contextCardState = ContextCardState()
    @State private var isRecentPhotosOpen = false
    @State private var attachmentScrollBounds: [CGRect] = []
    @State private var studyTopics: [StudyTopic] = []
    @State private var conversationForTopicPicker: InquiryConversation? = nil
    @State private var hasTextToSubmit: Bool = false
    /// True while the focused composer holds a bare "/token" — shows the slash-command card.
    @State private var isSlashCommandContext: Bool = false
    /// Live mirror of the typed "/token" for the picker header. Held as a plain reference so
    /// per-keystroke updates re-render only the picker, not this whole conversation view.
    @State private var slashQuery = SlashCommandQuery()
    /// Command text to insert into the focused field, applied when `insertCommandRequest` bumps.
    @State private var commandToInsert: String = ""
    @State private var insertCommandRequest: Int = 0
    @State private var isCompactingContext: Bool = false
    @State private var isCompactionErrorPresented: Bool = false
    @State private var isRenamePromptPresented: Bool = false
    @State private var renameDraft: String = ""
    @State private var undiscoveredInsightCount: Int = 0
    @State private var persistedTreeRefreshRequest: Int = 0
    @State private var insightTreeUpdateSignal: Int = 0
    /// Question/response pairs awaiting on-device tree-seed evaluation. Debounced so a rapid
    /// follow-up question never collides with this background call mid-flight. Each pair
    /// carries its own conversationID captured at append time — `activeConversationID` can
    /// change before this fires (e.g. the user switches conversations mid-debounce).
    @State private var pendingLocalInsightTreeSeeds:
        [(conversationID: UUID, question: String, response: String)] = []
    /// First answered questions to name after their tree processing.
    @State private var pendingConversationTitles:
        [(conversationID: UUID, branchID: UUID, question: String)] = []
    /// User messages awaiting the model's "Your Quote" notability check.
    @State private var pendingQuoteCandidates: [(conversationID: UUID, message: String)] = []
    @State private var localInsightTreeSeedDebounceTask: Task<Void, Never>? = nil
    @State private var canvasFocusNodeID: UUID? = nil
    @State private var canvasNodeSelectionRequest: Int = 0
    @State private var manuallySavedConversationInsightIDs: Set<UUID> = []
    /// Number of branch responses currently generating; drives the context wheel spinner.
    @State private var pendingResponseCount: Int = 0
    @State private var activeEmptyPromptEyebrow: String = ""
    @State private var activeEmptyPromptQuestion: String = ""
    @State private var activeEmptyPromptSubtitle: String = ""
    @Binding var uploadedFiles: [UploadedFile]
    @State private var targetSpawnY: CGFloat = 300
    @State private var targetSpawnResponseIndex: Int? = nil
    @State private var viewportSize: CGSize = .zero

    @State private var persistenceTask: Task<Void, Never>? = nil

    // MARK: Canvas mode
    @State private var canvasMode = CanvasModeModel()
    @State private var isEditingTitle: Bool = false
    @State private var titleEditDraft: String = ""

    // MARK: Model controls
    @State private var isPersonalityMenuOpen: Bool = false
    @Binding var showFilePicker: Bool
    @State private var showPhotoPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    // MARK: Context usage
    @State private var displayedContextTokenCount: Int = 0

    // MARK: Insight library sheet
    @State private var isInsightLibraryOpen: Bool = false
    @State private var opensPassagesInInsightPicker = false
    @State private var insightLibraryPopupHeight: CGFloat = 520

    // MARK: Insight word sheet (aq:// links)
    @State private var definitionState = ConversationDefinitionState()

    private var queuedInsightKeys: Set<String> {
        Set(modelTasks.upcomingTasks.compactMap(\.kind.definitionKey))
    }

    // MARK: Canvas helpers
    private var activeTitle: String {
        session.conversations.first { $0.id == session.activeConversationID }?.title ?? "New Conversation"
    }

    /// The active conversation's study topic name, if it belongs to one — shown in the
    /// eyebrow above the branch title in place of "NEW CONVERSATION".
    private var activeStudyTopicTitle: String? {
        guard let topicID = session.conversations.first(where: { $0.id == session.activeConversationID })?.studyTopicID else {
            return nil
        }
        return studyTopics.first { $0.id == topicID }?.title
    }

    private var topConversationChromeOpacity: Double {
        isBranchScrolledToTop && !canvasMode.isTopicCanvasVisible ? 0 : 1
    }

    private var isNewConversationPromptMode: Bool {
        guard session.activeBranches.count == 1, let branch = session.activeBranches.first else { return false }
        return !branch.topQuestionSubmitted
            && branch.parentBranchID == nil
            && branch.startingConcept == nil
            && branch.duplicatedResponse == nil
            && branch.activeChatBlocks.isEmpty
            && !branch.showBottomInput
    }

    private func stableQuestionInsightID(for text: String) -> UUID {
        let digest = SHA256.hash(data: Data(text.utf8))
        let bytes = Array(digest.prefix(16))
        let uuidString = String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private var conversationInsights: [ConceptDefinition] {
        var result = ChatBranch.mentionedInsights(in: session.activeBranches)
        var seen = Set(result.map { $0.word.lowercased() })
        for concept in collectedDefinitions
        where manuallySavedConversationInsightIDs.contains(concept.id) {
            let key = concept.word.lowercased()
            if seen.insert(key).inserted { result.append(concept) }
        }
        return result
    }

    private var hasSelectedCanvasItems: Bool {
        canvasMode.canvasSelectedItemCount > 0
    }

    private func refreshUndiscoveredInsightCountAfterResponse() {
        let currentInsightIDs = conversationInsights.map(\.id)
        _ = InsightDiscoveryStore.markNewInsightsUndiscovered(currentInsightIDs)
        undiscoveredInsightCount = InsightDiscoveryStore.visibleUndiscoveredCount(for: currentInsightIDs)
    }

    /// A completed tree mutation refreshes a mounted Canvas before announcing "Updated".
    /// When Canvas is not mounted, the mutation itself is the final update boundary.
    private func finishInsightTreeMutation(for conversationID: UUID) {
        guard session.activeConversationID == conversationID else { return }
        persistedTreeRefreshRequest += 1
        if !canvasMode.isTopicCanvasVisible {
            insightTreeUpdateSignal += 1
        }
    }

    private func enqueueInsightTreeAnalysis(branchID: UUID, responseIndex: Int) {
        guard let conversationID = session.activeConversationID,
              let branch = session.activeBranches.first(where: { $0.id == branchID }) else {
            return
        }
        enqueueInsightTreeAnalysis(
            conversationID: conversationID,
            branch: branch,
            responseIndex: responseIndex
        )
    }

    /// Called from inside the finishing question job, so the mapping job below is queued ahead of
    /// any question already waiting and the tree reflects this answer before the next one starts.
    private func enqueueInsightTreeAnalysis(
        conversationID: UUID,
        branch: ChatBranch,
        responseIndex: Int
    ) {
        guard responseIndex >= 0,
              responseIndex < branch.activeChatBlocks.count,
              case .text(let responseText) = branch.activeChatBlocks[responseIndex],
              let question = precedingQuestion(in: branch, before: responseIndex) else {
            return
        }

        if conversationTitlePolicy == .automatic,
           branch.parentBranchID == nil,
           responseIndex == 0,
           session.needsAutomaticTitle(
               conversationID: conversationID, branchID: branch.id, question: branch.topQuestionText
           ) {
            pendingConversationTitles.append((conversationID, branch.id, branch.topQuestionText))
        }

        // "Your Quote" judges the user's own message, so it doesn't depend on the answer.
        if HomeDiscovery.isQuoteCandidate(question) {
            pendingQuoteCandidates.append((conversationID: conversationID, message: question))
        }

        // A corpus-scope abstention contains no claim to organize. In particular, do not let a
        // later "take a guess" follow-up turn turn missing evidence into a durable tree subject.
        // General-knowledge conversation is intentionally transient too: it should remain a
        // normal exchange, without turning a model-only answer into a durable subject.
        let isTreeCandidate = !LiteRTAngroveModel.isCorpusScopeAbstention(
            InlineInsightMarkup.plainText(from: responseText)
        ) && branch.responsePresentation(at: responseIndex)?.evidenceBasis != .generalKnowledge

        if isTreeCandidate {
            pendingLocalInsightTreeSeeds.append((
                conversationID: conversationID,
                question: question,
                response: InlineInsightMarkup.plainText(from: responseText)
            ))
        }
        // This runs as a debounced `.background` job (see `enqueueLocalInsightTreeSeedingTask`),
        // so a foreground question always preempts it.
        enqueueLocalInsightTreeSeedingTask(runsNext: true)
    }

    /// Waits for 5s of idle time before
    /// actually starting on-device tree-seed evaluation. A rapid follow-up question reschedules
    /// this instead of colliding with it: `ModelTaskQueue`'s foreground/background preemption is
    /// best-effort (a preempted background job's Swift Task keeps cooperatively finishing rather
    /// than stopping instantly), so avoiding the collision in the first place is far more
    /// reliable than depending on preemption to resolve cleanly every time.
    private func scheduleLocalInsightTreeSeedingAfterIdle() {
        guard !pendingLocalInsightTreeSeeds.isEmpty || !pendingQuoteCandidates.isEmpty || !pendingConversationTitles.isEmpty else {
            return
        }
        localInsightTreeSeedDebounceTask?.cancel()
        localInsightTreeSeedDebounceTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard scenePhase == .active else { return }
            enqueueLocalInsightTreeSeedingTask()
        }
    }

    /// Seeds the conversation's Insight Tree with Node Concepts extracted on-device. This runs as
    /// a `.updateInsightTree` background Model Task
    /// (shows "Mapping...", not "Thinking...", and never blocks the already-displayed answer).
    ///
    /// Every pending turn asks the on-device model to extract its main subject (label + summary)
    /// unconditionally — see `insightTreeSeedCandidate`'s doc comment. Whether that subject
    /// actually becomes a new Node Concept is then decided here, deterministically, by on-device
    /// bundled MiniLM cosine similarity against the Node Concepts already on the tree: below
    /// `newSubjectThreshold` similarity to every existing Node means genuinely new, so it's
    /// appended; at or above it means the turn is still within an existing Node's subject, so no
    /// new Node is added (a related, separately-saved Insight will still cluster under that
    /// existing Node via `InsightTreeViewModel`'s own clustering — see its `localMembershipThreshold`).
    ///
    /// This replaced an earlier design where the model made that new-vs-related judgment itself
    /// (`new_subject: true/false`) directly in the same call. That judgment turned out to be
    /// unreliable and order-dependent — asked to compare the same two Bible/theology subjects in
    /// one order the model correctly saw a pivot, asked in the reverse order it didn't. A binary
    /// "is this new" call is exactly the kind of judgment an LLM is inconsistent at; embedding
    /// similarity answers it the same way every time for the same inputs, and it's the same
    /// lightweight math the tree's own clustering already relies on, so it costs effectively
    /// nothing extra.
    private func enqueueLocalInsightTreeSeedingTask(runsNext: Bool = false) {
        guard !pendingLocalInsightTreeSeeds.isEmpty || !pendingQuoteCandidates.isEmpty || !pendingConversationTitles.isEmpty,
              !modelTasks.contains(where: {
                  $0.kind == .updateInsightTree && $0.phase != .completed
              }) else {
            return
        }
        let pending = pendingLocalInsightTreeSeeds
        pendingLocalInsightTreeSeeds.removeAll()
        let titles = pendingConversationTitles
        pendingConversationTitles.removeAll()
        let quoteCandidates = pendingQuoteCandidates
        pendingQuoteCandidates.removeAll()

        modelTasks.enqueue(
            kind: .updateInsightTree,
            originPage: .conversation,
            priority: .background,
            runsNext: false
        ) {
            // Matches `InsightTreeViewModel.localMembershipThreshold`: below this similarity to
            // every existing Node, a subject counts as genuinely new rather than a continuation
            // of one already on the tree.
            let newSubjectThreshold = InsightTreeSemanticPolicy.newSubjectSimilarity
            for turn in pending {
                guard !Task.isCancelled else { return }
                var existingSeeds = LocalInsightTreeSeedStore.seeds(for: turn.conversationID)
                var didRefreshSeedEmbeddings = false
                for index in existingSeeds.indices
                where existingSeeds[index].embeddingVersion != embeddingProvider.version {
                    let seed = existingSeeds[index]
                    let refreshed = await embeddingProvider.embed(
                        "\(seed.label). \(seed.summary)"
                    )
                    existingSeeds[index] = LocalInsightTreeSeed(
                        id: seed.id,
                        label: seed.label,
                        summary: seed.summary,
                        embedding: refreshed,
                        embeddingVersion: embeddingProvider.version,
                        createdAt: seed.createdAt
                    )
                    didRefreshSeedEmbeddings = true
                }
                if didRefreshSeedEmbeddings {
                    LocalInsightTreeSeedStore.replaceSeeds(
                        existingSeeds,
                        for: turn.conversationID
                    )
                }
                guard let candidate = try? await self.angroveModel.insightTreeSeedCandidate(
                    question: turn.question,
                    response: turn.response
                ) else {
                    continue
                }

                let embedding = await embeddingProvider.embed(
                    "\(candidate.label). \(candidate.summary)"
                )
                if let embedding {
                    let similarities = existingSeeds.compactMap { existing -> (String, Double)? in
                        guard let existingEmbedding = existing.embedding else { return nil }
                        return (existing.label, cosineSimilarity(embedding, existingEmbedding))
                    }
#if DEBUG
                    print("Angrove seed new-subject check: '\(candidate.label)' vs existing \(similarities)")
#endif
                    let isAlreadyCovered = similarities.contains { $0.1 >= newSubjectThreshold }
                    guard !isAlreadyCovered else { continue }
                }

                let newSeedID = UUID()
                LocalInsightTreeSeedStore.appendSeed(
                    LocalInsightTreeSeed(
                        id: newSeedID,
                        label: candidate.label,
                        summary: candidate.summary,
                        embedding: embedding,
                        embeddingVersion: embeddingProvider.version,
                        createdAt: Date()
                    ),
                    for: turn.conversationID
                )
                // Without marking this Node Concept pending, opening the tree fresh (which tours only pending IDs, not a raw
                // diff — see `presentPersistedTree`) would silently skip its reveal animation.
                InsightDiscoveryStore.markNodesUndiscovered([newSeedID])
                InsightDiscoveryStore.markPendingTreePresentation(
                    insightIDs: [],
                    nodeIDs: [newSeedID]
                )
                self.finishInsightTreeMutation(for: turn.conversationID)
            }

            // Tree mutations above are persisted before this separate naming call begins.
            // Even exchanges excluded from the tree can receive a useful conversation title.
            for request in titles {
                guard !Task.isCancelled else { return }
                guard conversationTitlePolicy == .automatic,
                      session.needsAutomaticTitle(
                          conversationID: request.conversationID,
                          branchID: request.branchID, question: request.question
                      ),
                      let title = try? await angroveModel.conversationTitle(for: request.question)
                else { continue }
                guard !Task.isCancelled, conversationTitlePolicy == .automatic else { return }
                if session.applyAutomaticTitle(
                    title, conversationID: request.conversationID,
                    branchID: request.branchID, question: request.question
                ) {
                    // This job can outlive its page. Touch only the named conversation in
                    // shell bindings, preserving the shell's current selection and newer list.
                    if let index = sideMenuConversations.firstIndex(where: { $0.id == request.conversationID }) {
                        sideMenuConversations[index].title = title
                        if let branchIndex = sideMenuConversations[index].branches.firstIndex(where: {
                            $0.id == request.branchID
                        }) {
                            sideMenuConversations[index].branches[branchIndex].generatedBranchTitle = title
                        }
                    }
                    if sideMenuActiveConversationID == request.conversationID {
                        sideMenuCurrentTitle = title
                    }
                }
            }

            for candidate in quoteCandidates {
                guard !Task.isCancelled else { return }
                // Fail-quiet: a failed check just means this message isn't resurfaced.
                guard let notability = try? await self.angroveModel.assessQuoteNotability(
                    candidate.message
                ), notability.isNotable else {
                    continue
                }
                FlaggedQuoteStore.flag(
                    candidate.message,
                    reason: notability.reason,
                    in: candidate.conversationID
                )
            }
        }
    }

    private func precedingQuestion(in branch: ChatBranch, before responseIndex: Int) -> String? {
        if responseIndex > 0 {
            for index in stride(from: responseIndex - 1, through: 0, by: -1) {
                if case .user(let text, _, _) = branch.activeChatBlocks[index],
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }
        let topQuestion = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return topQuestion.isEmpty ? nil : topQuestion
    }

    private func contextTokenCount(in branch: ChatBranch?) -> Int {
        guard let branch else { return 0 }
        var textParts: [String] = []

        if let compactedContext = branch.compactedContext?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !compactedContext.isEmpty {
            textParts.append(compactedContext)
        } else if branch.topQuestionSubmitted {
            let topQuestion = branch.topQuestionText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !topQuestion.isEmpty {
                textParts.append(topQuestion)
            }
        }

        let compactedBlockCount = min(
            branch.compactedThroughBlockCount ?? 0,
            branch.activeChatBlocks.count
        )
        for block in branch.activeChatBlocks.dropFirst(compactedBlockCount) {
            switch block {
            case .text(let text):
                textParts.append(InlineInsightMarkup.plainText(from: text))
            case .user(let text, _, _):
                textParts.append(text)
            }
        }

        return AngroveContextBudget.estimatedTokenCount(in: textParts.joined(separator: "\n"))
    }

    private var canCompactFocusedContext: Bool {
        guard let branch = session.activeBranches.first(where: { $0.id == effectiveFocusedID })
                ?? session.activeBranches.first else {
            return false
        }

        if branch.compactedContext == nil,
           branch.topQuestionSubmitted,
           !branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        let compactedBlockCount = min(
            branch.compactedThroughBlockCount ?? 0,
            branch.activeChatBlocks.count
        )
        return branch.activeChatBlocks.dropFirst(compactedBlockCount).contains { block in
            switch block {
            case .text(let text):
                return !InlineInsightMarkup.plainText(from: text)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .user(let text, _, _):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func refreshDisplayedContextWordCount(animated: Bool = true) {
        let branch = session.activeBranches.first(where: { $0.id == effectiveFocusedID })
            ?? session.activeBranches.first
        let count = contextTokenCount(in: branch)

        if animated {
            withAnimation(.easeInOut(duration: 0.65)) {
                displayedContextTokenCount = count
            }
        } else {
            displayedContextTokenCount = count
        }
    }

    // MARK: Helpers
    private var effectiveFocusedID: UUID? {
        session.focusedBranchID ?? session.activeBranches.first?.id
    }

    private var insightSheetHeight: CGFloat {
        let measured   = max(definitionState.sheetContentHeight, 178)
        let available  = max(viewportSize.height, 1)
        return min(measured + 24, available * 0.82)
    }

    private func pendingFocusBranchTarget() -> ChatBranch? {
        if let pendingFocusBranchID,
           let branch = session.activeBranches.first(where: { $0.id == pendingFocusBranchID }) {
            return branch
        }

        return session.activeBranches.last
    }

    private var focusedBranchSelection: Binding<UUID?> {
        Binding(
            get: { effectiveFocusedID },
            set: { newID in
                if let newID {
                    session.focusedBranchID = newID
                }
            }
        )
    }

    @ViewBuilder
    private func branchPager(in geo: GeometryProxy) -> some View {
        TabView(selection: focusedBranchSelection) {
            ForEach(session.activeBranches) { branch in
                branchPage(branch: session.binding(for: branch), geo: geo)
                    .tag(Optional(branch.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
    }

    private func closeTopicCanvas() {
        canvasMode.isCanvasSearchActive = false
        canvasMode.canvasSearchQuery = ""
        withAnimation(.springStandard) {
            canvasMode.isTopicCanvasVisible = false
        }
    }

    private func enterCanvasMode() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        withAnimation(.springStandard) {
            isKeyboardOpen = false
            canvasMode.isTopicCanvasVisible = true
        }
    }

    private func forkCanvasInsight(_ concept: ConceptDefinition) {
        closeTopicCanvas()
        requestedForkConcept = concept
    }

    @ViewBuilder
    private var topicCanvasLayer: some View {
        // Only bookmarked Insights belong in the tree; un-bookmarking removes the node.
        let savedIDs = Set(collectedDefinitions.map(\.id))
        return InsightTreeView(
            insights: conversationInsights.filter { savedIDs.contains($0.id) },
            conversationID: session.activeConversationID,
            selectionRequest: canvasMode.canvasSelectionRequest,
            persistedTreeRefreshRequest: persistedTreeRefreshRequest,
            clearSelectionRequest: canvasMode.canvasClearSelectionRequest,
            dismissHoverRequest: canvasMode.canvasDismissHoverRequest,
            createConceptRequest: canvasMode.canvasCreateConceptRequest,
            studyRequest: canvasMode.canvasStudyRequest,
            studyExitRequest: canvasMode.canvasStudyExitRequest,
            studyToolsToggleRequest: canvasMode.canvasStudyToolsToggleRequest,
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            studyBranchConfirmRequest: canvasMode.canvasStudyBranchConfirmRequest,
            onStudyModeChange: { canvasMode.isCanvasStudyMode = $0 },
            onStudyToolsActiveChange: { canvasMode.isCanvasStudyToolsActive = $0 },
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            restoreSelectedNodeID: canvasFocusNodeID,
            nodeSelectionRequest: canvasNodeSelectionRequest,
            promotedInsightIDs: canvasMode.promotedCanvasInsightIDs,
            onRemoveInsight: removeConversationInsight,
            onRestoreInsight: restoreConversationInsight,
            onForkInsight: forkCanvasInsight,
            onQuoteInsight: { canvasMode.canvasQuoteTarget = $0 },
            onSelectionStateChange: { canvasMode.hasCanvasHover = $0 },
            onInsightSelectionStateChange: { canvasMode.hasHoveredCanvasInsight = $0 },
            onSelectedCanvasItemCountChange: { canvasMode.canvasSelectedItemCount = $0 },
            onPromotedInsightIDsChange: { canvasMode.promotedCanvasInsightIDs = $0 },
            savedConceptIDs: Set(collectedDefinitions.map(\.id)),
            onToggleSavedConcept: { concept in
                toggleSavedConcept(concept)
            },
            onBookmarkConcepts: { concepts in
                for concept in concepts {
                    setSavedConcept(concept, isSaved: true)
                }
            },
            inquireConnectionRequest: canvasMode.canvasInquireConnectionRequest,
            onInquireConnectionConcepts: { concepts in
                canvasMode.canvasConnectionConcepts = concepts
                closeTopicCanvas()
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    scrollToBottomRequest += 1
                }
            },
            midpointEnterRequest: canvasMode.canvasMidpointEnterRequest,
            midpointCenterRequest: canvasMode.canvasMidpointCenterRequest,
            midpointPlaceRequest: canvasMode.canvasMidpointPlaceRequest,
            searchQuery: canvasMode.canvasSearchQuery,
            searchPreviousRequest: canvasMode.canvasSearchPreviousRequest,
            searchNextRequest: canvasMode.canvasSearchNextRequest,
            onSearchResultsChange: { current, total in
                canvasMode.canvasSearchResultIndex = current
                canvasMode.canvasSearchResultCount = total
            },
            onMidpointModeChange: { canvasMode.isCanvasMidpointMode = $0 },
            onMidpointGeneratingChange: { canvasMode.isCanvasInsightGenerating = $0 },
            onUndiscoveredInsightCountChange: { undiscoveredInsightCount = $0 },
            onPersistedTreeRefreshCompleted: {
                insightTreeUpdateSignal += 1
            },
            inputFont: inputFont,
            conversationFontSize: conversationFontSize,
            showQuestionBar: false,
            modelTasks: modelTasks,
            modelTaskOriginPage: .conversation,
            model: angroveModel,
            embeddingProvider: embeddingProvider
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .zIndex(1)
    }

    private func quoteConceptIntoCurrentConversation(_ concept: ConceptDefinition) {
        withAnimation(.springBouncy) {
            attachedConcept = concept
            if session.focusedBranchID == nil {
                session.focusedBranchID = session.activeBranches.first?.id
            }
            canvasMode.isTopicCanvasVisible = false
            canvasMode.hasCanvasHover = false
            canvasMode.hasHoveredCanvasInsight = false
            canvasMode.canvasQuoteTarget = nil
            canvasMode.canvasSelectedItemCount = 0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(180))
            scrollToBottomRequest += 1
        }
    }

    /// Opens the conversation's Insight Tree with the requested Node Concept selected. The tree
    /// builds asynchronously after the canvas mounts, so the selection is requested after it has
    /// had a moment to lay out.
    private func openConversationNodeFocus(_ request: ConversationNodeFocusRequest) {
        conversationNodeFocusRequest = nil
        guard let conversation = session.conversations.first(where: { $0.id == request.conversationID }) else {
            return
        }
        if session.activeConversationID != conversation.id {
            switchToConversation(conversation)
        }
        canvasFocusNodeID = request.nodeID
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            enterCanvasMode()
            try? await Task.sleep(for: .milliseconds(700))
            canvasNodeSelectionRequest += 1
        }
    }

    private func openInsightConversationQuote(_ request: InsightConversationQuoteRequest) {
        guard let conversation = session.conversations.first(where: {
            $0.id == request.conversationID
                && (request.topicID == nil || $0.studyTopicID == request.topicID)
        }) else {
            insightConversationQuoteRequest = nil
            return
        }

        switchToConversation(conversation)
        pendingStudyTopicQuoteReturn = request.insight.isLibraryQuote ? nil : request
        insightConversationQuoteRequest = nil
        quoteConceptIntoCurrentConversation(request.insight)
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            scrollToBottomRequest += 1
        }
    }

    private func returnToStudyTopicTreeAfterQuoteCancellation() {
        guard let request = pendingStudyTopicQuoteReturn else { return }
        pendingStudyTopicQuoteReturn = nil
        attachedConcept = nil
        if let topicID = request.topicID {
            onReturnToStudyTopicTree(
                StudyTopicTreeSelectionRequest(
                    topicID: topicID,
                    insightID: request.insight.id
                )
            )
        } else {
            onReturnToGlobalInsights(request.insight)
        }
    }

    /// The slash-command card shows while the keyboard is up and the composer holds a
    /// bare "/token", in Branch mode (not the topic canvas).
    private var showSlashCommandMenu: Bool {
        isKeyboardOpen && isSlashCommandContext && !canvasMode.isTopicCanvasVisible
    }

    /// A command was tapped — insert it into the focused field and dismiss the card.
    private func selectSlashCommand(_ command: SlashCommand) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        commandToInsert = command.name + " "
        insertCommandRequest += 1
        hasTextToSubmit = true
        withAnimation(.springQuick) {
            isSlashCommandContext = false
        }
    }

    private var bottomInquiryControlDock: some View {
        InquiryControlDock(
            isCanvasMode: canvasMode.isTopicCanvasVisible,
            showFilePicker: $showFilePicker,
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            selectedPersonality: Binding(
                get: { conversationPersonality.displayName },
                set: { newValue in
                    guard let personality = ConversationPersonality.allCases.first(where: {
                        $0.displayName == newValue
                    }) else { return }
                    conversationPersonality = personality
                }
            ),
            isPersonalityMenuOpen: $isPersonalityMenuOpen,
            isAtBottom: true,
            isKeyboardOpen: isKeyboardOpen,
            showsSendButton: isKeyboardOpen && hasTextToSubmit,
            hasCanvasHover: canvasMode.hasCanvasHover,
            hasCanvasInsightHover: canvasMode.hasHoveredCanvasInsight,
            hasSelectedCanvasItems: hasSelectedCanvasItems,
            selectedCanvasItemCount: canvasMode.canvasSelectedItemCount,
            onScrollToBottom: { scrollToBottomRequest += 1 },
            onViewEntireCanvas: { },
            onOpenInsights: {
                opensPassagesInInsightPicker = false
                withAnimation(.springQuick) {
                    isInsightLibraryOpen = true
                }
            },
            onOpenPassages: {
                opensPassagesInInsightPicker = true
                withAnimation(.springQuick) { isInsightLibraryOpen = true }
            },
            onSend: {
                withAnimation(.springStandard) {
                    hasTextToSubmit = false
                    isKeyboardOpen = false
                }
                externalSubmitTrigger += 1
            },
            onSelectCanvasItem: { canvasMode.canvasSelectionRequest += 1 },
            onCreateCanvasConcept: { canvasMode.canvasCreateConceptRequest += 1 },
            onStudyCanvasInsight: { canvasMode.canvasStudyRequest += 1 },
            onInquireConnection: { canvasMode.canvasInquireConnectionRequest += 1 },
            onQuoteCanvasItem: {
                guard let target = canvasMode.canvasQuoteTarget else { return }
                quoteConceptIntoCurrentConversation(target)
            },
            onMidpointConcepts: { canvasMode.canvasMidpointEnterRequest += 1 },
            isMidpointMode: canvasMode.isCanvasMidpointMode,
            isStudyMode: canvasMode.isCanvasStudyMode,
            isStudyToolsActive: canvasMode.isCanvasStudyToolsActive,
            onToggleStudyTools: { canvasMode.canvasStudyToolsToggleRequest += 1 },
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            onStudyBranchConfirm: { canvasMode.canvasStudyBranchConfirmRequest += 1 },
            isCanvasInsightLoading: canvasMode.isCanvasInsightGenerating,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            keepsIdleModelStatus: true,
            onAttachRecentPhoto: { data in
                guard UploadedFile.isImageData(data) else { return }
                withAnimation(.springLively) {
                    uploadedFiles.append(UploadedFile(
                        name: "Photo",
                        imageData: data,
                        rotationDegrees: Double.random(in: -5...5)
                    ))
                }
            },
            recentPhotosOpen: $isRecentPhotosOpen,
            canvasSearchText: Binding(
                get: { canvasMode.canvasSearchQuery },
                set: { canvasMode.canvasSearchQuery = $0 }
            ),
            isCanvasSearchActive: Binding(
                get: { canvasMode.isCanvasSearchActive },
                set: { canvasMode.isCanvasSearchActive = $0 }
            ),
            canvasSearchResultIndex: canvasMode.canvasSearchResultIndex,
            canvasSearchResultCount: canvasMode.canvasSearchResultCount,
            onCanvasSearchPrevious: { canvasMode.canvasSearchPreviousRequest += 1 },
            onCanvasSearchNext: { canvasMode.canvasSearchNextRequest += 1 },
            onCanvasSearchActivated: {
                contextCardState.reset()
                modelTasksPopupState.reset()
                canvasMode.canvasDismissHoverRequest += 1
            },
            onMidpointCenter: { canvasMode.canvasMidpointCenterRequest += 1 },
            onMidpointPlace: { canvasMode.canvasMidpointPlaceRequest += 1 },
            onClearCanvasSelection: { canvasMode.canvasClearSelectionRequest += 1 },
            contextWordCount: displayedContextTokenCount,
            canCompactContext: canCompactFocusedContext && !modelTasks.isBusy,
            onCompactContext: {
                guard let branchID = effectiveFocusedID else { return false }
                return await performContextCompaction(in: branchID)
            },
            onClearConversation: clearCurrentConversation,
            onContextWillOpen: {
                if canvasMode.isTopicCanvasVisible { canvasMode.canvasDismissHoverRequest += 1 }
            },
            contextCard: contextCardState
        )
    }

    // MARK: Body
    var body: some View {
        conversationWithStateSync
        .canvasAppearance(canvasMode.isTopicCanvasVisible ? insightTreeBackground : conversationBackground)
        .onDisappear {
            persistenceTask?.cancel()
            localInsightTreeSeedDebounceTask?.cancel()
            removeActiveConversationIfEmpty()
            persistConversations()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scheduleLocalInsightTreeSeedingAfterIdle()
            } else {
                localInsightTreeSeedDebounceTask?.cancel()
            }
        }
        // aq:// insight links
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "aq", let host = url.host else { return .systemAction }
            let word = host.removingPercentEncoding ?? host
            openDynamicDefinition(word: word, sourceResponseBlock: nil)
            return .handled
        })
        // aq:// word insight sheet
        .sheet(item: $definitionState.activeWord, onDismiss: presentNextCompletedDefinition) { sheetData in
            insightSheet(for: sheetData)
        }
        // Insight library sheet (opened from "Insights" in the + menu)
        .sheet(isPresented: $isInsightLibraryOpen) {
            InsightLibraryPopup(
                currentConversationInsights: currentConversationInsights(),
                allInsights: collectedDefinitions,
                clippedPassages: clippedPassages,
                savedInsights: $collectedDefinitions,
                opensPassages: opensPassagesInInsightPicker,
                onQuote: { concept in
                    withAnimation(.springBouncy) {
                        attachedConcept = concept
                        if session.focusedBranchID == nil {
                            session.focusedBranchID = session.activeBranches.first?.id
                        }
                    }
                    isInsightLibraryOpen = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        scrollToBottomRequest += 1
                    }
                },
                onFork: { concept in
                    let parentID = session.focusedBranchID ?? session.activeBranches.first?.id
                    let newBranch = ChatBranch(
                        startingConcept: concept,
                        parentBranchID: parentID,
                        parentResponseIndex: targetSpawnResponseIndex,
                        yOffset: targetSpawnY
                    )
                    withAnimation(.springRelaxed) {
                        insertBranch(newBranch, after: parentID)
                    }
                    isInsightLibraryOpen = false
                },
                onToggleSaved: { concept in
                    withAnimation(.springBouncy) {
                        if collectedDefinitions.contains(where: { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }) {
                            collectedDefinitions.removeAll { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }
                        } else {
                            collectedDefinitions.append(concept)
                        }
                    }
                },
                onToggleClipped: { passage in
                    if clippedPassages.contains(where: { $0.id == passage.id }) {
                        clippedPassages.removeAll { $0.id == passage.id }
                    } else {
                        clippedPassages.append(passage)
                    }
                }
            )
            .onPreferenceChange(InsightLibraryPopupHeightKey.self) { height in
                insightLibraryPopupHeight = height
            }
            .presentationDetents([.height(insightLibrarySheetHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(AngroveTheme.Colors.canvas)
        }
        .onChange(of: isInsightLibraryOpen) { _, isOpen in
            onInsightLibraryVisibilityChange(isOpen)
        }
        .onDisappear { onInsightLibraryVisibilityChange(false) }
    }

    /// Split out of `body` so each piece stays small enough to type-check quickly; the
    /// modifiers are applied in the same order as a single chain.
    private var conversationWithStateSync: some View {
        conversationScaffold
        .onChange(of: session.focusedBranchID) { _, _ in
            refreshDisplayedContextWordCount()
        }
        .onChange(of: session.activeBranches.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            let target = pendingFocusBranchTarget()
            pendingFocusBranchID = nil
            guard let target else { return }
            let targetID = target.id
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.springRelaxed) {
                    session.focusedBranchID = targetID
                }
            }
        }
        .onChange(of: modelTasks.latestCompletedTask) { _, completedTask in
            guard let completedTask,
                  case .userQuestion(let branchID, _) = completedTask.kind,
                  let snapshot = CurrentConversationsStore.load(),
                  let persistedConversation = snapshot.conversations.first(where: {
                      $0.id == completedTask.conversationID
                  }),
                  let persistedBranch = persistedConversation.branches.first(where: {
                      $0.id == branchID
                  }) else {
                return
            }

            // A conversation view mounted while this task was already running has its own local
            // value state. Pull in only the completed branch, preserving drafts and edits on all
            // other branches while making the finished answer appear immediately.
            // A completion for a conversation the user has since left only refreshes the stored
            // copy below, so reopening that conversation shows the answer.
            if completedTask.conversationID == session.activeConversationID,
               let branchIndex = session.activeBranches.firstIndex(where: { $0.id == branchID }) {
                session.activeBranches[branchIndex] = persistedBranch
            }
            if let conversationIndex = session.conversations.firstIndex(where: {
                $0.id == persistedConversation.id
            }) {
                session.conversations[conversationIndex].branches = persistedConversation.branches
                session.conversations[conversationIndex].title = persistedConversation.title
            }
            if completedTask.conversationID == session.activeConversationID {
                refreshDisplayedContextWordCount()
            }
            // Keep the reader's viewport stable when the completed response appears.
            // Scrolling to the response remains an explicit action through the dock.
        }
        // MARK: - Persistence / conversation management
        .onAppear {
            let loadedSnapshot = CurrentConversationsStore.load()
            // Untouched Question of the Day drafts saved by earlier builds are dropped rather
            // than restored; restoring one froze the app on open.
            let cleanedSnapshot = loadedSnapshot.map { snapshot in
                var cleaned = snapshot
                cleaned.conversations.removeAll { ConversationDraftRetention.isUntouchedPromptDraft($0) }
                return cleaned
            }
            if let snapshot = cleanedSnapshot, !snapshot.conversations.isEmpty {
                session.conversations = snapshot.conversations
                // `openModelTaskPage` (tapping a task in the Model Tasks popup from a different
                // page) sets `requestedConversationID` *before* this view is even created, so
                // the `.onChange(of: requestedConversationID)` below never fires for it — that
                // only catches a value set while this view is already mounted. Without this
                // check, a fresh mount always fell back to whatever was last persisted as
                // active, silently ignoring which conversation the tapped task actually belongs
                // to (surfacing as "tapping the task opens a different/blank conversation").
                let requestedID = requestedConversationID
                if let requestedID {
                    requestedConversationID = nil
                }
                let targetID = requestedID
                    ?? snapshot.activeConversationID
                    ?? snapshot.conversations.first?.id
                if let id = targetID, let convo = snapshot.conversations.first(where: { $0.id == id }) {
                    session.activeConversationID = id
                    session.activeBranches = convo.branches.isEmpty ? [ChatBranch(startingConcept: nil)] : convo.branches
                    canvasMode.promotedCanvasInsightIDs = convo.promotedInsightIDs
                } else if let first = snapshot.conversations.first {
                    session.activeConversationID = first.id
                    session.activeBranches = first.branches.isEmpty ? [ChatBranch(startingConcept: nil)] : first.branches
                    canvasMode.promotedCanvasInsightIDs = first.promotedInsightIDs
                }
            } else {
                let initial = InquiryConversation()
                session.conversations = [initial]
                session.activeConversationID = initial.id
                session.activeBranches = [ChatBranch(startingConcept: nil)]
                canvasMode.promotedCanvasInsightIDs = []
            }
            session.focusedBranchID = session.activeBranches.first?.id
            restoreEmptyPromptState(from: session.activeBranches)
            refreshDisplayedContextWordCount(animated: false)
            if let conversationID = session.activeConversationID {
                manuallySavedConversationInsightIDs =
                    ConversationInsightMembershipStore.insightIDs(for: conversationID)
            }
            studyTopics = StudyTopicStore.load()
            publishShellMenuState()
            scrollToEndOfConversationAfterLayout()

            // A new-conversation request may have been fired while this view was
            // unmounted (e.g. from the Study Topics page). Handle it now so the
            // correct topic-tagged conversation is created instead of showing the
            // most-recently saved one.
            if let request = newConversationRequests.takePending() {
                startNewConversation(request)
            }
            if let request = insightConversationQuoteRequest {
                openInsightConversationQuote(request)
            }
            if let request = conversationNodeFocusRequest {
                openConversationNodeFocus(request)
            }
        }
        // Save branches back into the active conversation on every change, then persist.
        // saveCurrentConversation + publishShellMenuState are cheap (memory only).
        // persistConversations is debounced so UserDefaults isn't hit on every keystroke.
        .onChange(of: session.activeBranches) { _, _ in
            saveCurrentConversation()
            // publishShellMenuState() intentionally omitted — side menu data doesn't
            // change while typing, so calling it here causes a full AngroveSideMenu +
            // StreamingMessageView re-render on every keystroke (the source of lag).
            // It is called from onConversationTitleChange (post-submit), switchToConversation,
            // startNewConversation, and .onAppear instead.
            persistenceTask?.cancel()
            persistenceTask = Task {
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                persistConversations()
            }
        }
        // A response may finish in a column captured by an earlier view instance. Reconcile
        // its ID-addressed write into the currently mounted page before later snapshot saves.
        .onChange(of: modelTasks.latestCompletedTask) { _, task in
            guard let task, let conversationID = task.conversationID,
                  case .userQuestion(let branchID, let responseIndex) = task.kind else { return }
            refreshPersistedResponse(
                conversationID: conversationID, branchID: branchID, responseIndex: responseIndex
            )
        }
        // Side menu selected a conversation.
        .onChange(of: requestedConversationID) { _, id in
            guard let id, let convo = session.conversations.first(where: { $0.id == id }) else { return }
            requestedConversationID = nil
            switchToConversation(convo)
        }
        .onChange(of: insightConversationQuoteRequest) { _, request in
            guard let request else { return }
            openInsightConversationQuote(request)
        }
        .onChange(of: conversationNodeFocusRequest) { _, request in
            guard let request else { return }
            openConversationNodeFocus(request)
        }
        // "New Conversation" button in side menu.
        .onChange(of: newConversationRequests.pending?.id) { _, _ in
            guard let request = newConversationRequests.takePending() else { return }
            startNewConversation(request)
        }
        // Conversation deleted from side menu / Conversations page.
        .onChange(of: deletedConversationID) { _, id in
            guard let id else { return }
            deletedConversationID = nil
            ConversationInsightMembershipStore.removeConversation(id)
            LocalInsightTreeSeedStore.removeConversation(id)
            GlossedTermStore.removeConversation(id)
            FlaggedQuoteStore.removeConversation(id)
            session.conversations.removeAll { $0.id == id }
            if session.activeConversationID == id {
                if let first = session.conversations.first {
                    switchToConversation(first)
                } else {
                    startNewConversation()
                }
            }
            persistConversations()
        }
        // Sync title renames that ContentView applies directly to the sideMenuConversations binding.
        .onChange(of: sideMenuConversations) { _, updated in
            var changed = false
            for mc in updated {
                if let idx = session.conversations.firstIndex(where: { $0.id == mc.id }) {
                    if session.conversations[idx].title != mc.title {
                        session.conversations[idx].title = mc.title
                        changed = true
                    }
                    if session.conversations[idx].studyTopicID != mc.studyTopicID {
                        session.conversations[idx].studyTopicID = mc.studyTopicID
                        changed = true
                    }
                }
            }
            if changed { persistConversations() }
        }
    }

    /// Height of the top fade that softens content scrolling under the top bar.
    static func topFadeHeight(compact: Bool) -> CGFloat {
        compact ? 96 : 150
    }

    private var conversationScaffold: some View {
        GeometryReader { geo in
            let usesCompactVerticalLayout = verticalSizeClass == .compact
            ZStack(alignment: .top) {
                CanvasBackground(option: canvasMode.isTopicCanvasVisible ? insightTreeBackground : conversationBackground)
                    .ignoresSafeArea()

                // Horizontal branch pager
                branchPager(in: geo)

                // Photo backgrounds carry their own scrim, so the canvas-colored fades are skipped.
                if !(canvasMode.isTopicCanvasVisible ? insightTreeBackground : conversationBackground).isPhoto {
                    ConversationScrollFades(
                        topHeight: ConversationScrollFades.topFadeHeight(compact: usesCompactVerticalLayout),
                        bottomHeight: geo.size.height * (usesCompactVerticalLayout ? 0.28 : 0.4),
                        topOpacity: topConversationChromeOpacity,
                        showsBottomFade: !canvasMode.isTopicCanvasVisible
                    )
                }

                // Canvas Mode: per-conversation Insight Tree
                if canvasMode.isTopicCanvasVisible {
                    topicCanvasLayer
                }

                // The window-level canvas swipe must yield to the recent-photo strip.
                if isPageVisible && !canvasMode.isTopicCanvasVisible && !isInsightLibraryOpen && !isRecentPhotosOpen {
                    RightEdgeCanvasSwipeTrigger(excludedScrollBounds: attachmentScrollBounds) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        enterCanvasMode()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
                }

                // Top bar (replaces simple AngroveNavButton HStack)
                BranchModeTopBar(
                    isCanvasMode: canvasMode.isTopicCanvasVisible,
                    title: isNewConversationPromptMode ? "" : activeTitle,
                    titleOpacity: topConversationChromeOpacity,
                    insightTreeUpdateSignal: insightTreeUpdateSignal,
                    isEditingTitle: $isEditingTitle,
                    titleDraft: $titleEditDraft,
                    conversationFontSize: conversationFontSize,
                    isInStudyTopic: activeStudyTopicTitle != nil,
                    isStudyMode: canvasMode.isCanvasStudyMode,
                    onMenuTap: onOpenMenu,
                    onCanvasTap: enterCanvasMode,
                    onBackTap: {
                        withAnimation(.springStandard) {
                            if canvasMode.isCanvasStudyMode {
                                canvasMode.canvasStudyExitRequest += 1
                            } else {
                                canvasMode.isTopicCanvasVisible = false
                            }
                        }
                    },
                    onCommitTitle: { newTitle in
                        renameActiveConversation(to: newTitle)
                    },
                    onTapStudyTopicBadge: {
                        conversationForTopicPicker = session.conversations.first { $0.id == session.activeConversationID }
                    }
                )
                .zIndex(2)
                .animation(.easeInOut(duration: 0.28), value: topConversationChromeOpacity)
            }
            .onAppear {
                viewportSize = geo.size
                if session.focusedBranchID == nil {
                    session.focusedBranchID = session.activeBranches.first?.id
                }
            }
            .onChange(of: geo.size) { _, s in viewportSize = s }
        }
        .onPreferenceChange(AttachmentScrollBoundsKey.self) { attachmentScrollBounds = $0 }
        // Publishes to the shell's single Model Controls bar; renders nothing here.
        .background {
            bottomInquiryControlDock
        }
        .alert("Couldn’t compact context", isPresented: $isCompactionErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The conversation was left unchanged. The on-device model couldn’t finish; please try again.")
        }
        .alert("Rename Conversation", isPresented: $isRenamePromptPresented) {
            TextField("Conversation name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameDraft = "" }
            Button("Save") {
                renameActiveConversation(to: renameDraft)
                renameDraft = ""
            }
        }
        .alert("Couldn’t generate definition", isPresented: Binding(
            get: { definitionState.failedWord != nil },
            set: { if !$0 { definitionState.failedWord = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                definitionState.failedWord = nil
            }
            Button("Try Again") {
                guard let word = definitionState.failedWord else { return }
                definitionState.failedWord = nil
                enqueueDynamicDefinition(word)
            }
        } message: {
            Text("No placeholder Insight was created. The on-device model couldn’t finish; please try again.")
        }
        .onChange(of: canvasMode.isTopicCanvasVisible) { _, isVisible in
            onCanvasModeChange(isVisible)
            modelTasksPopupState.reset()
            if !isVisible {
                canvasMode.isCanvasSearchActive = false
                canvasMode.canvasSearchQuery = ""
                canvasMode.canvasSearchResultIndex = 0
                canvasMode.canvasSearchResultCount = 0
                canvasMode.hasCanvasHover = false
                canvasMode.hasHoveredCanvasInsight = false
                canvasMode.canvasQuoteTarget = nil
                canvasMode.canvasSelectedItemCount = 0
            }
        }
        .onChange(of: canvasMode.hasHoveredCanvasInsight) { _, isHoveringInsight in
            guard isHoveringInsight else { return }
            withAnimation(.springStandard) {
                modelTasksPopupState.reset()
            }
        }
        .onChange(of: canvasMode.canvasSelectedItemCount) { _, selectedCount in
            guard selectedCount > 0 else { return }
            withAnimation(.springStandard) {
                modelTasksPopupState.reset()
            }
        }
        .onChange(of: canvasMode.isCanvasMidpointMode) { _, isMakingMidpoint in
            guard isMakingMidpoint else { return }
            withAnimation(.springStandard) {
                modelTasksPopupState.reset()
            }
        }
        .onDisappear {
            onCanvasModeChange(false)
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardOpen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )) { _ in
            withAnimation(.springStandard) {
                isKeyboardOpen = false
                isSlashCommandContext = false
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 8,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       UploadedFile.isImageData(data) {
                        await MainActor.run {
                            withAnimation(.springLively) {
                                uploadedFiles.append(
                                    UploadedFile(
                                        name: "Photo",
                                        imageData: data,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    }
                }
                await MainActor.run { selectedPhotoItems.removeAll() }
            }
        }
        .sheet(item: $conversationForTopicPicker) { conversation in
            SideMenuStudyTopicPickerSheet(
                conversation: conversation,
                onSelectTopic: { topic in
                    if let idx = session.conversations.firstIndex(where: { $0.id == conversation.id }) {
                        session.conversations[idx].studyTopicID = topic.id
                        publishShellMenuState()
                        persistConversations()
                    }
                },
                onRemoveTopic: {
                    if let idx = session.conversations.firstIndex(where: { $0.id == conversation.id }) {
                        session.conversations[idx].studyTopicID = nil
                        publishShellMenuState()
                        persistConversations()
                    }
                }
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AngroveTheme.Colors.canvas)
            .onDisappear {
                studyTopics = StudyTopicStore.load()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.86) {
                    withAnimation(.springLively) {
                        uploadedFiles.append(
                            UploadedFile(
                                name: "Camera Photo",
                                imageData: data,
                                rotationDegrees: Double.random(in: -5...5)
                            )
                        )
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Insight library helpers

    private var insightLibrarySheetHeight: CGFloat {
        let available = max(viewportSize.height, 1)
        return min(max(insightLibraryPopupHeight, 220), available * 0.86)
    }

    private func currentConversationInsights() -> [ConceptDefinition] {
        var parts: [String] = []
        for branch in session.activeBranches {
            parts.append(branch.topQuestionText)
            parts.append(branch.bottomQuestionText)
            if let dup = branch.duplicatedResponse { parts.append(dup) }
            for block in branch.activeChatBlocks {
                switch block {
                case .text(let text):
                    parts.append(InlineInsightMarkup.plainText(from: text))
                case .user(let text, _, _):
                    parts.append(text)
                }
            }
        }
        let lower = parts.joined(separator: " ").lowercased()
        return collectedDefinitions
            .filter { lower.contains($0.word.lowercased()) }
            .uniquedByWord()
    }

    // MARK: - Branch page

    @ViewBuilder
    private func branchPage(branch: Binding<ChatBranch>, geo: GeometryProxy) -> some View {
        let b = branch.wrappedValue
        let stableViewportHeight = max(geo.size.height, viewportSize.height)
        let usesCompactVerticalLayout = verticalSizeClass == .compact
        let bottomRunwayHeight = stableViewportHeight * (
            isKeyboardOpen ? (usesCompactVerticalLayout ? 0.55 : 0.85) : (usesCompactVerticalLayout ? 0.22 : 0.35)
        )
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .background(
                        GeometryReader { topGeo in
                            Color.clear
                                .onAppear {
                                    updateTopState(for: b.id, minY: topGeo.frame(in: .named("BranchScroll-\(b.id)")).minY)
                                }
                                .onChange(of: topGeo.frame(in: .named("BranchScroll-\(b.id)")).minY) { _, newMinY in
                                    updateTopState(for: b.id, minY: newMinY)
                                }
                        }
                    )

                ChatThreadColumn(
                    branchData: branch,
                    conversationID: session.activeConversationID,
                    branchAnchor: "branch-top-\(b.id)",
                    targetSpawnY: $targetSpawnY,
                    uploadedFiles: $uploadedFiles,
                    showsPendingUploads: b.id == effectiveFocusedID,
                    quotedConcept: b.id == effectiveFocusedID ? attachedConcept : nil,
                    targetSpawnResponseIndex: $targetSpawnResponseIndex,
                    externalSubmitTrigger: b.id == effectiveFocusedID ? externalSubmitTrigger : 0,
                    conversationFontSize: conversationFontSize,
                    conversationTextAlignment: conversationTextAlignment,
                    inputFont: inputFont,
                    responseFont: responseFont,
                    conversationTitlePolicy: conversationTitlePolicy,
                    personality: conversationPersonality,
                    loadingInsightKey: definitionState.loadingWord?.id,
                    queuedInsightKeys: queuedInsightKeys,
                    savedInsightIDs: Set(collectedDefinitions.map(\.id)),
                    modelTasks: modelTasks,
                    contextCard: b.id == effectiveFocusedID ? contextCardState : nil,
                    isModelBusy: modelTasks.isBusy,
                    isPageVisible: isPageVisible,
                    emptyStateEyebrow: activeEmptyPromptEyebrow,
                    newConversationViewportHeight: stableViewportHeight,
                    studyTopicTitle: activeStudyTopicTitle,
                    onTapEyebrow: {
                        conversationForTopicPicker = session.conversations.first { $0.id == session.activeConversationID }
                    },
                    emptyStatePromptQuestion: activeEmptyPromptQuestion,
                    emptyStatePromptSubtitle: activeEmptyPromptSubtitle,
                    showsThinkingIntro: true,
                    conversationTitle: activeTitle,
                    onSpawnYChange: { _, _ in },
                    onDuplicateResponse: { text, index in
                        let newBranch = ChatBranch(
                            startingConcept: nil,
                            parentBranchID: b.id,
                            parentResponseIndex: index,
                            duplicatedResponse: InlineInsightMarkup.plainText(from: text),
                            yOffset: targetSpawnY
                        )
                        withAnimation(.springRelaxed) {
                            insertBranch(newBranch, after: b.id)
                        }
                    },
                    onDeleteBranch: { deleteBranch(b) },
                    onConversationTitleChange: { newTitle in
                        if let idx = session.conversations.firstIndex(where: { $0.id == session.activeConversationID }) {
                            session.conversations[idx].title = newTitle
                        }
                        publishShellMenuState()
                    },
                    onTopInputFocused: {
                        lastFocusedAnchor = "top-input-anchor-\(b.id)"
                    },
                    onTopQuestionSubmitted: {
                        guard b.parentBranchID == nil else { return }
                        switch activeEmptyPromptEyebrow {
                        case "QUESTION OF THE DAY":
                            onQuestionOfTheDayAnswered()
                        case "TODAY IN HISTORY":
                            onTodayInHistoryAnswered()
                        default:
                            break
                        }
                    },
                    onBottomInputFocused: {
                        lastFocusedAnchor = "bottom-input-anchor-\(b.id)"
                    },
                    onActiveInputTextChange: { text in
                        guard b.id == effectiveFocusedID else { return }
                        hasTextToSubmit = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        // Slash-command context: the field holds a bare "/token" (no space yet).
                        // Only updates @State on the boundary crossing, so typing stays lag-free.
                        let slash = text.hasPrefix("/") && !text.contains(" ") && !text.contains("\n")
                        if slash { slashQuery.text = text }   // re-renders only the picker
                        if slash != isSlashCommandContext {
                            withAnimation(.springQuick) {
                                isSlashCommandContext = slash
                            }
                        }
                    },
                    insertCommandRequest: b.id == effectiveFocusedID ? insertCommandRequest : 0,
                    commandToInsert: commandToInsert,
                    showsSlashCommandMenu: b.id == effectiveFocusedID && showSlashCommandMenu,
                    slashCommandQuery: slashQuery,
                    onSelectSlashCommand: selectSlashCommand,
                    onExecuteSlashCommand: { command in
                        executeSlashCommand(command, in: b.id)
                    },
                    onQuoteHandled: { attachedConcept = nil },
                    onQuotedConceptRemoved: {
                        returnToStudyTopicTreeAfterQuoteCancellation()
                    },
                    onQuotedConceptSubmitted: {
                        pendingStudyTopicQuoteReturn = nil
                    },
                    onQuotedConceptTap: { concept in
                        presentQuotedConcept(concept)
                    },
                    connectionConcepts: b.id == effectiveFocusedID ? canvasMode.canvasConnectionConcepts : nil,
                    onConnectionHandled: { canvasMode.canvasConnectionConcepts = nil },
                    onResponseGenerated: { responseIndex in
                        // The response is complete even if its on-screen reveal animation will
                        // never run because navigation removed this view. Save at the model
                        // completion boundary so remounting the conversation restores the answer.
                        saveCurrentConversation()
                        persistConversations()
                        refreshDisplayedContextWordCount()
                        pendingResponseCount = max(0, pendingResponseCount - 1)
                        enqueueInsightTreeAnalysis(branchID: b.id, responseIndex: responseIndex)
                    },
                    onDetachedResponseGenerated: { conversationID, branchID, responseIndex in
                        // The answer belongs to a conversation the user has left. Refresh its
                        // stored copy from disk, then map it before the next queued question.
                        guard let snapshot = CurrentConversationsStore.load(),
                              let persisted = snapshot.conversations.first(where: {
                                  $0.id == conversationID
                              }),
                              let branch = persisted.branches.first(where: { $0.id == branchID }),
                              let index = session.conversations.firstIndex(where: {
                                  $0.id == conversationID
                              }) else {
                            return
                        }
                        session.conversations[index].branches = persisted.branches
                        session.conversations[index].title = persisted.title
                        enqueueInsightTreeAnalysis(
                            conversationID: conversationID,
                            branch: branch,
                            responseIndex: responseIndex
                        )
                    },
                    onDetachedResponseCancelled: { conversationID, branchID, responseIndex in
                        refreshPersistedResponse(
                            conversationID: conversationID, branchID: branchID,
                            responseIndex: responseIndex
                        )
                    },
                    onResponseCompleted: { _ in },
                    onResponseStarted: {
                        pendingResponseCount += 1
                        saveCurrentConversation()
                        persistConversations()
                    },
                    onResponseCancelled: {
                        pendingResponseCount = max(0, pendingResponseCount - 1)
                    },
                    onInsightTap: { word, sourceResponseBlock in
                        openDynamicDefinition(word: word, sourceResponseBlock: sourceResponseBlock)
                    },
                    onInlineInsightQuote: { concept in
                        withAnimation(.springBouncy) {
                            attachedConcept = concept
                            session.focusedBranchID = b.id
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            scrollToBottomRequest += 1
                        }
                    },
                    onInlineInsightFork: { concept, responseIndex in
                        let newBranch = ChatBranch(
                            startingConcept: concept,
                            parentBranchID: b.id,
                            parentResponseIndex: responseIndex,
                            yOffset: targetSpawnY
                        )
                        withAnimation(.springRelaxed) {
                            insertBranch(newBranch, after: b.id)
                        }
                    },
                    onInlineInsightToggleSaved: { concept in
                        toggleSavedConcept(concept)
                    }
                )
                .padding(.horizontal, usesCompactVerticalLayout ? 48 : 36)
                .frame(maxWidth: usesCompactVerticalLayout ? 1_120 : .infinity)

                // Extra scroll runway lets focused question fields sit higher on screen,
                // leaving room to see recent responses above the keyboard.
                Color.clear.frame(width: 1, height: bottomRunwayHeight)
                    .animation(.easeInOut(duration: 0.2), value: isKeyboardOpen)
                Color.clear
                    .frame(width: 1, height: 1)
                    .id("branch-bottom-\(b.id)")
                    .background(
                        GeometryReader { bottomGeo in
                            Color.clear
                                .onAppear {
                                    updateBottomState(for: b.id, maxY: bottomGeo.frame(in: .named("BranchScroll-\(b.id)")).maxY, viewportHeight: geo.size.height)
                                }
                                .onChange(of: bottomGeo.frame(in: .named("BranchScroll-\(b.id)")).maxY) { _, newMaxY in
                                    updateBottomState(for: b.id, maxY: newMaxY, viewportHeight: geo.size.height)
                                }
                        }
                    )
            }
            // Explicit bottom content margin larger than the dock (76 pt) so the
            // system keyboard auto-scroll places the field above the dock even when
            // TabView fails to propagate the parent's .safeAreaInset inward.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .coordinateSpace(name: "BranchScroll-\(b.id)")
            // While the recent-photos card is open, a tap anywhere on the thread closes it.
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(.springStandard) { isRecentPhotosOpen = false }
                },
                including: isRecentPhotosOpen ? .all : .subviews
            )
            .onChange(of: scrollToBottomRequest) { _, _ in
                guard b.id == effectiveFocusedID else { return }
                withAnimation(.springStandard) {
                    proxy.scrollTo("branch-bottom-\(b.id)", anchor: .bottom)
                }
            }
            .onChange(of: scrollToTopRequest) { _, _ in
                guard b.id == effectiveFocusedID else { return }
                withAnimation(.springStandard) {
                    proxy.scrollTo("branch-top-\(b.id)", anchor: .top)
                }
            }
            // keyboardDidShow fires AFTER the system's own auto-scroll completes,
            // so this override always wins and places the field near the top, 48 pt
            // below the top fade gradient so it stays fully legible.
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidShowNotification
            )) { _ in
                guard b.id == effectiveFocusedID,
                      let anchor = lastFocusedAnchor else { return }
                let topBarClearance = Self.topFadeHeight(compact: usesCompactVerticalLayout) + 48
                let anchorY = min(topBarClearance / max(geo.size.height, 1), 0.5)
                withAnimation(.springStandard) {
                    proxy.scrollTo(anchor, anchor: UnitPoint(x: 0.5, y: anchorY))
                }
            }
        }
    }

    private func updateBottomState(for branchID: UUID, maxY: CGFloat, viewportHeight: CGFloat) {
        guard branchID == effectiveFocusedID else { return }
        let atBottom = maxY <= viewportHeight + 32
        guard miniScrollButtonVisibilityRelay.isAtBottom != atBottom else { return }
        miniScrollButtonVisibilityRelay.isAtBottom = atBottom
        NotificationCenter.default.post(
            name: .aquinasMiniScrollButtonVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": !atBottom]
        )
    }

    private func updateTopState(for branchID: UUID, minY: CGFloat) {
        guard isPageVisible else { return }
        guard branchID == effectiveFocusedID else { return }
        let atTop = minY >= -8
        guard isBranchScrolledToTop != atTop else { return }
        isBranchScrolledToTop = atTop
    }

    // MARK: - Insight sheet

    @ViewBuilder
    private func insightSheet(for sheetData: ConversationInsightWord) -> some View {
        let definition = definitionState.definitionsByKey[sheetData.id]
        let isSaved = definition.map { c in
            collectedDefinitions.contains {
                $0.word.caseInsensitiveCompare(c.word) == .orderedSame
                    && $0.containsDefinitions(from: c)
            }
        } ?? false
        let isClipped = definition.map { c in
            clippedPassages.contains { $0.id == c.id }
        } ?? false

        return DynamicInsightSheetCard(
            word: sheetData.text,
            concept: definition,
            isSaved: isSaved,
            isClipped: isClipped,
            funStatusText: modelTasks.allTasks.first {
                $0.kind.definitionKey == sheetData.id && $0.phase != .completed
            }?.funStatusText,
            onQuote: {
                guard let concept = definition else { return }
                definitionState.activeWord = nil
                withAnimation(.springBouncy) {
                    attachedConcept = concept
                    if session.focusedBranchID == nil {
                        session.focusedBranchID = session.activeBranches.first?.id
                    }
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    scrollToBottomRequest += 1
                }
            },
            onFork: {
                guard let concept = definition else { return }
                definitionState.activeWord = nil
                let newBranch = ChatBranch(
                    startingConcept: concept,
                    parentBranchID: effectiveFocusedID,
                    parentResponseIndex: targetSpawnResponseIndex,
                    yOffset: targetSpawnY
                )
                withAnimation(.springRelaxed) {
                    insertBranch(newBranch, after: effectiveFocusedID)
                }
            },
            onToggleSaved: {
                guard let concept = definition else { return }
                toggleSavedConcept(concept)
            },
            onToggleClipped: {
                guard let concept = definition else { return }
                if clippedPassages.contains(where: { $0.id == concept.id }) {
                    clippedPassages.removeAll { $0.id == concept.id }
                } else {
                    clippedPassages.append(concept)
                }
            }
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InsightSheetContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
        .frame(maxWidth: .infinity)
        .background(AngroveTheme.Colors.canvas)
        .onPreferenceChange(InsightSheetContentHeightKey.self) { h in
            definitionState.sheetContentHeight = h
        }
        .presentationDetents([.height(insightSheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(AngroveTheme.Colors.canvas)
    }

    // MARK: - Branch management

    private func insertBranch(_ branch: ChatBranch, after parentID: UUID?) {
        pendingFocusBranchID = branch.id
        guard let parentID,
              let parentIndex = session.activeBranches.firstIndex(where: { $0.id == parentID }) else {
            session.activeBranches.append(branch)
            return
        }
        session.activeBranches.insert(branch, at: min(parentIndex + 1, session.activeBranches.count))
    }

    private func deleteBranch(_ branch: ChatBranch) {
        guard let parentID = branch.parentBranchID,
              let parent = session.activeBranches.first(where: { $0.id == parentID }) else { return }

        var toRemove: Set<UUID> = [branch.id]
        var queue: [UUID] = [branch.id]
        while let current = queue.popLast() {
            for b in session.activeBranches where b.parentBranchID == current {
                if toRemove.insert(b.id).inserted { queue.append(b.id) }
            }
        }

        withAnimation(.springStandard) {
            session.activeBranches.removeAll { toRemove.contains($0.id) }
        }
        let returnID = parent.id
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.springRelaxed) {
                session.focusedBranchID = returnID
            }
        }
    }

    // MARK: - Conversation management

    private func executeSlashCommand(
        _ command: SlashCommandInvocation,
        in branchID: UUID
    ) {
        switch command {
        case .clear:
            clearCurrentConversation()
        case .compact:
            compactContext(in: branchID)
        case .rename(let title):
            if let title {
                renameActiveConversation(to: title)
            } else {
                renameDraft = activeTitle
                isRenamePromptPresented = true
            }
        case .newConversation:
            startNewConversation()
        case .tree:
            enterCanvasMode()
        case .topic:
            conversationForTopicPicker = session.conversations.first { $0.id == session.activeConversationID }
        case .insights:
            withAnimation(.springQuick) {
                isInsightLibraryOpen = true
            }
        }
    }

    private func renameActiveConversation(to title: String) {
        guard session.rename(to: title) else { return }
        publishShellMenuState()
        persistConversations()
    }

    private func compactContext(in branchID: UUID) {
        Task {
            _ = await performContextCompaction(in: branchID)
        }
    }

    @MainActor
    private func performContextCompaction(in branchID: UUID) async -> Bool {
        guard !isCompactingContext,
              let branchIndex = session.activeBranches.firstIndex(where: { $0.id == branchID }) else {
            return false
        }

        let branch = session.activeBranches[branchIndex]
        let compactedBlockCount = min(
            branch.compactedThroughBlockCount ?? 0,
            branch.activeChatBlocks.count
        )
        var uncompactedTranscript: [ChatBlock] = []
        if branch.compactedContext == nil {
            let topQuestion = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if branch.topQuestionSubmitted, !topQuestion.isEmpty {
                uncompactedTranscript.append(
                    .user(topQuestion, branch.branchContextConcept, branch.topQuestionUploads)
                )
            }
        }
        uncompactedTranscript.append(
            contentsOf: branch.activeChatBlocks.dropFirst(compactedBlockCount)
        )

        guard !uncompactedTranscript.isEmpty else {
            return false
        }

        isCompactingContext = true
        defer { isCompactingContext = false }
        let context = ConversationContext(
            compactedContext: branch.compactedContext,
            transcript: uncompactedTranscript,
            personality: conversationPersonality
        )
        let compactedThroughBlockCount = branch.activeChatBlocks.count

        let summary = await angroveModel.compact(context)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled else { return false }
        guard !summary.isEmpty else {
            isCompactionErrorPresented = true
            return false
        }
        guard let currentIndex = session.activeBranches.firstIndex(where: { $0.id == branchID }) else {
            return false
        }
        session.activeBranches[currentIndex].compactedContext = summary
        session.activeBranches[currentIndex].compactedThroughBlockCount =
            min(compactedThroughBlockCount, session.activeBranches[currentIndex].activeChatBlocks.count)
        saveCurrentConversation()
        persistConversations()
        // Compaction succeeds silently: the context gauge drops immediately, which is the
        // feedback that matters. A full-screen confirmation interrupts the conversation to
        // report something the user can already see. Failure still alerts.
        refreshDisplayedContextWordCount()
        return true
    }

    private func refreshPersistedResponse(
        conversationID: UUID,
        branchID: UUID,
        responseIndex: Int
    ) {
        guard session.refreshPersistedResponse(
            conversationID: conversationID, branchID: branchID, responseIndex: responseIndex
        ) else { return }
        publishShellMenuState()
    }

    /// Copy activeBranches back into the conversations array for the active conversation.
    private func saveCurrentConversation() {
        session.saveActiveConversation(promotedInsightIDs: canvasMode.promotedCanvasInsightIDs)
    }

    /// New conversations exist only while the user is composing them. Once navigation leaves an
    /// untouched draft, discard it instead of letting an empty card accumulate in the list.
    /// A quoted Insight is first copied into the branch so it remains available after remounting.
    private func removeActiveConversationIfEmpty() {
        guard let id = session.activeConversationID,
              let index = session.conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let attachedConcept,
           let branchIndex = session.activeBranches.firstIndex(where: { $0.id == session.focusedBranchID })
                ?? session.activeBranches.indices.first {
            session.activeBranches[branchIndex].attachedConcept = attachedConcept
            session.activeBranches[branchIndex].showBottomInput = true
            self.attachedConcept = nil
        }
        saveCurrentConversation()

        let conversation = session.conversations[index]
        let hasSavedInsights = !manuallySavedConversationInsightIDs.isEmpty
            || !ConversationInsightMembershipStore.insightIDs(for: id).isEmpty
        guard !ConversationDraftRetention.shouldKeep(
            conversation,
            hasSavedInsights: hasSavedInsights
        ) else {
            return
        }

        ConversationInsightMembershipStore.removeConversation(id)
        LocalInsightTreeSeedStore.removeConversation(id)
        GlossedTermStore.removeConversation(id)
        FlaggedQuoteStore.removeConversation(id)
        session.conversations.remove(at: index)
        session.activeConversationID = session.conversations.first?.id
        manuallySavedConversationInsightIDs = []
        canvasMode.promotedCanvasInsightIDs = []
        publishShellMenuState()
    }

    /// Update the sideMenu bindings from the current conversations list.
    private func publishShellMenuState() {
        sideMenuConversations = session.conversations
        sideMenuActiveConversationID = session.activeConversationID
        sideMenuCurrentTitle = session.conversations.first { $0.id == session.activeConversationID }?.title ?? "New Conversation"
    }

    /// Save activeBranches → conversations, then switch to a different conversation.
    private func switchToConversation(_ conversation: InquiryConversation) {
        // Switching pages or conversations is navigation, not cancellation. Model jobs are
        // shell-owned and already carry their conversation ID, so let them finish and route their
        // result back to the originating conversation. Only destructive actions such as Clear
        // intentionally call `resetModelTaskPipeline()`.
        removeActiveConversationIfEmpty()
        session.activate(conversation)
        let nextBranches = session.activeBranches
        manuallySavedConversationInsightIDs =
            ConversationInsightMembershipStore.insightIDs(for: conversation.id)
        refreshDisplayedContextWordCount(animated: false)
        canvasMode.promotedCanvasInsightIDs = conversation.promotedInsightIDs
        restoreEmptyPromptState(from: nextBranches)
        pendingResponseCount = modelTasks.allTasks.filter { task in
            guard task.conversationID == conversation.id,
                  case .userQuestion = task.kind else {
                return false
            }
            return task.phase == .current || task.phase == .upcoming
        }.count
        definitionState.reset()
        modelTasksPopupState.reset()
        publishShellMenuState()
        persistConversations()
        scrollToEndOfConversationAfterLayout()
    }

    /// Reconstruct the special empty-conversation presentation after navigation. The visible
    /// prompt metadata is otherwise view-local, while its source tag and pinned question are
    /// persisted on the root branch so an unanswered Question of the Day survives remounting.
    private func restoreEmptyPromptState(from branches: [ChatBranch]) {
        guard let rootBranch = branches.first(where: { $0.parentBranchID == nil }),
              rootBranch.activeChatBlocks.isEmpty,
              !rootBranch.topQuestionSubmitted,
              let question = rootBranch.pinnedHeaderQuestion?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !question.isEmpty else {
            activeEmptyPromptEyebrow = ""
            activeEmptyPromptQuestion = ""
            activeEmptyPromptSubtitle = ""
            return
        }

        let context = rootBranch.hiddenPromptContext ?? ""
        if context.localizedCaseInsensitiveContains("<question of the day>") {
            activeEmptyPromptEyebrow = "QUESTION OF THE DAY"
            activeEmptyPromptQuestion = question
            activeEmptyPromptSubtitle = ""
        } else if context.localizedCaseInsensitiveContains("<today in history>") {
            activeEmptyPromptEyebrow = "TODAY IN HISTORY"
            activeEmptyPromptQuestion = question
            activeEmptyPromptSubtitle = ""
        } else {
            activeEmptyPromptEyebrow = ""
            activeEmptyPromptQuestion = ""
            activeEmptyPromptSubtitle = ""
        }
    }

    /// Reset the active conversation in place so study-topic membership and the
    /// conversation's identity remain stable while every question/response disappears.
    private func clearCurrentConversation() {
        persistenceTask?.cancel()
        resetModelTaskPipeline(conversationID: session.activeConversationID)
        let freshBranches = [ChatBranch(startingConcept: nil)]
        session.activeBranches = freshBranches
        session.focusedBranchID = freshBranches.first?.id
        displayedContextTokenCount = 0
        undiscoveredInsightCount = 0
        activeEmptyPromptEyebrow = ""
        activeEmptyPromptQuestion = ""
        activeEmptyPromptSubtitle = ""
        canvasMode.promotedCanvasInsightIDs = []
        attachedConcept = nil
        uploadedFiles.removeAll()
        hasTextToSubmit = false
        canvasMode.canvasConnectionConcepts = nil
        canvasMode.canvasQuoteTarget = nil
        canvasMode.canvasSelectedItemCount = 0

        if let id = session.activeConversationID,
           let index = session.conversations.firstIndex(where: { $0.id == id }) {
            ConversationInsightMembershipStore.removeConversation(id)
            LocalInsightTreeSeedStore.removeConversation(id)
            GlossedTermStore.removeConversation(id)
            FlaggedQuoteStore.removeConversation(id)
            manuallySavedConversationInsightIDs = []
            session.conversations[index].title = "New Conversation"
            session.conversations[index].branches = freshBranches
            session.conversations[index].promotedInsightIDs = []
        }

        publishShellMenuState()
        persistConversations()
        scrollToBottomAfterLayout()
    }

    /// Save current work, then create a fresh conversation and make it active.
    private func startNewConversation() {
        startNewConversation(NewConversationRequest())
    }

    private func startNewConversation(_ request: NewConversationRequest) {
        // Starting a new conversation is navigation, not cancellation: jobs already queued for
        // the conversation being left keep running and route their results back to it. Only the
        // per-conversation UI state is reset for the fresh conversation.
        pendingResponseCount = 0
        definitionState.reset()
        modelTasksPopupState.reset()
        removeActiveConversationIfEmpty()
        let pendingQuestion = request.question
        let pendingEyebrow = request.eyebrow
        let pendingPromptContext = request.promptContext
        let pendingSubtitle = request.subtitle
        var freshBranch = ChatBranch(
            startingConcept: nil,
            hiddenPromptContext: pendingPromptContext.isEmpty ? nil : pendingPromptContext
        )
        if ["QUESTION OF THE DAY", "TODAY IN HISTORY"].contains(pendingEyebrow), !pendingQuestion.isEmpty {
            freshBranch.pinnedHeaderQuestion = pendingQuestion
        }
        var fresh = InquiryConversation(isStudyTopic: request.isStudyTopic, studyTopicID: request.topicID)
        if let pinned = freshBranch.pinnedHeaderQuestion {
            fresh.title = pinned
        }
        session.conversations.insert(fresh, at: 0)
        session.activeConversationID = fresh.id
        manuallySavedConversationInsightIDs = []
        session.activeBranches = [freshBranch]
        activeEmptyPromptEyebrow = pendingEyebrow
        activeEmptyPromptQuestion = pendingQuestion
        activeEmptyPromptSubtitle = pendingSubtitle
        displayedContextTokenCount = 0
        hasTextToSubmit = false
        canvasMode.promotedCanvasInsightIDs = []
        session.focusedBranchID = session.activeBranches.first?.id
        if let quoteRequest = request.quote {
            attachedConcept = quoteRequest.insight
            // Set regardless of whether this came from a Study Topic or the global Insight
            // Tree (`topicID` nil either way is fine — `InsightConversationQuoteRequest`
            // already models it as optional) — removing the quoted chip should return to
            // whichever tree it came from with the Insight hovered; see
            // `returnToStudyTopicTreeAfterQuoteCancellation`'s topicID branch.
            pendingStudyTopicQuoteReturn = quoteRequest.insight.isLibraryQuote ? nil : InsightConversationQuoteRequest(
                topicID: quoteRequest.topicID,
                conversationID: fresh.id,
                insight: quoteRequest.insight
            )

            // Seed the on-device Insight Tree fallback from the quoted Insight itself rather
            // than waiting for the first question's answer to generate one — the quoted
            // Insight already *is* this conversation's subject. The first answer's own
            // new-subject check (embedding similarity against existing seeds) naturally skips
            // adding a redundant second seed when it's about the same thing, so this doesn't
            // need any special-casing on that side.
            let quotedConcept = quoteRequest.insight
            LocalInsightTreeSeedStore.appendSeed(
                LocalInsightTreeSeed(
                    id: UUID(),
                    label: quotedConcept.word,
                    summary: quotedConcept.semanticDefinition,
                    embedding: computeEmbedding(for: "\(quotedConcept.word). \(quotedConcept.semanticDefinition)"),
                    createdAt: Date()
                ),
                for: fresh.id
            )
        }
        publishShellMenuState()
        persistConversations()
        scrollToTopAfterLayout()
    }

    /// An untouched draft (e.g. an unanswered Question of the Day) is one viewport-tall prompt
    /// with a long scroll runway beneath it. Restoring it must land on the prompt, not the runway.
    private func scrollToEndOfConversationAfterLayout() {
        if isNewConversationPromptMode {
            scrollToTopAfterLayout()
        } else {
            scrollToBottomAfterLayout()
        }
    }

    private func scrollToBottomAfterLayout() {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            scrollToBottomRequest += 1
        }
    }

    private func scrollToTopAfterLayout() {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            isBranchScrolledToTop = true
            scrollToTopRequest += 1
        }
    }

    /// Persist the current conversations through the canonical file-backed repository.
    private func persistConversations() {
        session.persist()
    }

    // MARK: - Insight definition

    private func openDynamicDefinition(word: String, sourceResponseBlock: String?) {
        let insightWord = ConversationInsightWord(
            text: word,
            sourceResponseBlock: sourceResponseBlock
        )

        if definitionState.definitionsByKey[insightWord.id] != nil {
            presentDefinition(insightWord)
            return
        }

        guard !definitionState.lookupKeys.contains(insightWord.id) else { return }
        definitionState.lookupKeys.insert(insightWord.id)

        let conversationID = session.activeConversationID
        let context = definitionContext(sourceResponseBlock: sourceResponseBlock)
        Task {
            let cached = await angroveModel.cachedDefinition(
                for: word,
                in: context,
                conversationID: conversationID
            )
            // Always clear the lookup guard, even if the user switched conversations while
            // this was in flight — otherwise this term's key stays stuck in the lookup set
            // forever and every future tap on it silently no-ops.
            definitionState.lookupKeys.remove(insightWord.id)
            guard session.activeConversationID == conversationID else { return }

            if let cached {
                definitionState.definitionsByKey[insightWord.id] = stableDefinition(
                    cached,
                    requestedTerm: word
                )
                presentDefinition(insightWord)
            } else {
                enqueueDynamicDefinition(insightWord)
            }
        }
    }

    private func presentQuotedConcept(_ concept: ConceptDefinition) {
        let insightWord = ConversationInsightWord(text: concept.word, sourceResponseBlock: nil)
        definitionState.definitionsByKey[insightWord.id] = concept
        presentDefinition(insightWord)
    }

    /// Cancel only the conversation being left/cleared, not the whole shared queue — a
    /// different conversation's still-running job must survive navigating away from it.
    private func resetModelTaskPipeline(conversationID: UUID?) {
        modelTasks.cancelTasks {
            !$0.kind.isInsightTreeTask && $0.conversationID == conversationID
        }
        modelTasks.clearCompletedTasks()
        modelTasksPopupState.reset()
        pendingResponseCount = 0
        definitionState.reset()
    }

    private func enqueueDynamicDefinition(_ word: ConversationInsightWord) {
        guard !modelTasks.contains(where: {
            $0.kind.definitionKey == word.id && $0.phase != .completed
        }) else {
            return
        }

        modelTasks.enqueue(
            kind: .defineInsight(key: word.id, name: word.text),
            originPage: .conversation,
            conversationID: session.activeConversationID,
            onStart: {
                definitionState.sheetContentHeight = 178
                definitionState.loadingWord = word
            },
            onCancel: {
                if definitionState.loadingWord == word {
                    definitionState.loadingWord = nil
                }
            }
        ) {
            await requestDynamicDefinition(
                for: word.text,
                sourceResponseBlock: word.sourceResponseBlock
            )
        }
    }

    // Routes through the live AngroveModel's contextual-definition call.
    private func requestDynamicDefinition(for word: String, sourceResponseBlock: String?) async {
        let conversationID = session.activeConversationID
        let completedWord = ConversationInsightWord(text: word, sourceResponseBlock: sourceResponseBlock)

        let defined: ConceptDefinition
        do {
            defined = try await angroveModel.defineTerm(
                word,
                in: definitionContext(sourceResponseBlock: sourceResponseBlock),
                conversationID: conversationID
            )
        } catch {
            guard !Task.isCancelled else { return }
            if definitionState.loadingWord == completedWord {
                definitionState.loadingWord = nil
            }
            definitionState.failedWord = completedWord
            return
        }
        guard !Task.isCancelled else { return }
        guard definitionState.loadingWord == completedWord else { return }

        // Re-stamp with a stable, term-derived id — the model assigns content, never identity
        // (see ConceptDefinition.stableID(forTerm:)) — so re-saving the same term always dedups.
        let stable = stableDefinition(defined, requestedTerm: word)
        definitionState.definitionsByKey[completedWord.id] = stable
        definitionState.loadingWord = nil
        if let conversationID {
            GlossedTermStore.recordLookup(stable, requestedTerm: word, in: conversationID)
        }

        postDefinitionCompletedNotification(completedWord)
    }

    private func definitionContext(sourceResponseBlock: String?) -> ConversationContext {
        guard let sourceResponseBlock else {
            return ConversationContext()
        }
        return ConversationContext(
            transcript: [.text(ResponseTextFormatting.definitionContext(from: sourceResponseBlock))]
        )
    }

    private func stableDefinition(
        _ definition: ConceptDefinition,
        requestedTerm: String
    ) -> ConceptDefinition {
        ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: requestedTerm),
            word: definition.word.capitalized,
            partOfSpeech: definition.partOfSpeech,
            pronunciation: definition.pronunciation,
            meaning: definition.meaning,
            example: definition.example,
            definitions: definition.contextualDefinitions
        )
    }

    private func presentDefinition(_ word: ConversationInsightWord) {
        definitionState.present(word)
    }

    private func postDefinitionCompletedNotification(_ word: ConversationInsightWord) {
        let title = definitionState.definitionsByKey[word.id]?.word ?? word.text.capitalized
        modelCompletionNotifications?.post(title: title, kind: .insightDefinition) {
            onRequestConversationPage()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard definitionState.definitionsByKey[word.id] != nil else { return }
                presentDefinition(word)
            }
        }
    }

    private func presentNextCompletedDefinition() {
        guard let nextWord = definitionState.takeNextCompletedWord() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard definitionState.activeWord == nil else { return }
            definitionState.activeWord = nextWord
        }
    }

    private func toggleSavedConcept(_ concept: ConceptDefinition) {
        let shouldSave = !collectedDefinitions.contains {
            $0.id == concept.id && $0.containsDefinitions(from: concept)
        }
        setSavedConcept(concept, isSaved: shouldSave)
    }

    private func setSavedConcept(_ concept: ConceptDefinition, isSaved: Bool) {
        let wasSavedToConversation = manuallySavedConversationInsightIDs.contains(concept.id)
        let existingConcept = collectedDefinitions.first { $0.id == concept.id }
        let conceptToSave = existingConcept?.mergingDefinitions(from: concept) ?? concept

        withAnimation(.springBouncy) {
            if isSaved {
                if let existingIndex = collectedDefinitions.firstIndex(
                    where: { $0.id == concept.id }
                ) {
                    collectedDefinitions[existingIndex] = conceptToSave
                } else {
                    collectedDefinitions.append(conceptToSave)
                }
            } else {
                collectedDefinitions.removeAll { $0.id == concept.id }
            }
        }

        guard let conversationID = session.activeConversationID else { return }
        if isSaved {
            ConversationInsightMembershipStore.add(
                insightID: concept.id,
                to: conversationID
            )
            manuallySavedConversationInsightIDs.insert(concept.id)

            if !wasSavedToConversation {
                InsightDiscoveryStore.markUndiscovered([concept.id])
                undiscoveredInsightCount = InsightDiscoveryStore.visibleUndiscoveredCount(
                    for: conversationInsights.map(\.id)
                )
            }
        } else {
            ConversationInsightMembershipStore.remove(
                insightID: concept.id,
                from: conversationID
            )
            manuallySavedConversationInsightIDs.remove(concept.id)
        }
        if isSaved && !wasSavedToConversation {
            InsightDiscoveryStore.markPendingTreePresentation(insightIDs: [concept.id], nodeIDs: [])
        }
        if !canvasMode.isTopicCanvasVisible {
            insightTreeUpdateSignal += 1
        }
    }

    private func removeConversationInsight(_ concept: ConceptDefinition) {
        guard let conversationID = session.activeConversationID else { return }
        ConversationInsightMembershipStore.remove(
            insightID: concept.id,
            from: conversationID
        )
        manuallySavedConversationInsightIDs.remove(concept.id)
    }

    private func restoreConversationInsight(_ concept: ConceptDefinition) {
        guard let conversationID = session.activeConversationID else { return }
        ConversationInsightMembershipStore.add(
            insightID: concept.id,
            to: conversationID
        )
        manuallySavedConversationInsightIDs.insert(concept.id)
    }
}
