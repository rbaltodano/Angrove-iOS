import SwiftUI

/// One placed piece of Worktree text. Plain text until a quoted question is committed, then a
/// bordered, resizable card that holds the conversation. The drag grip sits just before the
/// text, invisible until the text is hovered or being edited.
struct WorktreeItemView: View, Equatable {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let scale: CGFloat
    let runtime: MacApplicationRuntime
    /// Where the pointer is on the canvas; a note's box fades in near it.
    var pointer: WorktreeCanvasPointer? = nil
    @Environment(\.worktreeCapturesSnapshot) private var capturesSnapshot
    @State private var isHovered = false
    @State private var isGripHovered = false
    @State private var dragStart: CGPoint?
    /// Lags `item.isQuestion` by one update so the card first mounts in the text's chrome,
    /// then animates its border and padding open.
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cardPadding: CGFloat = 28
    /// Plain text already carries the card's chrome, borderless and tight, so asking only animates it open.
    static let textPadding: CGFloat = 8
    static let cardWidth: CGFloat = 400
    static let cardMaxHeight: CGFloat = 420
    private var gripSize: CGSize {
        CGSize(width: WorktreeBoxGrip.glyphSize.width / scale, height: WorktreeBoxGrip.glyphSize.height / scale)
    }
    private static let gripSpacing: CGFloat = 8

    /// Only the inputs: board state the view reads is tracked by observation.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.item == rhs.item && lhs.scale == rhs.scale && lhs.board === rhs.board && lhs.pointer === rhs.pointer }
    }

    private var isEditing: Bool { board.editingID == item.id }
    private var padding: CGFloat { isOpen ? Self.cardPadding : Self.textPadding }
    private var isOverTrash: Bool { board.trashTargetID == item.id }
    private var isOverSidebar: Bool { board.sidebarDrag?.id == item.id }
    /// A question opens into a card once any sidebar-chip arrival has finished.
    private var opensAsCard: Bool { item.isQuestion && item.arrivalTitle == nil }
    private var isSelectable: Bool { item.isQuestion || item.isInsight || item.isHeading || item.image != nil }
    /// A plain note: it gets a resizable text box, as a Figma text layer does.
    private var isNote: Bool {
        !item.isQuestion && !item.isInsight && !item.isHeading && item.image == nil && !item.isSummarizing
            && !item.isHelp && item.arrivalTitle == nil && item.definitionFailureTerm == nil
    }
    private var isActive: Bool { board.selection.contains(item.id) }
    private static let labelFont = NSFont(name: "LibreBaskerville-Regular", size: 28) ?? .systemFont(ofSize: 28)
    private static let labelDisplayFont = Font.custom("LibreBaskerville-Regular", fixedSize: 28)
    static let headingFont = NSFont(name: "LibreBaskerville-Regular", size: 40) ?? .systemFont(ofSize: 40)
    static let headingLineHeight: CGFloat = 80
    static let headingTracking: CGFloat = 0.5
    /// The first line's height, for centring the grip on it.
    private var firstLineHeight: CGFloat { item.isHeading ? Self.headingLineHeight : WorktreeTextEditor.lineHeight }

    var body: some View {
        content
            .padding(padding)
            .background {
                // A dropped conversation morphs from the sidebar chip's fill and corners.
                if item.isQuestion && (isOpen || item.isDropped) {
                    RoundedRectangle(cornerRadius: isOpen ? 28 : 12, style: .continuous)
                        .fill(isOpen ? AngroveTheme.Colors.canvas : AngroveTheme.Colors.systemSelection)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke((isActive ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.popupBorder)
                        .opacity(isOpen ? 1 : 0), lineWidth: 1 / scale)
                    .allowsHitTesting(false)
            }
            // The top edge moves the item, like the grip.
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: padding)
                    .contentShape(Rectangle())
                    .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
                    .gesture(moveGesture)
            }
            .overlay { if item.isQuestion { WorktreeResizeEdges(board: board, item: item, scale: scale) } }
            .overlay {
                if let pointer, isNote || (item.isHeading && !item.isSummarizing) {
                    WorktreeTextBox(board: board, item: item, zoom: scale, pointer: pointer, move: boxMove,
                                    minimumHeight: item.isHeading ? Self.headingLineHeight : WorktreeTextEditor.lineHeight)
                }
            }
            .overlay {
                if (isNote || item.isHeading) && isActive {
                    Rectangle()
                        .strokeBorder(AngroveTheme.Colors.lightGreen, lineWidth: 1 / scale)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) { grip }
            .overlay(alignment: .topLeading) { label }
            .onHover { hovering in
                isHovered = hovering
                // Hovering is enough to aim a command at an item.
                board.setHovered(item.id, hovering)
            }
            .onChange(of: pointer?.nearIDs.contains(item.id)) { _, nearby in
                if nearby == false { isHovered = false; isGripHovered = false }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if size.width > 0, size.height > 0, board.itemSizes[item.id] != size { board.itemSizes[item.id] = size }
            }
            // The card grows outward so its first line stays where it was typed.
            .offset(x: -padding, y: -padding)
            // Selection is outlined without changing the item's size.
            // Plain text keeps its clicks for editing.
            // ⇧- or ⌘-click adds to the selection.
            .simultaneousGesture(TapGesture().onEnded {
                if !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty { board.toggleSelection(item.id) }
                else { board.select(item.id) }
            }, including: isSelectable ? .all : .none)
            .opacity(isOverTrash ? 0.5 : isOverSidebar ? 0 : 1)
            .scaleEffect(isOverTrash ? 0.96 : isOverSidebar ? 0.6 : 1)
            .animation(.springQuick, value: isOverSidebar)
            .animation(.springQuick, value: isOverTrash)
            .onChange(of: opensAsCard, initial: true) { _, opens in
                guard opens != isOpen else { return }
                guard opens else { isOpen = false; return }
                Task { @MainActor in
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard) { isOpen = true }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if item.isInsight {
            WorktreeInsightContent(board: board, item: item)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AngroveTheme.Colors.lightGreen.opacity(isActive ? 1 : 0), lineWidth: 1 / scale)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged(moveChanged)
                    .onEnded { _ in moveEnded() })
        } else if item.isSummarizing {
            Text(item.isHeading ? "Heading…" : "Summarizing…")
                .font(BrandTypography.font("Figtree-Regular", size: 14))
                .frame(height: WorktreeTextEditor.lineHeight)
                .modifier(WorktreeWorkStyle(work: item.outputWork))
                .transition(.blurFade)
        } else if item.revealsSummary && !isEditing {
            WorktreeSummaryReveal(text: item.text, width: item.size?.width, minimumHeight: item.size?.height, onComplete: {
                board.update(item.id) { $0.revealsSummary = false }
            }, onEdit: {
                board.update(item.id) { $0.revealsSummary = false }
                board.editingID = item.id
            })
            .transition(.blurFade)
        } else if let title = item.arrivalTitle {
            // The chip's text inside the item's own (chip-coloured) background.
            Text(title)
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .transition(.blurFade)
        } else if item.isQuestion {
            if let session = item.session {
                WorktreeConversationSurface(card: WorktreeQuestionCard(board: board, item: item, session: session, runtime: runtime, isOpen: isOpen))
                    .equatable()
                    .transition(.blurFade)
            }
        } else if let image = item.image {
            WorktreeImage(board: board, item: item, file: image, zoom: scale, pointer: pointer, move: boxMove)
        } else if item.isHelp {
            WorktreeHelpCard()
                .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .blurFade))
        } else if item.isHeading && !isEditing {
            // Shown word by word, as page titles arrive. A click selects it; a double-click edits.
            WorktreeRevealedText(text: item.text, font: MacPageHeading.pageFont, color: AngroveTheme.Colors.headingText,
                                 naturalFont: Self.headingFont, lineHeight: Self.headingLineHeight,
                                 tracking: Self.headingTracking, editsOnDoubleClick: true, width: item.size?.width) {
                // Editing keeps the selection, so the heading's size doesn't change under the cursor.
                board.editingID = item.id
            }
            .frame(minHeight: item.size?.height, alignment: .topLeading)
            .transition(.blurFade)
        } else if item.isHeading {
            WorktreeTextEditor(text: board.binding(item.id, \.text), isEditing: isEditing,
                fillsWidth: item.size != nil, maxWidth: item.size?.width ?? 720, color: AngroveTheme.Colors.headingText,
                textFont: Self.headingFont, textLineHeight: Self.headingLineHeight, textTracking: Self.headingTracking,
                onBeginEditing: { board.editingID = item.id },
                onEndEditing: { if board.editingID == item.id { board.endEditing() } },
                onCommit: { board.endEditing() },
                onEscape: { board.endEditing() })
                .frame(width: item.size?.width, alignment: .topLeading)
                .frame(minHeight: item.size?.height, alignment: .topLeading)
        } else {
            // A resized note wraps at its box's width and is at least its box's height.
            WorktreeTextEditor(text: board.binding(item.id, \.text), isEditing: isEditing,
                fillsWidth: item.size != nil, maxWidth: item.size?.width ?? 480,
                color: AngroveTheme.Colors.paragraphText,
                highlightsCommands: true,
                onBeginEditing: { board.editingID = item.id },
                onEndEditing: { if board.editingID == item.id { board.endEditing() } },
                onCommit: { board.commit(item.id, runtime: runtime) },
                onEscape: { board.endEditing() })
                .frame(width: item.size?.width, alignment: .topLeading)
                .frame(minHeight: item.size?.height, alignment: .topLeading)
                .transition(.blurFade)
                // A lone quotation mark left untouched fades away.
                .task(id: item.text) {
                    guard ["\"", "\u{201C}"].contains(item.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) { board.delete(item.id) }
                }
        }
    }

    /// Baskerville 28 above the item, editable in place; "Labeling..." shimmers in its place while
    /// the model works.
    private var label: some View {
        ZStack(alignment: .bottomLeading) {
            if let work = item.labelWork {
                Text("Labeling...")
                    .font(Self.labelDisplayFont)
                    .modifier(WorktreeWorkStyle(work: work))
                    .transition(.blurFade)
            } else if let label = item.label, board.editingID != item.labelID {
                // A true 28pt, matching the editor (the brand helper caps Mac sizes at 24).
                WorktreeRevealedText(text: label, font: Self.labelDisplayFont,
                                     color: AngroveTheme.Colors.headingText,
                                     naturalFont: Self.labelFont, lineHeight: 42) {
                    board.editingID = item.labelID
                }
                .transition(.blurFade)
            } else if item.label != nil {
                WorktreeTextEditor(text: board.binding(item.id, \.labelText), isEditing: board.editingID == item.labelID,
                    submitsOnReturn: true, maxWidth: 640, color: AngroveTheme.Colors.headingText,
                    textFont: Self.labelFont, textLineHeight: 42,
                    onBeginEditing: { board.editingID = item.labelID },
                    onEndEditing: { if board.editingID == item.labelID { board.finishLabelEditing(item.id) } },
                    onCommit: { board.finishLabelEditing(item.id) },
                    onEscape: { board.finishLabelEditing(item.id) })
                    .fixedSize()
                    .transition(.blurFade)
            }
        }
        .alignmentGuide(.top) { $0[.bottom] + 8 }
    }

    private var pointerIsNearGrip: Bool {
        guard let pointer else { return true }
        let x = item.isHeading ? -(gripSize.width + 8 / scale) : (isOpen ? 0 : padding) - gripSize.width - Self.gripSpacing
        let y = item.isHeading ? 0 : padding + (firstLineHeight - gripSize.height) / 2
        return pointer.isNearControl(CGPoint(x: x + gripSize.width / 2, y: y + gripSize.height / 2),
            for: item.id, board: board, zoom: scale)
    }

    private var grip: some View {
        Image("WorktreeGrip")
            .renderingMode(.template)
            .resizable()
            .frame(width: gripSize.width, height: gripSize.height)
            // Brighter move grips remain distinct from the quieter resize outlines.
            .foregroundStyle(AngroveTheme.Colors.lightGreen.opacity(0.75))
            .padding(6)
            .contentShape(Rectangle())
            .opacity((isEditing || isHovered || isGripHovered || dragStart != nil) && pointerIsNearGrip ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovered || isGripHovered || isEditing)
            .onHover { isGripHovered = $0 }
            .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
            .gesture(moveGesture)
            // Just before the text itself; a card's grip sits just outside its border.
            .offset(x: item.isHeading ? -(gripSize.width + 8 / scale + 6)
                        : (isOpen ? 0 : padding) - (gripSize.width + Self.gripSpacing + 6),
                    y: item.isHeading ? -6 : padding + (firstLineHeight - gripSize.height) / 2 - 6)
            .accessibilityLabel("Move")
            .opacity(capturesSnapshot ? 0 : 1)
    }

    private var moveGesture: some Gesture {
        // Global space so the pointer can be compared with the Trash control's frame.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged(moveChanged)
            .onEnded { _ in moveEnded() }
    }

    /// Moving from a box's grip or top edge, as from the item's own grip.
    private var boxMove: WorktreeBoxMove { WorktreeBoxMove(changed: moveChanged, ended: moveEnded) }

    private func moveChanged(_ value: DragGesture.Value) {
        if dragStart == nil { board.beginHistoryAction() }
        let start = dragStart ?? item.origin
        dragStart = start
        // 8pt snapping and 84pt guide overhang, in screen points.
        board.move(item.id, to: CGPoint(x: start.x + value.translation.width / scale,
                                        y: start.y + value.translation.height / scale),
                   threshold: 8 / scale, overhang: 84 / scale)
        WorktreeItemMove.updateDestination(board: board, id: item.id, location: value.location)
    }

    private func moveEnded() {
        defer { board.endHistoryAction() }
        let start = dragStart
        dragStart = nil
        WorktreeItemMove.end(board: board, id: item.id, start: start, runtime: runtime)
    }
}

/// The conversation inside a question card, drawn with the conversation page's own response
/// card (thinking, reveal, Insights). Each question and its answer form one section whose question
/// sticks to the top until the next section pushes it away.
struct WorktreeQuestionCard: View, Equatable {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let session: MacConversationState
    let runtime: MacApplicationRuntime
    /// Before the card opens, the first question sits where it was typed, then glides right.
    let isOpen: Bool
    @State private var contentHeight: CGFloat = WorktreeTextEditor.lineHeight
    /// Read only by the pinned questions, so scrolling never rebuilds the response cards.
    @State private var fade = WorktreeScrollFade()
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var canLoadEarlier = false
    @Environment(\.modelCompletionNotifications) private var completionNotifications
    @Environment(\.worktreeConversationScrollActivity) private var scrollActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAskedHere = false
    @State private var isLoadingEarlier = false
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var responseSize: ConversationFontSizeOption = .small

    /// The fade beneath the pinned question reaches full strength over this much scrolling.
    static let fadeHeight: CGFloat = 40
    /// The window's padding: answers scroll on through it to the window's bottom edge.
    private var edge: CGFloat { isOpen ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding }

    private var width: CGFloat {
        (item.size?.width ?? WorktreeItemView.cardWidth) - WorktreeItemView.cardPadding * 2
    }
    private var height: CGFloat {
        if let size = item.size { return size.height - WorktreeItemView.cardPadding * 2 }
        return min(contentHeight, WorktreeItemView.cardMaxHeight - WorktreeItemView.cardPadding * 2)
    }

    // Camera scale belongs to the outer chrome. Moving, labeling, hovering, or zooming a
    // window must not rebuild its transcript, response markup, and native composer. Session
    // properties read in body remain independently observed, including live model output.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.board === rhs.board && lhs.session === rhs.session && lhs.runtime === rhs.runtime
                && lhs.isOpen == rhs.isOpen && lhs.item.id == rhs.item.id
                && lhs.item.followUpID == rhs.item.followUpID && lhs.item.followUp == rhs.item.followUp
                && lhs.item.size == rhs.item.size && lhs.item.visibleTurnLimit == rhs.item.visibleTurnLimit
        }
    }

    /// Transcript blocks paired as (question index, answer index).
    private static func pairedTurns(in blocks: [ChatBlock]) -> [(question: Int, answer: Int?)] {
        blocks.indices.compactMap { index in
            guard case .user = blocks[index] else { return nil }
            return (index, blocks.indices.contains(index + 1) ? index + 1 : nil)
        }
    }

    private var allTurns: [(question: Int, answer: Int?)] {
        Self.pairedTurns(in: session.transcript)
    }

    /// A dropped conversation shows its latest turns; scrolling to the top loads five more.
    private var turns: ArraySlice<(question: Int, answer: Int?)> {
        let all = allTurns
        guard let limit = item.visibleTurnLimit else { return all[...] }
        return all.suffix(limit)
    }

    var body: some View {
        let blocks = session.transcript
        // Build the transcript and turn list once per update, even with many saved turns.
        let allTurns = Self.pairedTurns(in: blocks)
        let turns = item.visibleTurnLimit.map { allTurns.suffix($0) } ?? allTurns[...]
        let hasEarlierTurns = turns.count < allTurns.count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                if hasEarlierTurns {
                    LeafLoadingAnimation(size: 28)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .onAppear(perform: loadEarlierTurns)
                        .accessibilityLabel("Loading earlier questions")
                }
                ForEach(turns, id: \.question) { turn in
                    Section {
                        if let answer = turn.answer, case .text(let text) = blocks[answer] {
                            response(text, index: answer)
                        }
                    } header: {
                        if case .user(let question, _, _) = blocks[turn.question] {
                            WorktreePinnedQuestion(text: question, isPlaced: isOpen || turn.question > 0,
                                                   maxWidth: questionMaxWidth, fade: fade)
                                .id(turn.question)
                        }
                    }
                }
                // The conversation page's own composer: quoted, hugging the text up to its width.
                QuotedQuestionContainer(isEmpty: followUpText.wrappedValue.isEmpty,
                    lineHeight: MacConversationStyle.questionLineHeight,
                    fontName: MacConversationStyle.questionFontName,
                    maximumWidth: questionMaxWidth,
                    onTapToFocus: { board.editingID = item.followUpID; board.select(item.id) }) {
                    MacCommandEditor(text: followUpText,
                        isFocused: Binding(get: { board.editingID == item.followUpID }, set: { focused in
                            if focused { board.editingID = item.followUpID; board.select(item.id) }
                            else if board.editingID == item.followUpID { board.editingID = nil }
                        }),
                        reduceMotion: reduceMotion,
                        onSubmit: { board.askFollowUp(in: item.id, runtime: runtime) },
                        onEscape: { board.editingID = nil },
                        recognizesCommand: { WorktreeCommandParser.commandRanges(in: $0).first?.location == 0 })
                        .frame(width: min(MacConversationStyle.questionContentWidth(followUpText.wrappedValue, minimum: "Ask a question..."),
                                          questionMaxWidth - 36))
                        .accessibilityLabel("Ask a question")
                }
                    .opacity(session.isComposerReady ? 1 : 0)
                    .allowsHitTesting(session.isComposerReady)
                    .animation(ResponseRevealTiming.finishingAnimation, value: session.isComposerReady)
                // Room below a follow-up asked here so its question can scroll to the very top.
                if hasAskedHere {
                    Color.clear.frame(height: max(0, height - WorktreeTextEditor.lineHeight - 32))
                }
            }
        }
        .onScrollPhaseChange { _, _ in scrollActivity?.onScroll?() }
        .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { old, new in
            if old != new { scrollActivity?.onScroll?() }
        }
        .scrollPosition($position)
        // Dropped conversations open at their latest answer.
        .defaultScrollAnchor(item.visibleTurnLimit == nil ? .top : .bottom)
        .task {
            // The loader is only live once the window has settled at the bottom.
            try? await Task.sleep(for: .milliseconds(600))
            canLoadEarlier = true
        }
        // A finished answer pulses the dot grid once.
        .onChange(of: session.completedResponseCount) { _, _ in board.pulse(item.id) }
        // A new question (not earlier turns loading) scrolls to the top of the window.
        .onChange(of: allTurns.count) { old, new in
            guard new > old, new > 1, let latest = allTurns.last?.question else { return }
            hasAskedHere = true
            Task { @MainActor in
                withAnimation(.springStandard) { position.scrollTo(id: latest, anchor: .top) }
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, value in
            contentHeight = value
        }
        // Quantised and clamped, so the action stops firing once the fade is full.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let progress = (geometry.contentOffset.y + geometry.contentInsets.top) / Self.fadeHeight
            return (min(1, max(0, progress)) * 20).rounded() / 20
        } action: { _, value in
            fade.progress = value
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let below = geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.contentOffset.y - geometry.containerSize.height
            return (min(1, max(0, below / Self.fadeHeight)) * 20).rounded() / 20
        } action: { _, value in
            fade.bottom = value
        }
        // The scroll area runs through the bottom padding to the window's edge, where a fade
        // begins, so answers soften away rather than being cut off.
        .contentMargins(.bottom, edge, for: .scrollContent)
        .frame(width: width, height: height + edge)
        .overlay(alignment: .bottom) { WorktreeBottomFade(fade: fade, height: edge + Self.fadeHeight) }
        .padding(.bottom, -edge)
        .animation(.springStandard, value: height)
        .environment(\.speechSource, SpeechSource(title: session.activeBranch?.topQuestionText ?? "", conversationID: session.id, page: .conversation))
    }

    private func requestDefinition(_ term: String, source: String) {
        session.define(term, source: source, runtime: runtime) { concept in
            guard let completionNotifications else { return }
            board.postDefinition(concept, from: session, to: completionNotifications)
        }
    }

    /// The conversation page's question width, within this window.
    private var questionMaxWidth: CGFloat { min(width, MacConversationStyle.questionMaxWidth) }

    /// Adds five earlier turns, keeping the first turn that was on screen where it was.
    private func loadEarlierTurns() {
        guard canLoadEarlier, !isLoadingEarlier, let anchor = turns.first?.question else { return }
        isLoadingEarlier = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            board.update(item.id) { $0.visibleTurnLimit = ($0.visibleTurnLimit ?? 0) + 5 }
            position.scrollTo(id: anchor, anchor: .top)
            isLoadingEarlier = false
        }
    }

    /// A "/" typed first in the follow-up opens the command field outside the window instead.
    private var followUpText: Binding<String> {
        // Read the narrow item input. Reading board.items through a binding here wakes every
        // retained transcript whenever any item's origin changes, even offscreen cached cards.
        return Binding(get: { item.followUp }, set: { value in
            if item.followUp.isEmpty, value == "/" {
                board.select(item.id)
                _ = board.openCommand()
            } else {
                board.update(item.id) { $0.followUp = value }
            }
        })
    }

    /// Mirrors `MacConversationView`'s response card.
    @ViewBuilder private func response(_ text: String, index: Int) -> some View {
        if text == questionCanceledResponseText {
            Text(text).font(AngroveTheme.Typography.body).foregroundStyle(AngroveTheme.Colors.placeholderText)
        } else {
            let run = session.responseRun(transcriptIndex: index)
            let presentation = MacConversationResponsePresentation(text: text, isPending: session.isPending(transcriptIndex: index))
            ModelResponseCard(title: "", fullText: presentation.visibleText, shouldAnimateOnAppear: session.shouldRevealResponse(transcriptIndex: index),
                showsThinkingIntro: session.isPending(transcriptIndex: index) || session.presentation(transcriptIndex: index)?.showsThinking == true,
                isAwaitingResponse: presentation.isAwaitingResponse, isReceivingStream: presentation.isWriting,
                isQueuedForModel: session.isQueued(transcriptIndex: index),
                usesIncrementalStream: false,
                thinkingSummary: session.summary(transcriptIndex: index),
                liveThought: session.liveThought(transcriptIndex: index),
                thinkingDurationSeconds: session.thinkingDuration(transcriptIndex: index),
                groundingSources: session.sources(transcriptIndex: index),
                evidenceBasis: session.presentation(transcriptIndex: index)?.evidenceBasis,
                responseFont: responseFont,
                conversationFontSize: responseSize,
                savedInsightIDs: session.savedIDs,
                onRegenerate: { session.regenerate(transcriptIndex: index, runtime: runtime) },
                onInsightTap: { requestDefinition($0, source: $1) },
                onInlineInsightQuote: session.attachQuote,
                onInlineInsightFork: session.fork,
                onInlineInsightToggleSaved: session.toggleBookmark,
                onBodyRevealComplete: { if let run { session.finishResponseBodyReveal(run: run) } },
                onFinish: { if let run { session.finishResponseReveal(run: run) } })
                .environment(\.responseFeedbackReport,
                    session.feedbackReport(transcriptIndex: index).map { report in { report } })
                .id(run)
                .environment(\.defineResponseWord, { request in
                    if let term = DefinedTermMarkup.term(in: request.token) { requestDefinition(term, source: text) }
                })
        }
    }
}

@MainActor @Observable private final class WorktreeScrollFade {
    var progress: CGFloat = 0
    /// How much answer lies below the window, as fade strength.
    var bottom: CGFloat = 0
}

/// Canvas colour at the window's very bottom, clearing upward; gone once scrolled to the end.
private struct WorktreeBottomFade: View {
    let fade: WorktreeScrollFade
    let height: CGFloat

    var body: some View {
        LinearGradient(colors: [AngroveTheme.Colors.canvas.opacity(0), AngroveTheme.Colors.canvas],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .opacity(fade.bottom)
            .allowsHitTesting(false)
    }
}

/// A section's question: sticky at the top of its card. Only while pinned does it cast the fade
/// that softens the answer scrolling beneath it.
private struct WorktreePinnedQuestion: View {
    let text: String
    let isPlaced: Bool
    let maxWidth: CGFloat
    let fade: WorktreeScrollFade
    @State private var isPinned = false

    var body: some View {
        // The conversation thread's submitted question: quoted, hugging its text.
        QuotedQuestionContainer(isEmpty: false,
            lineHeight: MacConversationStyle.questionLineHeight,
            fontName: MacConversationStyle.questionFontName,
            maximumWidth: maxWidth,
            alignment: isPlaced ? .trailing : .leading) {
            MacLineText(text: text, serif: MacConversationStyle.usesSerifQuestions, lineHeight: MacConversationStyle.questionLineHeight)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .frame(maxWidth: min(MacConversationStyle.questionContentWidth(text), maxWidth - 36), alignment: .leading)
                .textSelection(.enabled)
        }
            .padding(.vertical, 5)
            // Reaches above the question so nothing scrolling under it shows in the gap to the
            // window's top edge; the scroll view clips the overhang.
            .background { AngroveTheme.Colors.canvas.padding(.top, -60) }
            .background(alignment: .bottom) {
                LinearGradient(colors: [AngroveTheme.Colors.canvas, AngroveTheme.Colors.canvas.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: WorktreeQuestionCard.fadeHeight)
                    .offset(y: WorktreeQuestionCard.fadeHeight)
                    .opacity(isPinned ? fade.progress : 0)
                    .allowsHitTesting(false)
            }
            .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY < 0.5 } action: { isPinned = $0 }
    }
}

/// Browser-window resizing: sides and bottom resize one way, bottom corners both.
private struct WorktreeResizeEdges: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let scale: CGFloat
    @State private var start: (origin: CGPoint, size: CGSize)?

    private static let edge: CGFloat = 8
    private static let corner: CGFloat = 16
    private static let minimum = CGSize(width: 240, height: 140)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                handle(.leading, width: Self.edge, height: size.height - Self.corner, current: size)
                    .offset(x: -Self.edge / 2, y: 0)
                handle(.trailing, width: Self.edge, height: size.height - Self.corner, current: size)
                    .offset(x: size.width - Self.edge / 2, y: 0)
                handle(.bottom, width: size.width - Self.corner * 2, height: Self.edge, current: size)
                    .offset(x: Self.corner, y: size.height - Self.edge / 2)
                handle(.bottomLeading, width: Self.corner, height: Self.corner, current: size)
                    .offset(x: -Self.edge / 2, y: size.height - Self.corner + Self.edge / 2)
                handle(.bottomTrailing, width: Self.corner, height: Self.corner, current: size)
                    .offset(x: size.width - Self.corner + Self.edge / 2, y: size.height - Self.corner + Self.edge / 2)
            }
        }
    }

    private func handle(_ position: FrameResizePosition, width: CGFloat, height: CGFloat, current: CGSize) -> some View {
        Color.clear
            .frame(width: max(width, 0), height: max(height, 0))
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: position))
            .gesture(resize(position, current: current))
    }

    private func resize(_ position: FrameResizePosition, current currentSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(MacWorktreeView.canvasSpace))
            .onChanged { value in
                if start == nil { board.beginHistoryAction() }
                let begin = start ?? (item.origin, item.size ?? currentSize)
                start = begin
                let dx = value.translation.width / scale, dy = value.translation.height / scale
                var size = begin.size, origin = begin.origin
                if [.trailing, .bottomTrailing].contains(position) { size.width = max(Self.minimum.width, begin.size.width + dx) }
                if [.leading, .bottomLeading].contains(position) {
                    size.width = max(Self.minimum.width, begin.size.width - dx)
                    origin.x = begin.origin.x + (begin.size.width - size.width)
                }
                if [.bottom, .bottomLeading, .bottomTrailing].contains(position) {
                    size.height = max(Self.minimum.height, begin.size.height + dy)
                }
                board.update(item.id) { $0.size = size; $0.origin = origin }
            }
            .onEnded { _ in start = nil; board.endHistoryAction() }
    }

}

/// An Insight card made by `/define`. While the model works it still reads as the typed command,
/// shimmering; the definition then grows out of it as the card.
private struct WorktreeInsightContent: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let term = item.definitionFailureTerm {
                WorktreeDefinitionFailure(term: term) { board.dismissDefinitionFailure(item.id) }
                    .transition(.blurFade)
            } else if let insight = item.insight {
                InsightLibraryCard(insight: insight, isSaved: board.savedInsightIDs.contains(insight.id),
                    shadowOpacity: 0,
                    onQuote: {
                        guard let session = item.sourceID.flatMap({ id in board.items.first { $0.id == id } })?.session else { return }
                        session.attachQuote(insight)
                    },
                    onFork: {},
                    onToggleSaved: { board.toggleSaved(insight) })
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .blurFade))
            } else if item.definingTerm != nil {
                Text("Defining...")
                    .font(BrandTypography.font("Figtree-Regular", size: 14))
                    .frame(height: WorktreeTextEditor.lineHeight)
                    .modifier(WorktreeWorkStyle(work: item.outputWork))
                    .transition(.blurFade)
            }
        }
    }
}

/// The command field typed after "/": beside the selection, or free on the canvas.
struct WorktreeCommandField: View {
    let board: WorktreeBoard
    let runtime: MacApplicationRuntime

    var body: some View {
        // Invalid commands and their strike-through use the shared error color.
        WorktreeTextEditor(text: Bindable(board).commandText, isEditing: board.editingID == board.commandFieldID,
            submitsOnReturn: true, maxWidth: 320,
            color: board.isCommandStruck ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.headingText,
            highlightsCommands: !board.isCommandStruck,
            onBeginEditing: { board.editingID = board.commandFieldID },
            onEndEditing: { if board.editingID == board.commandFieldID, !board.isCommandStruck { board.closeCommand() } },
            onCommit: { board.submitCommand(runtime: runtime) },
            onEscape: { board.closeCommand() })
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { board.commandFieldSize = $0 }
            // A lone "/" left untouched fades away.
            .task(id: board.commandText) {
                guard board.commandText == "/" else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, board.commandText == "/", !board.isCommandStruck else { return }
                board.closeCommand()
            }
            // `/define` with nothing to define: the Insight underline, drawn through the middle.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AngroveTheme.Colors.accentRed)
                    .frame(height: 1)
                    .scaleEffect(x: board.isCommandStruck ? 1 : 0, y: 1, anchor: .leading)
                    .allowsHitTesting(false)
            }
    }
}

/// Text standing in for model work, styled as a conversation's: it breathes while queued behind
/// other work and takes the "Thinking..." shimmer once the model starts on it.
struct WorktreeWorkStyle: ViewModifier {
    let work: WorktreeWork?

    func body(content: Content) -> some View {
        content
            .modifier(ThinkingShimmer(isActive: work == .running, color: AngroveTheme.Colors.primaryReadable))
            // Outside the shimmer, so the shimmer's gradient wins while it runs.
            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            .modifier(QueuedWorkBreatheModifier(isQueued: work == .queued))
    }
}

/// The Insight card's drop shadow, given to every selected item and hidden otherwise.
struct WorktreeSelectionShadow: ViewModifier {
    static let opacity = 0.15
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.shadow(color: AngroveTheme.Colors.dropShadow.opacity(isSelected ? Self.opacity : 0), radius: 24, x: 0, y: 16)
    }
}

/// Finished heading or label text, revealed one word at a time like a page title on arrival.
/// A new text reveals again; clicking it starts editing.
struct WorktreeRevealedText: View {
    let text: String
    let font: Font
    let color: Color
    /// The font's AppKit twin and the line height to space its lines to.
    let naturalFont: NSFont
    let lineHeight: CGFloat
    var tracking: CGFloat = 0
    var editsOnDoubleClick = false
    /// A resized heading wraps at its box's width.
    var width: CGFloat? = nil
    let onEdit: () -> Void

    var body: some View {
        SettingsAnimatedHeading(title: text, font: font, color: color, revealsOnAppear: true)
            .id(text)
            .font(font)
            .tracking(tracking)
            .lineSpacing(max(0, lineHeight - ceil(naturalFont.ascender - naturalFont.descender + naturalFont.leading)))
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: width == nil, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture(count: editsOnDoubleClick ? 2 : 1, perform: onEdit)
            .pointerStyle(editsOnDoubleClick ? nil : .horizontalText)
    }
}

/// A command list card from the retired `/help`, kept so Worktrees that have one still show it.
private struct WorktreeHelpCard: View {
    @State private var expanded: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(WorktreeCommandGuide.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(AngroveTheme.Colors.hairline) }
                row(entry)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(width: 500, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1))
    }

    private func row(_ entry: WorktreeCommandGuide.Entry) -> some View {
        let isOpen = expanded == entry.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard) {
                    expanded = isOpen ? nil : entry.id
                }
            } label: {
                HStack {
                    Text(verbatim: entry.name)
                        .font(BrandTypography.font("Figtree-Bold", size: 14))
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))

            if isOpen {
                Text(entry.explanation)
                    .font(BrandTypography.font("Figtree-Regular", size: 14))
                    .lineSpacing(WorktreeTextEditor.lineHeight - 17)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .transition(.blurFade)
            }
        }
    }
}

/// A picture fits within 1000 × 1000 canvas points, keeping its proportions.
private struct WorktreeImage: View {
    let board: WorktreeBoard
    let item: WorktreeBoard.Item
    let file: UploadedFile
    let zoom: CGFloat
    var pointer: WorktreeCanvasPointer? = nil
    var move: WorktreeBoxMove? = nil
    @State private var image: NSImage?
    @State private var hasLanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = item.size ?? image.map {
            WorktreePhotoGeometry.fitted($0.size, rotation: 0, maximum: 1000)
        } ?? CGSize(width: 320, height: 240)
        let layout = image.map { WorktreePhotoGeometry.covering($0.size, frame: size) }
            ?? WorktreePhotoLayout(contentSize: size)
        ZStack(alignment: .topLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                    .offset(x: layout.offset.x, y: layout.offset.y)
            } else {
                AngroveTheme.Colors.canvasSecondary
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(board.selection.contains(item.id) ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.popupBorder, lineWidth: 1))
        .scaleEffect(hasLanded || reduceMotion ? 1 : 0.98)
        .overlay {
            if image != nil {
                WorktreePhotoResizeHandles(board: board, item: item, size: size, layout: layout, zoom: zoom, pointer: pointer, move: move)
            }
        }
        .task(id: file.id) {
            guard let data = file.imageData else { return }
            image = await Task.detached(priority: .userInitiated) { NSImage(data: data) }.value
            await Task.yield()
            withAnimation(reduceMotion ? nil : .springLively) { hasLanded = true }
        }
        .accessibilityLabel(file.name)
    }
}
