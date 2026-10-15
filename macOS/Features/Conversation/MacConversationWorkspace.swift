import AppKit
import SwiftUI

struct MacInsightPaneLayout: Equatable {
    static let minimumContentWidth: CGFloat = 500
    static let collapseDistance: CGFloat = 84
    var fraction: CGFloat = 0
    var isPinned = false
    private(set) var isSwapped = false
    private(set) var floatingWidth: CGFloat = 500
    private(set) var rememberedFraction: CGFloat? = nil
    private(set) var collapsedDuringDrag = false

    func minimumViewportWidth(in workspaceWidth: CGFloat) -> CGFloat {
        min(Self.minimumContentWidth, max(0, isPinned ? workspaceWidth * 0.8 : workspaceWidth - 48))
    }

    func viewportWidth(in workspaceWidth: CGFloat) -> CGFloat {
        guard fraction > 0, workspaceWidth > 0 else { return 0 }
        if !isPinned { return min(floatingWidth, max(0, workspaceWidth - 48)) }
        return min(max(workspaceWidth * fraction, Self.minimumContentWidth), workspaceWidth * 0.8)
    }
    func mainViewportWidth(in workspaceWidth: CGFloat) -> CGFloat {
        max(0, workspaceWidth - (isPinned ? viewportWidth(in: workspaceWidth) : 0))
    }
    func mainControlsViewportWidth(in workspaceWidth: CGFloat) -> CGFloat {
        if isPinned || fraction == 0 { return mainViewportWidth(in: workspaceWidth) }
        return max(0, workspaceWidth - viewportWidth(in: workspaceWidth) - 48)
    }
    func conversationViewportWidth(in workspaceWidth: CGFloat) -> CGFloat {
        isSwapped ? viewportWidth(in: workspaceWidth) : mainViewportWidth(in: workspaceWidth)
    }
    func treeViewportWidth(in workspaceWidth: CGFloat) -> CGFloat {
        isSwapped ? mainViewportWidth(in: workspaceWidth) : viewportWidth(in: workspaceWidth)
    }
    mutating func applyShortcut(_ action: MacShortcutRequest.Action, workspaceWidth: CGFloat) {
        switch action {
        case .focusQuestion, .toggleContext:
            if isSwapped { open(workspaceWidth: workspaceWidth) }
        case .openTree:
            toggle(workspaceWidth: workspaceWidth)
        case .swapPanes:
            open(workspaceWidth: workspaceWidth)
            swap()
        case .pinPanes:
            open(workspaceWidth: workspaceWidth)
            togglePin(workspaceWidth: workspaceWidth)
        default: break
        }
    }
    mutating func swap() { isSwapped.toggle() }
    func contentWidth(in workspaceWidth: CGFloat) -> CGFloat {
        max(Self.minimumContentWidth, viewportWidth(in: workspaceWidth))
    }
    func expandedContentWidth(in workspaceWidth: CGFloat) -> CGFloat {
        var expanded = self
        expanded.open(workspaceWidth: workspaceWidth)
        return expanded.contentWidth(in: workspaceWidth)
    }
    mutating func drag(from initialWidth: CGFloat, translation: CGFloat, workspaceWidth: CGFloat) {
        guard workspaceWidth > 0 else { return }
        let proposed = initialWidth - translation
        if initialWidth > 0, proposed <= minimumViewportWidth(in: workspaceWidth) - Self.collapseDistance {
            if fraction > 0 {
                if isPinned { fraction = minimumViewportWidth(in: workspaceWidth) / workspaceWidth }
                else { floatingWidth = Self.minimumContentWidth }
                close()
            }
            collapsedDuringDrag = true
            return
        }
        if collapsedDuringDrag {
            open(workspaceWidth: workspaceWidth)
            collapsedDuringDrag = false
        }
        if !isPinned {
            floatingWidth = min(max(proposed, Self.minimumContentWidth), max(Self.minimumContentWidth, workspaceWidth - 48))
            return
        }
        if initialWidth == 0, proposed <= 0 { return }
        fraction = min(max(proposed, Self.minimumContentWidth) / workspaceWidth, 0.8)
    }
    mutating func togglePin(workspaceWidth: CGFloat) {
        if isPinned {
            isPinned = false
        } else {
            let width = viewportWidth(in: workspaceWidth)
            isPinned = true
            fraction = min(max(width / max(workspaceWidth, 1), Self.minimumContentWidth / max(workspaceWidth, 1)), 0.8)
        }
        collapsedDuringDrag = false
    }
    mutating func finishDrag() {
        collapsedDuringDrag = false
    }
    mutating func close() {
        if fraction > 0 { rememberedFraction = fraction }
        fraction = 0
        collapsedDuringDrag = false
    }
    mutating func toggle(workspaceWidth: CGFloat) {
        if fraction > 0 { close() }
        else { open(workspaceWidth: workspaceWidth) }
    }
    mutating func open(workspaceWidth: CGFloat = 1000) {
        guard workspaceWidth > 0 else { return }
        guard fraction == 0 else { return }
        fraction = min(max(Self.minimumContentWidth / workspaceWidth, rememberedFraction ?? 0.5), 0.8)
        collapsedDuringDrag = false
    }
}

struct MacConversationWorkspace: View {
    let showsFixture: Bool
    let conversationID: UUID
    @Binding var question: String
    @Binding var shortcutRequest: MacShortcutRequest?
    let queuePopup: ModelTasksPopupState
    var onActivity: () -> Void = {}
    @State private var focusQuestionRequest = 0
    @State private var contextToggleRequest: UUID?
    var initialQuote: ConceptDefinition? = nil
    var onInitialQuoteHandled: () -> Void = {}
    var onNewConversation: () -> Void = {}
    var onOpenInsights: () -> Void = {}
    @State private var session = MacConversationState()
    @State private var tree = MacTreeControls()
    private let runtime = MacApplicationRuntime.shared
    @State private var pane = MacInsightPaneLayout(fraction: MacDesignPreview.startsScrolled ? 0.5 : 0)
    @State private var dragStartWidth: CGFloat?
    @State private var handleHovered = false
    @State private var secondaryUpdateSignal = 0
    @State private var treeButtonWidth: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsClearConfirmation = false
    @State private var showsRenamePrompt = false
    @State private var renameDraft = ""
    @State private var showsTopicPicker = false
    @State private var workspaceWidth: CGFloat = 1000

    @AppStorage(SettingsStorageKey.conversationBackground) private var conversationBackground: CanvasBackgroundOption = .system

    var body: some View {
        GeometryReader { geometry in
            let isTreeOpen = pane.fraction > 0
            let secondaryWidth = pane.viewportWidth(in: geometry.size.width)
            let conversationWidth = pane.conversationViewportWidth(in: geometry.size.width)
            let treeWidth = pane.treeViewportWidth(in: geometry.size.width)
            let secondaryHeight = max(0, geometry.size.height - (pane.isPinned ? 0 : 48))
            let conversationIsFloating = pane.isSwapped && !pane.isPinned
            let mainControlsWidth = pane.mainControlsViewportWidth(in: geometry.size.width)
            ZStack(alignment: .topTrailing) {
                MacConversationView(showsFixture: showsFixture, session: session, onSend: send, question: $question, focusQuestionRequest: focusQuestionRequest,
                                    onChooseTopic: { showsTopicPicker = true })
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(width: pane.isSwapped ? pane.expandedContentWidth(in: geometry.size.width) : conversationWidth,
                           height: pane.isSwapped ? secondaryHeight : geometry.size.height)
                    .background(CanvasBackground(option: conversationBackground))
                    .canvasAppearance(conversationBackground)
                    .frame(width: conversationWidth,
                           height: pane.isSwapped ? secondaryHeight : geometry.size.height, alignment: .leading)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: conversationIsFloating ? 24 : 0))
                    .contentShape(RoundedRectangle(cornerRadius: conversationIsFloating ? 24 : 0))
                    .opacity(!pane.isSwapped || isTreeOpen ? 1 : 0)
                    .allowsHitTesting(!pane.isSwapped || isTreeOpen)
                    .accessibilityHidden(pane.isSwapped && !isTreeOpen)
                    .padding(conversationIsFloating ? 24 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pane.isSwapped ? .topTrailing : .topLeading)
                    .zIndex(pane.isSwapped ? 2 : 0)

                ZStack(alignment: .topTrailing) {
                    // This surface expands from the capsule when the tree occupies the secondary slot.
                    AngroveTheme.Colors.canvasSecondary
                    AngroveTheme.Colors.canvas.opacity(isTreeOpen || pane.isSwapped ? 1 : 0)
                    MacInsightTreePane(session: session, controls: tree, runtime: runtime,
                                       isVisible: isTreeOpen || pane.isSwapped, onActivity: onActivity)
                        .frame(width: pane.isSwapped ? max(500, treeWidth) : pane.expandedContentWidth(in: geometry.size.width),
                               height: pane.isSwapped ? geometry.size.height : secondaryHeight)
                        .opacity(isTreeOpen || pane.isSwapped ? 1 : 0)
                        .allowsHitTesting(isTreeOpen || pane.isSwapped)
                        .accessibilityHidden(!isTreeOpen && !pane.isSwapped)
                }
                .frame(width: pane.isSwapped || isTreeOpen ? treeWidth : treeButtonWidth,
                       height: pane.isSwapped ? geometry.size.height : (isTreeOpen ? secondaryHeight : 48),
                       alignment: pane.isSwapped ? .topLeading : .topTrailing)
                .clipShape(RoundedRectangle(cornerRadius: pane.isSwapped || (pane.isPinned && isTreeOpen) ? 0 : 24))
                .contentShape(RoundedRectangle(cornerRadius: pane.isSwapped || (pane.isPinned && isTreeOpen) ? 0 : 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(AngroveTheme.Colors.controlBorder, lineWidth: 1)
                        .opacity(!pane.isSwapped && !isTreeOpen ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .padding(pane.isSwapped || (pane.isPinned && isTreeOpen) ? 0 : 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pane.isSwapped ? .topLeading : .topTrailing)
                .zIndex(pane.isSwapped ? 0 : 2)
            }
            .macPageFade()
            .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { treeConfiguration in
                ZStack(alignment: .bottomTrailing) {
                    // These two hosts belong to layout slots, so Swap changes their content in place.
                    MacWorkspaceControlSlot(session: session, tree: tree, runtime: runtime,
                                            isCanvasMode: pane.isSwapped, isVisible: true,
                                            hasQuestion: !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                            treeCard: treeConfiguration?.dockedCard,
                                            onOpenTree: { openTree(workspaceWidth: geometry.size.width) },
                                            onCloseTree: closeTree, onSend: send, onClearDraft: { question = "" },
                                            queuePopup: queuePopup, onActivity: onActivity,
                                            contextToggleRequest: $contextToggleRequest)
                        .frame(width: mainControlsWidth, height: geometry.size.height)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MacWorkspaceControlSlot(session: session, tree: tree, runtime: runtime,
                                            isCanvasMode: !pane.isSwapped, isVisible: isTreeOpen,
                                            hasQuestion: !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                            treeCard: treeConfiguration?.dockedCard,
                                            onOpenTree: { openTree(workspaceWidth: geometry.size.width) },
                                            onCloseTree: closeTree, onSend: send, onClearDraft: { question = "" }, onActivity: onActivity,
                                            contextToggleRequest: $contextToggleRequest)
                        .frame(width: secondaryWidth, height: secondaryHeight)
                        .padding(pane.isPinned ? 0 : 24)
                        .opacity(isTreeOpen ? 1 : 0)
                        .allowsHitTesting(isTreeOpen)
                        .accessibilityHidden(!isTreeOpen)
                }
            }
            // Draw the floating frame above the controls' fade, including its bottom edge.
            .overlay(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(AngroveTheme.Colors.controlBorder, lineWidth: 1)
                    .frame(width: secondaryWidth, height: secondaryHeight)
                    .padding(24)
                    .opacity(isTreeOpen && !pane.isPinned ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .macPageFade()
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 16) {
                    if isTreeOpen {
                        MacTreeHeaderButton(symbol: "arrow.left.arrow.right", label: "Swap") {
                            onActivity()
                            withAnimation(reduceMotion ? nil : .springStandard) { pane.swap() }
                        }
                        .transition(reduceMotion ? .opacity : .blurFade)
                        MacTreeHeaderButton(symbol: pane.isPinned ? "pin.fill" : "pin",
                                            label: pane.isPinned ? "Unpin Insight Tree" : "Pin Insight Tree",
                                            isActive: pane.isPinned) {
                            onActivity()
                            withAnimation(reduceMotion ? nil : .springStandard) {
                                pane.togglePin(workspaceWidth: geometry.size.width)
                            }
                        }
                        .transition(reduceMotion ? .opacity : .blurFade)
                    }
                    MacTreeToggleButton(isOpen: isTreeOpen, isSwapped: pane.isSwapped, updateSignal: secondaryUpdateSignal) {
                        onActivity()
                        if isTreeOpen { closeTree() }
                        else { openTree(workspaceWidth: geometry.size.width) }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { treeButtonWidth = $0 }
                }
                .padding(isTreeOpen ? (pane.isPinned ? 24 : 40) : 24)
                .macPageFade()
            }
            .overlay {
                if isTreeOpen || dragStartWidth != nil {
                    resizeHandle(treeWidth: secondaryWidth, workspaceWidth: geometry.size.width)
                        .position(x: geometry.size.width - secondaryWidth - (pane.isPinned ? 10 : 22),
                                  y: geometry.size.height / 2)
                        .opacity(isTreeOpen ? 1 : 0)
                        .transition(.opacity)
                        .macPageFade()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: LocalInsightTreeSeedStore.didChange)) { notification in
                if !pane.isSwapped, notification.object as? UUID == session.id { secondaryUpdateSignal += 1 }
            }
            .onChange(of: session.concepts) { old, new in
                if !pane.isSwapped, old != new { secondaryUpdateSignal += 1 }
            }
            .onChange(of: session.completedResponseCount) { old, new in
                if pane.isSwapped, new > old { secondaryUpdateSignal += 1 }
            }
            .task {
                session.configure(preview: showsFixture, conversationID: conversationID)
                if let initialQuote {
                    session.attachQuote(initialQuote)
                    onInitialQuoteHandled()
                }
            }
            .onChange(of: session.quoteRequest) { _, _ in
                tree.dismissHoverRequest += 1
                tree.studyExitRequest += 1
                if pane.isSwapped { openTree(workspaceWidth: workspaceWidth) }
                else { closeTree() }
            }
            .sheet(item: Bindable(session).selectedDefinition) { concept in
                InsightLibraryCard(insight: concept, isSaved: session.savedIDs.contains(concept.id),
                    onQuote: { session.attachQuote(concept); session.selectedDefinition = nil },
                    onFork: { session.fork(concept); session.selectedDefinition = nil },
                    onToggleSaved: { session.toggleBookmark(concept) })
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(24)
                    .background(AngroveTheme.Colors.canvas)
            }
            .environment(\.speechSource, SpeechSource(title: session.activeBranch?.topQuestionText ?? "", conversationID: session.id, page: .conversation))
            .onChange(of: session.restoredDraft) { _, draft in
                if let draft, question.isEmpty { question = draft }
                session.restoredDraft = nil
            }
            .onExitCommand { tree.dismissHoverRequest += 1; tree.studyExitRequest += 1 }
            .alert("Angrove", isPresented: Bindable(session).showsError) {
                Button("OK", role: .cancel) {}
            } message: { Text(session.errorMessage ?? "") }
            .confirmationDialog("Clear this conversation?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("Clear Conversation", role: .destructive) { session.clear(runtime: runtime); question = "" }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the current conversation’s messages and cancels its model tasks.") }
            .sheet(isPresented: $showsRenamePrompt) {
                MacRenameConversationSheet(initialTitle: renameDraft) { session.rename(to: $0) }
            }
            .sheet(isPresented: $showsTopicPicker) {
                MacConversationTopicPicker(selectedID: session.studyTopicID) { topicID in
                    session.assignTopic(topicID)
                    showsTopicPicker = false
                }
            }
            .onChange(of: shortcutRequest, initial: true) { _, request in
                guard let request else { return }
                withAnimation(reduceMotion ? nil : .springStandard) {
                    pane.applyShortcut(request.action, workspaceWidth: geometry.size.width)
                }
                if request.action == .focusQuestion { focusQuestionRequest += 1 }
                if request.action == .toggleContext { contextToggleRequest = request.id }
                shortcutRequest = nil
            }
            .coordinateSpace(name: "MacConversationWorkspace")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { workspaceWidth = $0 }
        }
    }
    private func resizeHandle(treeWidth: CGFloat, workspaceWidth: CGFloat) -> some View {
        Capsule()
            .fill(AngroveTheme.Colors.treeConnector)
            .frame(width: 2, height: 149)
            .scaleEffect(handleHovered ? 1.05 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: handleHovered)
            .frame(width: 28, height: 173)
            .contentShape(Rectangle())
            .background(MacResizeCursor())
            .onHover { handleHovered = $0 }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("MacConversationWorkspace"))
                .onChanged { value in
                    if dragStartWidth == nil { dragStartWidth = treeWidth }
                    var next = pane
                    next.drag(from: dragStartWidth ?? treeWidth, translation: value.translation.width,
                              workspaceWidth: workspaceWidth)
                    guard next != pane else { return }
                    let changesVisibility = (pane.fraction > 0) != (next.fraction > 0)
                    withAnimation(changesVisibility && !reduceMotion ? .springStandard : nil) { pane = next }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .springStandard) { pane.finishDrag() }
                    dragStartWidth = nil
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Insight Tree resize handle")
            .accessibilityValue("\(Int(treeWidth)) points")
            .accessibilityAdjustableAction { direction in
                let inwardDistance = treeWidth <= pane.minimumViewportWidth(in: workspaceWidth) + 0.5
                    ? MacInsightPaneLayout.collapseDistance : 50
                withAnimation(reduceMotion ? nil : .springStandard) {
                    pane.drag(from: treeWidth, translation: direction == .increment ? -50 : inwardDistance,
                              workspaceWidth: workspaceWidth)
                    pane.finishDrag()
                }
            }
    }
    private func send() {
        onActivity()
        let invocation = SlashCommand.invocation(for: question)
        if case .define(nil) = invocation { return }
        if let command = invocation, !command.producesResponse {
            question = ""
            switch command {
            case .define: break // Definition requests use the normal persisted response path.
            case .clear: showsClearConfirmation = true
            case .compact:
                guard runtime.modelIsAvailable, session.canCompactContext else {
                    session.report("There is no completed context available to compact right now.")
                    return
                }
                Task { if !(await session.compact(runtime: runtime)) { session.report("The conversation could not be compacted.") } }
            case .rename(let title):
                if let title { session.rename(to: title) }
                else { renameDraft = session.title; showsRenamePrompt = true }
            case .newConversation: onNewConversation()
            case .tree: openTree(workspaceWidth: workspaceWidth)
            case .topic: showsTopicPicker = true
            case .insights: onOpenInsights()
            }
            return
        }
        guard question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "/define" else { return }
        if session.send(question, runtime: runtime) { question = "" }
    }
    private func openTree(workspaceWidth: CGFloat) {
        withAnimation(reduceMotion ? nil : .springStandard) { pane.open(workspaceWidth: workspaceWidth) }
    }
    private func closeTree() {
        withAnimation(reduceMotion ? nil : .springStandard) { pane.close() }
    }
}

private struct MacResizeCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {}
    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }
}
