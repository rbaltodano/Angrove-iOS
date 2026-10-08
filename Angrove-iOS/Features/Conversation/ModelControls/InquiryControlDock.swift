//
//  InquiryControlDock.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

/// A single persistent control surface whose contents adapt to Branch and Canvas mode.
struct InquiryControlDock: View {
    let isCanvasMode: Bool
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let isAtBottom: Bool
    var showsModelControlsInCanvasMode: Bool = false
    var isKeyboardOpen: Bool = false
    var showsSendButton: Bool = false
    var hasCanvasHover: Bool = false
    var hasCanvasInsightHover: Bool = false
    var hasSelectedCanvasItems: Bool = false
    var selectedCanvasItemCount: Int = 0
    var onScrollToBottom: () -> Void
    var onViewEntireCanvas: () -> Void
    var onOpenInsights: () -> Void
    var onOpenPassages: () -> Void = {}
    var onSend: () -> Void = {}
    var onSelectCanvasItem: () -> Void = {}
    var onCreateCanvasConcept: () -> Void = {}
    var onStudyCanvasInsight: () -> Void = {}
    var onInquireConnection: () -> Void = {}
    var onQuoteCanvasItem: () -> Void = {}
    /// Global and Study Topic trees use a two-step Ask flow instead of quoting immediately.
    var usesCanvasAskFlow: Bool = false
    var isCanvasAskMode: Bool = false
    var onAskInNewConversation: () -> Void = {}
    var onAskInExistingConversation: () -> Void = {}
    var onCancelCanvasAsk: () -> Void = {}
    var onMidpointConcepts: () -> Void = {}
    var isMidpointMode: Bool = false
    /// In Study the dock keeps its tree controls, with Tools in place of Study.
    var isStudyMode: Bool = false
    /// Study's tools are open (the Tools button shows light green).
    var isStudyToolsActive: Bool = false
    var onToggleStudyTools: () -> Void = {}
    /// Follows `isStudyMode`, except that leaving Study first tucks Place away (the reverse of
    /// its entrance) before the normal controls return.
    private var showsStudyControls: Bool { isStudyMode && isStudyToolsActive }
    @State private var isLeavingStudy = false
    var studyBranchCount: Int = 2
    var onStudyBranchCountChange: (Int) -> Void = { _ in }
    var onStudyBranchConfirm: () -> Void = {}
    /// While a placed midpoint insight is generating, the dock hides its canvas actions.
    var isCanvasInsightLoading: Bool = false
    /// Status for background canvas work that does not run through `ModelTaskQueue`.
    var modelStatusOverride: String? = nil
    /// Shared serialized model work. Drives both the status control and its task popup.
    var modelTasks: ModelTaskQueue? = nil
    var modelTasksPopupState: ModelTasksPopupState? = nil
    /// Conversation threads retain Idle; standalone trees show status only during work.
    var keepsIdleModelStatus: Bool = false
    var onAttachRecentPhoto: ((Data) -> Void)? = nil
    /// Owned by the conversation so a tap on its thread can close the recent-photos card.
    var recentPhotosOpen: Binding<Bool> = .constant(false)
    var canvasSearchText: Binding<String>? = nil
    var isCanvasSearchActive: Binding<Bool>? = nil
    var canvasSearchResultIndex: Int = 0
    var canvasSearchResultCount: Int = 0
    var onCanvasSearchPrevious: () -> Void = {}
    var onCanvasSearchNext: () -> Void = {}
    var onCanvasSearchActivated: () -> Void = {}
    var onModelStatusTap: () -> Void = {}
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var onMidpointCenter: () -> Void = {}
    var onMidpointPlace: () -> Void = {}
    var onClearCanvasSelection: () -> Void = {}
    var contextWordCount: Int = 0
    var contextWordLimit: Int = angroveContextWindowLimit
    /// The context gauge belongs to an active conversation, not standalone tree canvases.
    var showsContextWheel: Bool = true
    var canCompactContext: Bool = false
    var onCompactContext: () async -> Bool = { false }
    var onClearConversation: () -> Void = {}
    var onContextWillOpen: () -> Void = {}
    /// Owned by the hosting screen so Context state survives control-layout changes.
    let contextCard: ContextCardState

    @State private var canvasActionDrawID = UUID()
    @State private var isScrollButtonVisible = false
    @State private var isControlButtonPressed = false
    private var isRecentPhotosOpen: Bool {
        get { recentPhotosOpen.wrappedValue }
        nonmutating set { recentPhotosOpen.wrappedValue = newValue }
    }
    @State private var addFlashOpacity: CGFloat = 1
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed

    /// Flash the Add button while in Select mode with an insight hovered, hinting it can be added.
    private var shouldFlashAdd: Bool {
        canAddCanvasSelection && hasCanvasHover
    }

    private var canAddCanvasSelection: Bool {
        hasSelectedCanvasItems && selectedCanvasItemCount < CanvasSelectionPolicy.maximumCount
    }

    private func startAddFlashIfNeeded() {
        if shouldFlashAdd {
            addFlashOpacity = 1
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                addFlashOpacity = 0.5
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { addFlashOpacity = 1 }
        }
    }

    /// While a placed midpoint is generating AND nothing else is hovered/selected, canvas
    /// actions are hidden while Model Status and the context gauge remain visible.
    private var isLoadingCollapsed: Bool {
        isCanvasMode && isCanvasInsightLoading && !hasCanvasHover && !hasSelectedCanvasItems
    }

    private var showsAttachmentControl: Bool {
        (!isCanvasMode || showsModelControlsInCanvasMode) && !isCanvasAskMode && !showsStudyControls
    }

    private var showsModelStatusControl: Bool {
        !showsStudyControls && activityDisplay != .hidden
            && modelTasks != nil
            && (keepsIdleModelStatus || modelTasks?.isBusy == true || modelStatusOverride != nil)
            && !(isCanvasMode && (
                hasCanvasHover
                    || hasSelectedCanvasItems
                    || isMidpointMode
                    || isCanvasAskMode
            ))
    }

    private var canvasSearchIsActive: Bool {
        isCanvasSearchActive?.wrappedValue == true
    }

    private var showsCanvasSearchControl: Bool {
        isCanvasMode
            && canvasSearchText != nil
            && isCanvasSearchActive != nil
            && !hasCanvasHover
            && !hasSelectedCanvasItems
            && !isMidpointMode
            && !isCanvasInsightLoading
            && !isCanvasAskMode
            && !isStudyMode
    }

    private var showsContextControl: Bool {
        showsContextWheel
            && !showsStudyControls
            && !isCanvasMode
    }

    private var controlCount: Int {
        if showsStudyControls { return 2 }
        if isCanvasMode && isCanvasAskMode {
            return 3
        }
        if isLoadingCollapsed {
            return (showsModelStatusControl ? 1 : 0) + (showsContextControl ? 1 : 0)
        }
        if isCanvasMode && isMidpointMode {
            return (showsModelStatusControl ? 1 : 0) + 2
                + (showsContextControl ? 1 : 0) + 1
        }
        let attachmentCount = showsAttachmentControl ? 1 : 0
        let modelStatusCount = showsModelStatusControl ? 1 : 0
        let searchCount = showsCanvasSearchControl ? 1 : 0
        let canvasActionCount: Int
        if !isCanvasMode {
            canvasActionCount = 0
        } else if isStudyMode {
            canvasActionCount = (hasCanvasHover ? 1 : 0) + (hasCanvasInsightHover ? 1 : 0) // Ask + Branch
        } else if hasSelectedCanvasItems {
            if hasCanvasHover {
                canvasActionCount = canAddCanvasSelection ? 1 : 0
            } else if selectedCanvasItemCount >= 2 {
                canvasActionCount = 3 // Inquire + Midpoint + Study
            } else {
                canvasActionCount = 1 // Select only
            }
        } else if hasCanvasHover {
            canvasActionCount = 3 // Select + Ask + Study (Insights and Node Concepts)
        } else {
            canvasActionCount = 0
        }
        let selectionCancelCount = isCanvasMode && hasSelectedCanvasItems && !isStudyMode ? 1 : 0
        return attachmentCount + searchCount + modelStatusCount + canvasActionCount
            + selectionCancelCount + (showsContextControl ? 1 : 0)
            + (showsSendButton ? 1 : 0)
    }

    /// Captures everything that changes the dock's visible controls — including swaps that
    /// keep the same control count but change content width (e.g. the "Add" button ↔ the
    /// "Tap another Insight" hint) — so the capsule resizes with the same spring + scale bump.
    private var controlLayoutKey: String {
        let statusKey = modelStatusOverride ?? "idle"
        return "\(controlCount)|\(modelTaskCounterKey)|\(statusKey)|\(showsStudyControls ? 1 : 0)|\(studyBranchCount)|\(isMidpointMode ? 1 : 0)|\(isCanvasInsightLoading ? 1 : 0)|\(hasCanvasHover ? 1 : 0)|\(hasCanvasInsightHover ? 1 : 0)|\(selectedCanvasItemCount)|\(showsSendButton ? 1 : 0)|\(canvasSearchIsActive ? 1 : 0)|\(isCanvasAskMode ? 1 : 0)|\(isStudyMode ? 1 : 0)|\(isStudyToolsActive ? 1 : 0)"
    }

    /// Explicitly keys the pill's resize and 5% pulse to the fraction shown by Model Status.
    private var modelTaskCounterKey: String {
        guard let modelTasks, modelTasks.isBusy else { return "idle" }
        return "\(modelTasks.currentPosition)/\(modelTasks.totalCount)"
    }

    /// Some parent views (`CurrentConversationView`, Study Topic trees) mount this invisibly;
    /// the visible bar is the shell's single `ModelControlsHost`.
    var surfaceID: String = "conversation"
    var priority: Int = 1
    var maxWidth: CGFloat? = nil
    var alignment: Alignment = .center

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .modelControls(configuration)
            .onAppear {
                isScrollButtonVisible = !isAtBottom
            }
            .onReceive(NotificationCenter.default.publisher(for: .aquinasMiniScrollButtonVisibilityChanged)) { notification in
                guard let isVisible = notification.userInfo?["isVisible"] as? Bool else { return }
                isScrollButtonVisible = isVisible
            }
            .onChange(of: hasCanvasHover) { _, selected in
                if selected { canvasActionDrawID = UUID() }
            }
            .onChange(of: hasCanvasInsightHover) { _, isHoveringInsight in
                if isHoveringInsight { dismissContextPopup() }
            }
            .onChange(of: hasSelectedCanvasItems) { _, isSelecting in
                if isSelecting { dismissContextPopup() }
            }
            .onChange(of: isCanvasAskMode) { _, isAsking in
                guard isAsking else { return }
                dismissContextPopup()
                modelTasksPopupState?.reset()
                isCanvasSearchActive?.wrappedValue = false
            }
            .onDisappear {
                contextCard.compactTask?.cancel()
                isRecentPhotosOpen = false
            }
    }

    private var configuration: ModelControlsConfiguration {
        ModelControlsConfiguration(
            id: surfaceID,
            priority: priority,
            showsScrollToBottom: !isCanvasMode && isScrollButtonVisible,
            onScrollToBottom: onScrollToBottom,
            contextCard: contextCard,
            contextWordCount: contextWordCount,
            contextWordLimit: contextWordLimit,
            canCompactContext: canCompactContext,
            onCompactContext: onCompactContext,
            onClearConversation: onClearConversation,
            modelTasksPopupState: modelTasksPopupState,
            modelTasks: modelTasks,
            // Image and file inputs, including the recent-photo shortcut, are post-launch.
            supplementalPopupIsOpen: false,
            supplementalPopup: nil,
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirm,
            onDecline: onDecline,
            controlsUpdateKey: controlLayoutKey,
            buttons: controlCount > 0 ? AnyView(buttons) : nil,
            pillHorizontalPadding: showsStudyControls ? 0 : (isCanvasAskMode ? 16 : 32),
            pillVerticalPadding: showsStudyControls ? 0 : 24,
            showsPillChrome: !showsStudyControls,
            isControlButtonPressed: isControlButtonPressed,
            pillReplacement: canvasSearchIsActive
                ? canvasSearchText.map { AnyView(expandedCanvasSearchBar(text: $0)) }
                : nil,
            bottomPadding: isKeyboardOpen ? 8 : 24,
            maxWidth: maxWidth,
            alignment: alignment
        )
    }

    private var buttons: some View {
        HStack(alignment: .center, spacing: isCanvasAskMode ? 12 : 24) {
        if showsAttachmentControl {
            attachmentButton
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }

        if showsCanvasSearchControl {
            canvasSearchButton
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }

        if showsModelStatusControl, let modelTasks {
            if let modelStatusOverride {
                ModelStatusButton(
                    modelTasks: modelTasks,
                    action: {},
                    controlIsPressed: $isControlButtonPressed,
                    statusOverride: modelStatusOverride
                )
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                ModelStatusButton(
                    modelTasks: modelTasks,
                    action: handleModelStatusTap,
                    controlIsPressed: $isControlButtonPressed
                )
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }

        if isCanvasMode && showsStudyControls {
            StudyBranchDockControls(
                count: studyBranchCount,
                onCountChange: onStudyBranchCountChange,
                isLeaving: isLeavingStudy,
                isBusy: isCanvasInsightLoading,
                onConfirm: onStudyBranchConfirm
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else if isCanvasMode && isCanvasAskMode {
            canvasActionButton(
                title: "New Conversation",
                icon: "plus.bubble",
                action: onAskInNewConversation
            )
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            canvasActionButton(
                title: "Existing Conversation",
                icon: "bubble.left.and.bubble.right",
                action: onAskInExistingConversation
            )
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            cancelCanvasAskButton
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        } else if isLoadingCollapsed {
            // Generating a placed midpoint, nothing hovered — keep only status + context.
            EmptyView()
        } else if isCanvasMode && isMidpointMode {
            canvasActionButton(title: "Center", icon: "lines.measurement.horizontal", action: onMidpointCenter)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            canvasActionButton(title: "Place", icon: "arrow.down", action: onMidpointPlace)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        } else if isCanvasMode && isStudyMode {
            // Only an Insight offers Branch; studying a Node retains its Ask action.
            if hasCanvasHover {
                canvasActionButton(title: "Ask", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if hasCanvasInsightHover {
                studyToolsButton
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        } else if isCanvasMode && (hasCanvasHover || hasSelectedCanvasItems) {
            if hasSelectedCanvasItems && hasCanvasHover {
                // Selection mode + hovering an addable insight/node:
                // the Add button is the only control present.
                if canAddCanvasSelection {
                    selectCanvasActionButton
                        .opacity(shouldFlashAdd ? addFlashOpacity : 1)
                        .onAppear { startAddFlashIfNeeded() }
                        .onChange(of: shouldFlashAdd) { _, _ in startAddFlashIfNeeded() }
                }
            } else if hasSelectedCanvasItems {
                // Selection mode, nothing hovered: hint (1 selected) or the
                // selection actions (Inquire, Midpoint, and Study).
                if selectedCanvasItemCount == 1 {
                    Text("Tap another Insight for actions")
                        .font(.custom("Figtree-Bold", size: 14))
                        .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
                        .fixedSize()
                        .transition(.opacity)
                } else if selectedCanvasItemCount == 2 {
                    canvasActionButton(title: "Inquire", icon: "point.3.connected.trianglepath.dotted", action: onInquireConnection)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Study", icon: "graph.3d", action: onStudyCanvasInsight)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    canvasActionButton(title: "Inquire", icon: "point.3.connected.trianglepath.dotted", action: onInquireConnection)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Study", icon: "graph.3d", action: onStudyCanvasInsight)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            } else {
                // No selection yet — entry point while hovering an insight/node.
                selectCanvasActionButton
                // Study opens for a hovered Insight or Node Concept.
                if hasCanvasHover {
                    canvasActionButton(title: "Ask", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Study", icon: "graph.3d", action: onStudyCanvasInsight)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
        }

        if isCanvasMode && hasSelectedCanvasItems && !isCanvasAskMode && !showsStudyControls && !isStudyMode {
            clearCanvasSelectionButton
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }

        if showsContextControl {
            contextButton
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }

        if showsSendButton {
            sendButton
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
        }
    }

    private var canvasSearchButton: some View {
        Button(action: activateCanvasSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))

                Text("Search")
                    .font(.custom("Figtree-SemiBold", size: 14))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
            .frame(minHeight: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Search Insights")
    }

    private func expandedCanvasSearchBar(text: Binding<String>) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Button(action: dismissCanvasSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AngroveTheme.Colors.placeholderText)
                }
                .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
                .accessibilityLabel("Dismiss Insight search")

                CanvasSearchTextField(text: text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 9) {
                Button(action: onCanvasSearchPrevious) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 14, height: 14)
                }
                .disabled(canvasSearchResultCount == 0)
                .accessibilityLabel("Previous search result")

                Text(searchResultFraction)
                    .font(.custom("Figtree-SemiBold", size: 14))
                    .monospacedDigit()
                    .fixedSize()

                Button(action: onCanvasSearchNext) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 14, height: 14)
                }
                .disabled(canvasSearchResultCount == 0)
                .accessibilityLabel("Next search result")
            }
            .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
            .foregroundColor(AngroveTheme.Colors.placeholderText)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
        .modifier(FloatingControlPressFeedback(isButtonPressed: isControlButtonPressed))
    }

    private var searchResultFraction: String {
        guard canvasSearchResultCount > 0 else { return "0/0" }
        return "\(max(canvasSearchResultIndex, 1))/\(canvasSearchResultCount)"
    }

    private func activateCanvasSearch() {
        dismissContextPopup()
        onCanvasSearchActivated()
        withAnimation(.easeInOut(duration: 0.24)) {
            isCanvasSearchActive?.wrappedValue = true
        }
    }

    private func dismissCanvasSearch() {
        canvasSearchText?.wrappedValue = ""
        withAnimation(.easeInOut(duration: 0.24)) {
            isCanvasSearchActive?.wrappedValue = false
        }
    }

    @ViewBuilder
    private var attachmentButton: some View {
        if onAttachRecentPhoto != nil {
            PhotoAttachmentControl(
                isPressed: $isControlButtonPressed,
                onInsights: { isRecentPhotosOpen = false; onOpenInsights() },
                onPassages: { isRecentPhotosOpen = false; onOpenPassages() }
            )
        } else {
        Menu {
            Button {
                isRecentPhotosOpen = false
                onOpenInsights()
            } label: {
                Label("Insights", systemImage: "text.bubble")
            }

            Button {
                isRecentPhotosOpen = false
                onOpenPassages()
            } label: {
                Label("Passages", systemImage: "books.vertical")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        }
    }

    private var contextButton: some View {
        Button {
            guard !contextCard.isCompacting else { return }
            withAnimation(.springStandard) { isRecentPhotosOpen = false }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            contextCard.dragY = 0
            if contextCard.isOpen {
                withAnimation(.springStandard) {
                    contextCard.isOpen = false
                }
                return
            }
            let otherWasOpen = modelTasksPopupState?.isOpen == true
            onContextWillOpen()
            switchPopups(
                otherIsOpen: otherWasOpen,
                closeOther: { modelTasksPopupState?.isOpen = false },
                openThis: { contextCard.isOpen = true }
            )
        } label: {
            let contextColor = AngroveTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                ContextUsageIcon(progress: contextProgress, color: contextColor)
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(contextColor)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Conversation context")
    }

    private func handleModelStatusTap() {
        guard !contextCard.isCompacting, let modelTasksPopupState else { return }
        withAnimation(.springStandard) { isRecentPhotosOpen = false }
        if modelTasksPopupState.isOpen {
            withAnimation(.springStandard) {
                modelTasksPopupState.isOpen = false
            }
            return
        }
        let otherWasOpen = contextCard.isOpen
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
        onModelStatusTap()
        switchPopups(
            otherIsOpen: otherWasOpen,
            closeOther: { contextCard.reset() },
            openThis: { modelTasksPopupState.isOpen = true }
        )
    }

    /// Coordinates switching between the Context card and the Model Tasks popup: if the other one
    /// is currently open, its exit animation is allowed to fully finish before this one's entrance
    /// animation begins — the same sequential out-then-in feel used for the Insight Tree's docked
    /// cards — rather than cross-fading both at once.
    private func switchPopups(
        otherIsOpen: Bool,
        closeOther: @escaping () -> Void,
        openThis: @escaping () -> Void
    ) {
        guard otherIsOpen else {
            withAnimation(.springStandard) {
                openThis()
            }
            return
        }
        withAnimation(.springQuick) {
            closeOther()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.springStandard) {
                openThis()
            }
        }
    }

    private var contextProgress: CGFloat {
        guard contextWordLimit > 0 else { return 0 }
        return min(max(CGFloat(contextWordCount) / CGFloat(contextWordLimit), 0), 1)
    }

    private func dismissContextPopup() {
        guard contextCard.isOpen else { return }
        withAnimation(.springStandard) {
            contextCard.reset()
        }
    }

    private func canvasActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .id("\(title)-\(canvasActionDrawID)")
                    .sfSymbolDrawOn()
                Text(title)
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

    private var studyToolsButton: some View {
        Button(action: onToggleStudyTools) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                Text("Branch")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(isStudyToolsActive ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.paragraphText.opacity(0.75))
            .animation(.easeInOut(duration: 0.2), value: isStudyToolsActive)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel(isStudyToolsActive ? "Close Branch" : "Branch this Insight")
    }

    private var selectCanvasActionButton: some View {
        Button(action: onSelectCanvasItem) {
            HStack(spacing: 8) {
                selectionCountIcon
                BlurSwapText(selectedCanvasItemCount >= 1 ? "Add concept to selection" : "Select")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(selectedCanvasItemCount >= 1 ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

    private var clearCanvasSelectionButton: some View {
        Button(action: onClearCanvasSelection) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Cancel current selection")
    }

    private var cancelCanvasAskButton: some View {
        Button(action: onCancelCanvasAsk) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Cancel Ask")
    }

    @ViewBuilder
    private var selectionCountIcon: some View {
        if selectedCanvasItemCount > 0 {
            ZStack {
                Circle()
                    .fill(AngroveTheme.Colors.lightGreen)
                Text("\(min(selectedCanvasItemCount, 99))")
                    .font(.custom("Figtree-Bold", size: selectedCanvasItemCount > 9 ? 7 : 8))
                    .foregroundColor(AngroveTheme.Colors.canvasSecondary)
            }
            .frame(width: 14, height: 14)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .id("select-\(canvasActionDrawID)")
                .sfSymbolDrawOn()
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

}

/// Owns its own focus so it can live in the shell's `ModelControlsHost`, away from the dock
/// that publishes it; it takes focus as soon as the expanded search appears.
private struct CanvasSearchTextField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text("Search")
                .foregroundColor(AngroveTheme.Colors.placeholderText)
        )
        .font(.custom("Figtree-SemiBold", size: 14))
        .foregroundColor(AngroveTheme.Colors.paragraphText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($isFocused)
        .accessibilityLabel("Search Insights")
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }
}
