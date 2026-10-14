import AppKit
import SwiftUI

struct MacConversationView: View {
    let showsFixture: Bool
    let session: MacConversationState
    let onSend: () -> Void
    @Binding var question: String
    @State private var offset: CGFloat = 0
    @State private var position = ScrollPosition()
    @State private var isQuestionFocused = false
    @StateObject private var slashQuery = SlashCommandQuery()
    @State private var dismissesCommands = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isComposerVisible: Bool {
        session.isComposerReady || isQuestionFocused || !question.isEmpty || session.quote != nil
    }

    private var showsCommands: Bool {
        isQuestionFocused && !dismissesCommands && question.hasPrefix("/") && !question.contains(where: \.isWhitespace)
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = min(650, max(140, geometry.size.width - 64))
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
                .padding(.top, (geometry.size.height >= 700 ? 200 : 100) + 24)
                .padding(.bottom, 350)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, newValue in
                offset = newValue
            }
            .overlay(alignment: .top) {
                if offset > 200 {
                    ZStack(alignment: .top) {
                        edgeFade(top: true)
                            .ignoresSafeArea(.container, edges: .top)
                        Text(showsFixture ? "Conversation Title" : session.title)
                            .font(MacConversationStyle.pinnedTitle)
                            .foregroundStyle(AngroveTheme.Colors.headingText)
                            .padding(.top, 48)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if !showsCommands && (offset > 200 || geometry.size.height < 700) { edgeFade(top: false) }
            }
            .task {
                if showsFixture && MacDesignPreview.startsScrolled {
                    position.scrollTo(y: 323)
                }
                if session.quote != nil { focusComposer() }
            }
            .onChange(of: session.quoteRequest) { _, _ in focusComposer() }
            .onChange(of: session.isComposerReady) { _, ready in
                if !ready && question.isEmpty && session.quote == nil {
                    isQuestionFocused = false
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                MacIconView(icon: .studyTopic)
                Text(showsFixture ? "AUGUSTINIAN PREDESTINATION" : "A NEW INQUIRY")
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
            }
            .frame(height: 18)
            MacLineText(text: showsFixture ? "What Should We Study Today Ryan?" : "What Should We Study Today?", serif: true, size: 28, lineHeight: 34)
                .foregroundStyle(AngroveTheme.Colors.headingText)
        }
        .frame(maxWidth: 350, alignment: .leading)
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
                Picker("Conversation branch", selection: Bindable(session).selectedBranch) {
                    ForEach(session.branches) { branch in
                        Text(branch.startingConcept?.word ?? "Main conversation").tag(branch.id)
                    }
                }
            }
            ForEach(Array(session.transcript.enumerated()), id: \.offset) { index, block in
                switch block {
                case .user(let text, let concept, _):
                    VStack(alignment: .trailing, spacing: 8) {
                        if let concept { quoteChip(concept, removable: false) }
                        QuotedQuestionContainer(isEmpty: false,
                            lineHeight: MacConversationStyle.questionLineHeight,
                            fontName: MacConversationStyle.questionFontName) {
                            MacLineText(text: text, serif: true, lineHeight: MacConversationStyle.questionLineHeight)
                                .frame(maxWidth: MacConversationStyle.questionContentWidth(text), alignment: .leading)
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
                        ModelResponseCard(title: "", fullText: text, shouldAnimateOnAppear: session.shouldRevealResponse(transcriptIndex: index),
                            showsThinkingIntro: session.isPending(transcriptIndex: index) || session.presentation(transcriptIndex: index)?.showsThinking == true, isAwaitingResponse: text.isEmpty && session.isPending(transcriptIndex: index), isReceivingStream: !text.isEmpty && session.isPending(transcriptIndex: index),
                            isQueuedForModel: session.isQueued(transcriptIndex: index),
                            usesIncrementalStream: session.usesIncrementalResponse(transcriptIndex: index),
                            thinkingSummary: session.summary(transcriptIndex: index),
                            liveThought: session.liveThought(transcriptIndex: index),
                            thinkingDurationSeconds: session.thinkingDuration(transcriptIndex: index),
                            groundingSources: session.sources(transcriptIndex: index),
                            evidenceBasis: session.presentation(transcriptIndex: index)?.evidenceBasis,
                            conversationFontSize: MacConversationStyle.bodyFontSize,
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
                    Text("Inquire Connection").font(AngroveTheme.Typography.uiHeading)
                    ForEach(session.connectionConcepts) { concept in Text(concept.word) }
                    Button("Remove connection") { session.connectionConcepts = [] }
                }.foregroundStyle(AngroveTheme.Colors.lightGreen)
            }
        }
        .id(session.selectedBranch)
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let concept = session.quote { quoteChip(concept, removable: true) }
            QuotedQuestionContainer(isEmpty: question.isEmpty,
                lineHeight: MacConversationStyle.questionLineHeight,
                fontName: MacConversationStyle.questionFontName,
                onTapToFocus: { isQuestionFocused = true }) {
                MacCommandEditor(text: $question,
                    isFocused: Binding(get: { isQuestionFocused }, set: { isQuestionFocused = $0 }),
                    reduceMotion: reduceMotion, onSubmit: onSend,
                    onEscape: { dismissesCommands = true })
                    .frame(width: min(MacConversationStyle.questionContentWidth(question, minimum: "Ask a question..."),
                                      MacConversationStyle.questionMaxWidth - 36))
                    .accessibilityLabel("Ask a question")
            }
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
            onRemove: session.removeQuote)
            .frame(maxWidth: MacConversationStyle.questionMaxWidth, alignment: .trailing)
    }

    private func focusComposer() {
        position.scrollTo(id: "question-composer", anchor: .center)
        isQuestionFocused = true
    }

    private func edgeFade(top: Bool) -> some View {
        MacConversationEdgeFade(top: top)
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
        return view
    }

    func updateNSView(_ view: Editor, context: Context) {
        context.coordinator.parent = self
        if view.string != text, !view.hasMarkedText() {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        view.reduceMotion = reduceMotion
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

        func refreshHighlight() {
            guard !hasMarkedText() else { return }
            let token = string.split(whereSeparator: \.isWhitespace).first.map(String.init)
            let next = SlashCommand.invocation(for: string) != nil ? token?.lowercased() : nil
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
