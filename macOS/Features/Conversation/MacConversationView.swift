import AppKit
import SwiftUI

struct MacConversationView: View {
    let showsFixture: Bool
    let session: MacConversationState
    let onSend: () -> Void
    @Binding var question: String
    var focusQuestionRequest = 0
    var onChooseTopic: () -> Void = {}
    @State private var displayedEyebrow = ""
    @State private var isEyebrowHidden = false
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var responseSize: ConversationFontSizeOption = .medium
    // Read so a change in Settings redraws questions in the chosen face.
    @AppStorage(MacConversationStyle.questionFontKey) private var questionFont: ConversationFontOption = .serif
    @State private var position = ScrollPosition()
    @State private var isQuestionFocused = false
    @StateObject private var slashQuery = SlashCommandQuery()
    @State private var dismissesCommands = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isComposerVisible: Bool {
        session.isComposerReady || isQuestionFocused || !question.isEmpty || session.quote != nil || !session.uploads.isEmpty
    }

    private var showsCommands: Bool {
        isQuestionFocused && !dismissesCommands && question.hasPrefix("/") && !question.contains(where: \.isWhitespace)
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = min(MacConversationStyle.conversationColumnMaxWidth, max(140, geometry.size.width - MacConversationStyle.pageHorizontalPadding * 2))
            ScrollView {
                VStack(alignment: .trailing, spacing: 48) {
                    introduction
                    #if DEBUG
                    if showsFixture {
                        sampleTurn
                        if MacDesignPreview.startsScrolled { sampleTurn }
                    }
                    #endif
                    transcript
                    composer
                        .opacity(isComposerVisible ? 1 : 0)
                        .allowsHitTesting(isComposerVisible)
                        .accessibilityHidden(!isComposerVisible)
                        .animation(reduceMotion ? nil : ResponseRevealTiming.finishingAnimation, value: isComposerVisible)
                        .id("question-composer")
                }
                .frame(width: columnWidth)
                .padding(.top, MacConversationStyle.pageTopPadding)
                .padding(.bottom, 350)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .scrollPosition($position)
            .modifier(MacConversationScrollChrome(title: showsFixture ? "Conversation Title" : session.title,
                isCompact: geometry.size.height < 700, showsCommands: showsCommands))
            .task {
                if showsFixture && MacDesignPreview.startsScrolled {
                    position.scrollTo(y: 323)
                }
                if session.quote != nil { focusComposer() }
            }
            .onChange(of: focusQuestionRequest, initial: true) { _, request in
                if request > 0 { focusComposer() }
            }
            .onChange(of: session.quoteRequest) { _, _ in focusComposer() }
            .onChange(of: session.isComposerReady) { _, ready in
                if !ready && question.isEmpty && session.quote == nil {
                    isQuestionFocused = false
                }
            }
        }
    }

    /// The header mirrors the iPhone: a pinned daily prompt keeps its own heading, otherwise the
    /// heading follows the conversation's title until one exists.
    private var header: (title: String, subtitle: String?) {
        if showsFixture { return ("What Should We Study Today Ryan?", nil) }
        if let branch = session.activeBranch,
           let pinned = branch.pinnedHeaderQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !pinned.isEmpty {
            let context = branch.hiddenPromptContext ?? ""
            if context.contains("<question of the day>") { return (String(localized: "Question of the Day"), pinned) }
            if let entry = TodayInHistoryCatalog.entry(matchingPromptContext: context) { return (entry.title, entry.description) }
            return (pinned, nil)
        }
        return (session.title == "New Conversation" ? "What Should We Study Today?" : session.title, nil)
    }

    private var eyebrowText: String {
        if showsFixture { return "AUGUSTINIAN PREDESTINATION" }
        if let id = session.studyTopicID, let topic = StudyTopicStore.load().first(where: { $0.id == id }) {
            let title = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title.uppercased() }
        }
        return "ADD TO STUDY TOPIC"
    }

    private var introduction: some View {
        let header = header
        return VStack(alignment: .leading, spacing: 8) {
            Button(action: onChooseTopic) {
                HStack(spacing: 4) {
                    MacIconView(icon: .studyTopic)
                    Text(displayedEyebrow)
                        .font(AngroveTheme.Typography.uiLabel)
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .opacity(isEyebrowHidden ? 0 : 1)
                        .blur(radius: isEyebrowHidden ? 4 : 0)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityHint("Assigns this conversation to a Study Topic")
            .onAppear { displayedEyebrow = eyebrowText }
            .onChange(of: eyebrowText) { _, text in
                // Fade the old topic out, then glide the new one in, as on iPhone.
                withAnimation(.easeIn(duration: 0.2)) { isEyebrowHidden = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.springLively) {
                        displayedEyebrow = text
                        isEyebrowHidden = false
                    }
                }
            }
            ConversationHeading(title: header.title) { title in
                MacPageHeading(title: title, font: MacPageHeading.pageFont)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let subtitle = header.subtitle {
                Text(subtitle)
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .lineSpacing(7)
                    .padding(.top, 8)
                    .settingsTextReveal()
            }
        }
        .frame(maxWidth: header.subtitle == nil ? 350 : 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if DEBUG
    private var sampleTurn: some View {
        VStack(alignment: .trailing, spacing: 48) {
            MacLineText(text: MacDesignPreview.question, serif: true)
                .frame(maxWidth: MacConversationStyle.questionMaxWidth, alignment: .trailing)
            MacLineText(text: MacDesignPreview.response)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .accessibilityHint("Sample text from Figma, shown only in the design preview")
    }
    #endif

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 36) {
            if session.branches.count > 1 {
                MacMenuPicker(title: "Conversation branch", selection: Bindable(session).selectedBranch,
                              options: session.branches.map { ($0.id, $0.startingConcept?.word ?? String(localized: "Main conversation")) })
            }
            ForEach(Array(session.transcript.enumerated()), id: \.offset) { index, block in
                switch block {
                case .user(let text, let concept, let uploads):
                    VStack(alignment: .trailing, spacing: 8) {
                        if let concept { quoteChip(concept, removable: false) }
                        if !uploads.isEmpty { MacAttachmentStrip(files: uploads) }
                        QuotedQuestionContainer(isEmpty: false,
                            lineHeight: MacConversationStyle.questionLineHeight,
                            fontName: MacConversationStyle.questionFontName,
                            maximumWidth: MacConversationStyle.questionMaxWidth) {
                            // The same width and ink as the composer, so submitting doesn't reflow the question.
                            MacLineText(text: text, serif: MacConversationStyle.usesSerifQuestions, lineHeight: MacConversationStyle.questionLineHeight)
                                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                                .frame(maxWidth: min(MacConversationStyle.questionContentWidth(text), MacConversationStyle.questionMaxWidth - 36), alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: MacConversationStyle.questionMaxWidth, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                case .text(let text):
                    if text == questionCanceledResponseText {
                        Text(text).font(AngroveTheme.Typography.body).foregroundStyle(AngroveTheme.Colors.placeholderText)
                    } else {
                        let run = session.responseRun(transcriptIndex: index)
                        let presentation = MacConversationResponsePresentation(text: text, isPending: session.isPending(transcriptIndex: index))
                        ModelResponseCard(title: "", fullText: presentation.visibleText, shouldAnimateOnAppear: session.shouldRevealResponse(transcriptIndex: index),
                            showsThinkingIntro: session.isPending(transcriptIndex: index) || session.presentation(transcriptIndex: index)?.showsThinking == true, isAwaitingResponse: presentation.isAwaitingResponse, isReceivingStream: presentation.isWriting,
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
                            onRegenerate: { session.regenerate(transcriptIndex: index, runtime: MacApplicationRuntime.shared) },
                            onInsightTap: { session.define($0, source: $1, runtime: MacApplicationRuntime.shared) },
                            onInlineInsightQuote: session.attachQuote,
                            onInlineInsightFork: session.fork,
                            onInlineInsightToggleSaved: session.toggleBookmark,
                            onBodyRevealComplete: { if let run { session.finishResponseBodyReveal(run: run) } },
                            onFinish: { if let run { session.finishResponseReveal(run: run) } })
                            .id(run)
                            .environment(\.defineResponseWord, { request in
                                if let term = DefinedTermMarkup.term(in: request.token) { session.define(term, source: text, runtime: MacApplicationRuntime.shared) }
                            })
                    }
                }
            }
            if !session.connectionConcepts.isEmpty {
                VStack(alignment: .leading) {
                    MacPageHeading(title: "Inquire Connection")
                    ForEach(session.connectionConcepts) { concept in Text(concept.word) }
                    Button("Remove connection") { session.connectionConcepts = [] }
                }.foregroundStyle(AngroveTheme.Colors.lightGreen)
            }
        }
        .id(session.selectedBranch)
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let concept = session.quote {
                quoteChip(concept, removable: true)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
            if !session.uploads.isEmpty {
                MacAttachmentStrip(files: session.uploads) { id in
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .springLively) { session.removeUpload(id) }
                }
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
            QuotedQuestionContainer(isEmpty: question.isEmpty,
                lineHeight: MacConversationStyle.questionLineHeight,
                fontName: MacConversationStyle.questionFontName,
                maximumWidth: MacConversationStyle.questionMaxWidth,
                onTapToFocus: focusQuestionField) {
                MacCommandEditor(text: $question,
                    isFocused: Binding(get: { isQuestionFocused }, set: { isQuestionFocused = $0 }),
                    reduceMotion: reduceMotion, onSubmit: onSend,
                    onEscape: {
                        if showsCommands { dismissesCommands = true } else { isQuestionFocused = false }
                    })
                    .frame(width: min(MacConversationStyle.questionContentWidth(question, minimum: "Ask a question..."),
                                      MacConversationStyle.questionMaxWidth - 36))
                    .accessibilityLabel("Ask a question")
            }
                // Anywhere across the field's row starts typing, not only on the text itself.
                .contentShape(Rectangle())
                .onTapGesture { focusQuestionField() }
                .onChange(of: question) { _, text in
                    slashQuery.text = text
                    dismissesCommands = false
                }
                .onAppear { slashQuery.text = question }
                .onKeyPress(.escape) {
                    guard showsCommands else { return .ignored }
                    dismissesCommands = true
                    return .handled
                }
            if showsCommands {
                SlashCommandMenu(query: slashQuery,
                    commands: SlashCommand.all + [SlashCommand(name: "/define", description: "Define a word or subject")],
                    maxHeight: 230) { command in
                        question = command.name + " "
                        isQuestionFocused = true
                    }
                    .modifier(MacMenuScaleIn())
                    .modifier(MacMenuTextReveal())
                    .frame(maxWidth: MacConversationStyle.questionMaxWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task(id: showsCommands) {
            guard showsCommands else { return }
            await Task.yield()
            position.scrollTo(id: "question-composer", anchor: .center)
        }
    }

    private func quoteChip(_ concept: ConceptDefinition, removable: Bool) -> some View {
        BranchContextChip(title: concept.isLibraryQuote ? concept.word : concept.word.capitalized,
            icon: concept.isLibraryQuote ? "books.vertical" : "text.bubble",
            isFilled: !removable, animatesAppearance: removable, showRemove: removable,
            onTap: { session.selectedDefinition = concept },
            onRemove: {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .springLively) {
                    session.removeQuote()
                }
            })
            .frame(maxWidth: MacConversationStyle.questionMaxWidth, alignment: .trailing)
    }

    /// Re-asserts focus even when the flag is already set but the editor has lost the responder.
    private func focusQuestionField() {
        isQuestionFocused = false
        DispatchQueue.main.async { isQuestionFocused = true }
    }

    private func focusComposer() {
        position.scrollTo(id: "question-composer", anchor: .center)
        isQuestionFocused = true
    }
}

/// The Mac reveals the completed answer in one pass. Stream updates drive the
/// Writing status without mounting independent paragraph reveal tasks.
struct MacConversationResponsePresentation {
    let text: String
    let isPending: Bool

    var visibleText: String { isPending ? "" : text }
    var isAwaitingResponse: Bool { isPending }
    var isWriting: Bool { isPending && !text.isEmpty }
}

/// Keep scroll observation below the transcript's update boundary. Only crossing
/// the heading threshold changes state; pixel offsets never rebuild response cards.
struct MacConversationScrollChrome: ViewModifier {
    let title: String
    let isCompact: Bool
    let showsCommands: Bool
    @State private var showsPinnedTitle = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y + $0.contentInsets.top > 200
            } action: { _, isPastHeading in
                showsPinnedTitle = isPastHeading
            }
            .overlay(alignment: .top) {
                if showsPinnedTitle {
                    ZStack(alignment: .top) {
                        MacConversationEdgeFade(top: true)
                            .ignoresSafeArea(.container, edges: .top)
                        ConversationHeading(title: title) { title in
                            MacPageHeading(title: title, font: MacConversationStyle.pinnedTitle)
                        }
                            .padding(.top, 48)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if !showsCommands && (showsPinnedTitle || isCompact) {
                    MacConversationEdgeFade(top: false)
                }
            }
    }
}

struct MacConversationEdgeFade: View {
    let top: Bool
    var body: some View {
        LinearGradient(stops: [
            .init(color: MacConversationStyle.edgeFade, location: 0),
            .init(color: MacConversationStyle.edgeFade, location: 0.15787),
            .init(color: MacConversationStyle.edgeFade.opacity(0), location: 1)
        ], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
        .frame(height: 200)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Native editing keeps the command sweep in the text storage, leaving selection and
/// the insertion point intact. Return submits; Shift-Return inserts a line break.
struct MacCommandEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let reduceMotion: Bool
    let onSubmit: () -> Void
    let onEscape: () -> Void
    /// Which leading text counts as a command for the green sweep; the conversation's by default.
    var recognizesCommand: (String) -> Bool = { SlashCommand.invocation(for: $0) != nil }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Editor {
        let view = Editor()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainerInset = NSSize(width: 0, height: AngroveTheme.Spacing.unit / 2)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.font = MacConversationStyle.questionNativeFont
        view.insertionPointColor = NSColor(AngroveTheme.Colors.lightGreen)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = AngroveTheme.Spacing.unit
        view.defaultParagraphStyle = paragraph
        view.typingAttributes[.paragraphStyle] = paragraph
        return view
    }

    func updateNSView(_ view: Editor, context: Context) {
        context.coordinator.parent = self
        if view.string != text, !view.hasMarkedText() {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        view.reduceMotion = reduceMotion
        view.recognizesCommand = recognizesCommand
        view.refreshHighlight()
        if isFocused, view.window?.firstResponder !== view {
            DispatchQueue.main.async { [weak view] in
                guard let view, context.coordinator.parent.isFocused else { return }
                view.window?.makeFirstResponder(view)
            }
        } else if !isFocused, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Editor, context: Context) -> CGSize? {
        let width = proposal.width ?? MacConversationStyle.questionMaxWidth - 36
        nsView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        if let container = nsView.textContainer { nsView.layoutManager?.ensureLayout(for: container) }
        let height = nsView.textContainer.flatMap { nsView.layoutManager?.usedRect(for: $0).height } ?? 0
        return CGSize(width: width, height: max(MacConversationStyle.questionLineHeight, ceil(height) + nsView.textContainerInset.height * 2))
    }

    static func dismantleNSView(_ view: Editor, coordinator: Coordinator) { view.timer?.invalidate() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacCommandEditor
        init(_ parent: MacCommandEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? Editor else { return }
            parent.text = view.string
            view.refreshHighlight()
            view.invalidateIntrinsicContentSize()
        }
        func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        func textDidEndEditing(_ notification: Notification) { parent.isFocused = false }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)),
               !NSEvent.modifierFlags.contains(.shift) { parent.onSubmit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            return false
        }
    }

    final class Editor: NSTextView {
        var reduceMotion = false
        var recognizesCommand: (String) -> Bool = { SlashCommand.invocation(for: $0) != nil }
        var timer: Timer?
        private var command: String?
        private var waveStart = Date.distantPast

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty {
                ("Ask a question..." as NSString).draw(at: NSPoint(x: 0, y: textContainerInset.height),
                    withAttributes: [.font: MacConversationStyle.questionNativeFont,
                                     .foregroundColor: NSColor(AngroveTheme.Colors.placeholderText)])
            }
        }

        override func layout() { super.layout(); applyHighlight() }

        private var clickMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            guard window != nil else { return }
            // Clicking anywhere outside the field ends editing.
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let self, event.window === self.window, self.window?.firstResponder === self,
                   !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.window?.makeFirstResponder(nil)
                }
                return event
            }
        }

        deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }

        override func mouseDown(with event: NSEvent) {
            if window?.firstResponder !== self { window?.makeFirstResponder(self) }
            super.mouseDown(with: event)
        }

        func refreshHighlight() {
            guard !hasMarkedText() else { return }
            // Replacing `string` (draft restoration, command insertion, paste)
            // can leave text storage without the default paragraph style.
            // Apply it to existing text as well as future typing so wrapped
            // questions retain the submitted question's line spacing.
            if let paragraph = defaultParagraphStyle {
                typingAttributes[.paragraphStyle] = paragraph
                if let storage = textStorage, storage.length > 0 {
                    storage.addAttribute(.paragraphStyle, value: paragraph,
                                         range: NSRange(location: 0, length: storage.length))
                }
            }
            let token = string.split(whereSeparator: \.isWhitespace).first.map(String.init)
            let next = recognizesCommand(string) ? token?.lowercased() : nil
            if next != command {
                timer?.invalidate()
                command = next
                waveStart = Date()
                if next != nil, !reduceMotion {
                    timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
                        MainActor.assumeIsolated {
                            guard let self else { timer.invalidate(); return }
                            self.applyHighlight()
                            if Date().timeIntervalSince(self.waveStart) >= 1 { timer.invalidate() }
                        }
                    }
                }
            }
            applyHighlight()
            needsDisplay = true
        }

        private func applyHighlight() {
            guard !hasMarkedText(), let storage = textStorage else { return }
            let base = NSColor(AngroveTheme.Colors.primaryReadable)
            storage.addAttribute(.foregroundColor, value: base, range: NSRange(location: 0, length: storage.length))
            typingAttributes[.foregroundColor] = base
            guard command != nil, let token = string.split(whereSeparator: \.isWhitespace).first else { return }
            let range = (string as NSString).range(of: String(token))
            let green = NSColor(AngroveTheme.Colors.lightGreen)
            var color = green
            let progress = reduceMotion ? 1 : min(1, Date().timeIntervalSince(waveStart))
            if progress < 1, let manager = layoutManager, let container = textContainer, bounds.width > 0 {
                let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                let band = max(rect.width * 0.4, 1)
                let front = rect.minX - band + (rect.width + 2 * band) * progress
                let image = NSImage(size: NSSize(width: bounds.width, height: 1), flipped: false) { _ in
                    guard let gradient = NSGradient(starting: green, ending: base) else { return false }
                    gradient.draw(from: NSPoint(x: front - band, y: 0), to: NSPoint(x: front + band, y: 0),
                                  options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
                    return true
                }
                color = NSColor(patternImage: image)
            }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }
}
