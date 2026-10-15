import SwiftUI

/// Publishes the shared iPhone controls for one Mac workspace slot. Both slots use
/// the same runtime and queue, with independent popup presentation state.
struct MacConversationDock: View {
    let session: MacConversationState
    let tree: MacTreeControls
    let runtime: MacApplicationRuntime
    let isCanvasMode: Bool
    let hasQuestion: Bool
    let onOpenTree: () -> Void
    let onCloseTree: () -> Void
    var isGlobal = false
    let onSend: () -> Void
    var onClearDraft: () -> Void = {}
    var isAsking = false
    var onAsk: (() -> Void)? = nil
    var onAskNew: () -> Void = {}
    var onAskExisting: () -> Void = {}
    var onCancelAsk: () -> Void = {}
    var queuePopup: ModelTasksPopupState? = nil
    var onActivity: () -> Void = {}
    var contextToggleRequest: Binding<UUID?> = .constant(nil)
    @State private var context = ContextCardState()
    @State private var popup = ModelTasksPopupState()
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showPassages = false
    @State private var personality = "default"
    @State private var personalityMenu = false

    var body: some View {
        @Bindable var tree = tree
        InquiryControlDock(
            isCanvasMode: isCanvasMode,
            showFilePicker: $showFilePicker, showPhotoPicker: $showPhotoPicker, showCamera: $showCamera,
            selectedPersonality: $personality, isPersonalityMenuOpen: $personalityMenu,
            isAtBottom: true, showsModelControlsInCanvasMode: true,
            showsSendButton: false, showsAttachments: !isCanvasMode,
            hasCanvasHover: tree.hasHover, hasCanvasInsightHover: tree.hasInsightHover,
            hasSelectedCanvasItems: tree.selectedCount > 0, selectedCanvasItemCount: tree.selectedCount,
            onScrollToBottom: {}, onViewEntireCanvas: onCloseTree,
            onOpenInsights: onOpenTree, onOpenPassages: { showPassages = true }, onSend: onSend,
            onSelectCanvasItem: { onActivity(); tree.selectionRequest += 1 },
            onCreateCanvasConcept: { onActivity(); tree.createConceptRequest += 1 },
            onStudyCanvasInsight: { onActivity(); tree.studyRequest += 1 },
            onInquireConnection: { onActivity(); tree.inquireConnectionRequest += 1 },
            onQuoteCanvasItem: {
                onActivity()
                if let onAsk { onAsk() }
                else if let concept = tree.hoveredConcept { session.attachQuote(concept); tree.dismissHoverRequest += 1 }
            },
            usesCanvasAskFlow: isGlobal, isCanvasAskMode: isAsking,
            onAskInNewConversation: onAskNew, onAskInExistingConversation: onAskExisting,
            onCancelCanvasAsk: onCancelAsk,
            onMidpointConcepts: { onActivity(); tree.midpointEnterRequest += 1 },
            isMidpointMode: tree.isMidpoint, isStudyMode: tree.isStudy,
            isStudyToolsActive: tree.studyToolsOpen,
            onToggleStudyTools: { onActivity(); tree.studyToolsRequest += 1 },
            studyBranchCount: tree.studyBranchCount,
            onStudyBranchCountChange: { onActivity(); tree.studyBranchCount = $0 },
            onStudyBranchConfirm: { onActivity(); tree.studyBranchConfirmRequest += 1 },
            isCanvasInsightLoading: tree.isGenerating,
            modelTasks: runtime.modelTasks, modelTasksPopupState: queuePopup ?? popup, keepsIdleModelStatus: true,
            canvasSearchText: $tree.searchQuery, isCanvasSearchActive: $tree.searchActive,
            canvasSearchResultIndex: tree.searchIndex, canvasSearchResultCount: tree.searchCount,
            onCanvasSearchPrevious: { onActivity(); tree.searchPreviousRequest += 1 },
            onCanvasSearchNext: { onActivity(); tree.searchNextRequest += 1 },
            onCanvasSearchActivated: { onActivity(); tree.dismissHoverRequest += 1 },
            onModelStatusTap: onActivity,
            onMidpointCenter: { onActivity(); tree.midpointCenterRequest += 1 },
            onMidpointPlace: { onActivity(); tree.midpointPlaceRequest += 1 },
            onClearCanvasSelection: { onActivity(); tree.clearSelectionRequest += 1 },
            contextWordCount: session.contextTokenCount, showsContextWheel: !isGlobal && !isCanvasMode, showsContextInCanvasMode: false,
            canCompactContext: runtime.modelIsAvailable && session.canCompactContext,
            onCompactContext: { await session.compact(runtime: runtime) },
            onClearConversation: { session.clear(runtime: runtime); onClearDraft() }, contextCard: context,
            contextToggleRequest: contextToggleRequest,
            surfaceID: isCanvasMode ? "mac-tree" : "mac-conversation"
        )
        .onChange(of: (queuePopup ?? popup).isOpen) { _, isOpen in
            if isOpen { context.reset() }
        }
        .onChange(of: isCanvasMode) { _, _ in
            context.reset()
            (queuePopup ?? popup).isOpen = false
            personalityMenu = false
        }
        .modifier(MacAttachmentPickers(showsFiles: $showFilePicker, showsPhotos: $showPhotoPicker) { files in
            withAnimation(.springLively) { session.attach(files) }
        })
        .sheet(isPresented: $showPassages) {
            VStack(alignment: .leading, spacing: 20) {
                MacPageHeading(title: "Clipped Passages")
                let passages = ClippedPassageStore.load()
                if passages.isEmpty {
                    Text("No clipped passages yet.").font(AngroveTheme.Typography.body).settingsTextReveal()
                }
                ForEach(passages) { passage in
                    Button(passage.word) { session.attachQuote(passage); showPassages = false }
                }
                Button("Done") { showPassages = false }
            }.padding(28).frame(minWidth: 320).background(AngroveTheme.Colors.canvas)
        }
    }
}

/// A persistent controls host for the main or secondary slot. Its preference boundary
/// keeps the two publishers separate; only the tree slot receives the canvas's card.
struct MacWorkspaceControlSlot: View {
    let session: MacConversationState
    let tree: MacTreeControls
    let runtime: MacApplicationRuntime
    let isCanvasMode: Bool
    let isVisible: Bool
    let hasQuestion: Bool
    let treeCard: ModelControlsDockedCard?
    let onOpenTree: () -> Void
    let onCloseTree: () -> Void
    let onSend: () -> Void
    let onClearDraft: () -> Void
    var queuePopup: ModelTasksPopupState? = nil
    var onActivity: () -> Void = {}
    var contextToggleRequest: Binding<UUID?> = .constant(nil)
    @Environment(\.macPageControlsVisible) private var pageControlsVisible

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .background {
                MacConversationDock(session: session, tree: tree, runtime: runtime,
                                    isCanvasMode: isCanvasMode, hasQuestion: hasQuestion,
                                    onOpenTree: onOpenTree, onCloseTree: onCloseTree,
                                    onSend: onSend, onClearDraft: onClearDraft, queuePopup: queuePopup, onActivity: onActivity,
                                    contextToggleRequest: isCanvasMode ? .constant(nil) : contextToggleRequest)
            }
            .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { configuration in
                ModelControlsHost(configuration: presentedConfiguration(configuration))
            }
            .transformPreference(ModelControlsPreferenceKey.self) { $0 = nil }
    }

    private func presentedConfiguration(_ configuration: ModelControlsConfiguration?) -> ModelControlsConfiguration? {
        guard isVisible, pageControlsVisible, var configuration else { return nil }
        configuration.dockedCard = isCanvasMode ? treeCard : nil
        return configuration
    }
}

struct MacTreeHeaderButton: View {
    let symbol: String
    let label: String
    var isActive = false
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol)
                    .id(symbol)
                    .transition(.blurFade)
            }
            .animation(.springStandard, value: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.lightGreen)
            .frame(minWidth: 48, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $pressed))
        .pulsesOnChange(of: symbol)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct MacTreeToggleButton: View {
    let isOpen: Bool
    var isSwapped = false
    let updateSignal: Int
    let action: () -> Void
    @State private var showsUpdated = false
    @State private var pulseScale: CGFloat = 1
    @State private var dismissalTask: Task<Void, Never>?
    @State private var pulseTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        isOpen ? "xmark" : (isSwapped ? MacIcon.conversations.symbol : "point.3.connected.trianglepath.dotted")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: symbol)
                        .id(symbol)
                        .transition(reduceMotion ? .opacity : .blurFade)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(width: 18, height: 18)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.28), value: symbol)
                if showsUpdated && !isOpen {
                    Text("Updated")
                        .font(.figtreeChipLabel)
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                        .transition(.blurFade)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 48)
            .contentShape(Capsule())
            .background(AngroveTheme.Colors.canvasSecondary.opacity(!isOpen && isSwapped ? 1 : 0), in: Capsule())
            .overlay(Capsule().strokeBorder(AngroveTheme.Colors.controlBorder.opacity(!isOpen && isSwapped ? 1 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(pulseScale)
        .accessibilityLabel(isOpen ? (isSwapped ? "Close Conversation Pane" : "Close Insight Tree") : (isSwapped ? "Open Conversation Pane" : "Open Insight Tree"))
        .help(isOpen ? "Close the secondary pane" : "Open the secondary pane at its last width")
        .onChange(of: symbol) { _, _ in
            dismissalTask?.cancel()
            pulseTask?.cancel()
            showsUpdated = false
            pulseScale = 1
        }
        .onChange(of: updateSignal) { old, new in
            guard new > old, !isOpen else { return }
            dismissalTask?.cancel()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { showsUpdated = true }
            pulse()
            dismissalTask = Task {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                pulse()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { showsUpdated = false }
            }
        }
        .onDisappear { dismissalTask?.cancel(); pulseTask?.cancel() }
    }

    private func pulse() {
        guard !reduceMotion else { return }
        pulseTask?.cancel()
        pulseTask = Task {
            withAnimation(.easeInOut(duration: 0.14)) { pulseScale = 1.05 }
            do { try await Task.sleep(for: .seconds(0.14)) } catch { return }
            withAnimation(.easeInOut(duration: 0.14)) { pulseScale = 1 }
        }
    }
}
