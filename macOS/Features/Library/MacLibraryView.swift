import SwiftUI

/// The desktop Library: the iPhone's shelves, then a reader with its outline beside the text.
struct MacLibraryView: View {
    var navigationRequest: LibraryNavigationRequest?
    let conversations: [InquiryConversation]
    var onAsk: (ConceptDefinition, UUID?) -> Void

    @Environment(\.isBootPageRevealAnimating) private var isPageRevealed
    @State private var catalog: LibraryCatalog?
    @State private var searchText = ""
    @State private var selectedWorkID: String?
    @State private var target = MacLibraryTarget()
    @State private var pendingRequest: LibraryNavigationRequest?
    @State private var clippedPassages = ClippedPassageStore.load()
    @State private var askQuote: ConceptDefinition?
    @State private var pickingConversationFor: ConceptDefinition?
    @State private var clippedCard: ConceptDefinition?
    @EncryptedStringStorage(LibraryRecents.storageKey) private var recentWorkIDsRaw = ""

    private var selectedWork: LibraryWork? { catalog?.works.first { $0.id == selectedWorkID } }

    var body: some View {
        ZStack {
            if let selectedWork {
                MacLibraryReader(work: selectedWork, target: target,
                    onClose: closeWork,
                    onOpenScripture: openScripture,
                    onAsk: { askQuote = $0 },
                    onClip: clip)
                    .id(selectedWork.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                LibraryHomeView(catalog: catalog,
                    recentWorkIDs: LibraryRecents.decode(recentWorkIDsRaw),
                    searchText: $searchText,
                    onOpenWork: { openWork($0.id) },
                    onOpenPassage: { openWork($0.workID, chunk: $0.chunkIndex) },
                    onOpenReading: { apply(LibraryListeningActions.request(for: $0)) },
                    onListen: { work in LibraryListeningActions.toggle(work) { apply($0) } },
                    clippedPassages: clippedPassages,
                    onRemoveClippedPassage: removeClip,
                    onAskClippedPassage: { askQuote = $0 },
                    isPageVisible: isPageRevealed)
                    .frame(maxWidth: MacConversationStyle.pageContentMaxWidth)
                    .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
                    .frame(maxWidth: .infinity)
                    .macSettingsScrollEdges()
                    .transition(.opacity)
            }
        }
        .animation(.springStandard, value: selectedWorkID)
        .background(AngroveTheme.Colors.canvas)
        .environment(\.speechSource, SpeechSource(page: .library))
        .task {
            let loaded = await Task.detached(priority: .userInitiated) { LibraryCatalog.loadBundled() }.value
            withAnimation(.easeOut(duration: 0.25)) { catalog = loaded }
            if let request = pendingRequest ?? navigationRequest {
                pendingRequest = nil
                apply(request)
            }
        }
        .onChange(of: navigationRequest) { _, request in
            guard let request else { return }
            if catalog == nil { pendingRequest = request } else { apply(request) }
        }
        .onChange(of: selectedWorkID) { _, id in
            guard let id else { return }
            recentWorkIDsRaw = LibraryRecents.encode(LibraryRecents.opening(id, in: LibraryRecents.decode(recentWorkIDsRaw)))
        }
        .confirmationDialog("Ask about this passage", isPresented: Binding(
            get: { askQuote != nil }, set: { if !$0 { askQuote = nil } }), titleVisibility: .visible) {
            Button("New Conversation") { if let askQuote { onAsk(askQuote, nil) } }
            Button("Existing Conversation…") { pickingConversationFor = askQuote }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $pickingConversationFor) { quote in
            MacConversationChooser(conversations: conversations) { id in
                pickingConversationFor = nil
                if let id { onAsk(quote, id) }
            }
        }
        .sheet(item: $clippedCard) { passage in
            DynamicInsightSheetCard(word: passage.word, concept: passage, isSaved: false,
                isClipped: clippedPassages.contains { $0.id == passage.id },
                onQuote: { clippedCard = nil; askQuote = passage }, onFork: {}, onToggleSaved: {},
                onToggleClipped: {
                    if clippedPassages.contains(where: { $0.id == passage.id }) { removeClip(passage) } else { clip(passage) }
                })
                .padding(28)
                .frame(width: 520)
                .background(AngroveTheme.Colors.canvas)
        }
    }

    // MARK: Navigation

    private func apply(_ request: LibraryNavigationRequest) {
        guard let works = catalog?.works,
              let work = works.first(where: { $0.id == request.sourceID }) ?? works.first(where: {
                  $0.title.caseInsensitiveCompare(request.sourceTitle) == .orderedSame
                      || $0.title.caseInsensitiveCompare(request.sourceName) == .orderedSame
              }) else { return }
        target = MacLibraryTarget(
            chunkIndex: request.chunkIndex ?? request.resolvedChunkIndex(in: BundledPassageCorpus.bundled()?.passages(forSource: work.id) ?? []),
            readerChunkIndex: request.readerChunkIndex, listeningWordIndex: request.listeningWordIndex,
            startsListening: request.startsListening, sectionTitle: request.sourceTitle, requestID: request.id)
        selectedWorkID = work.id
    }

    private func openWork(_ id: String, chunk: Int? = nil) {
        let word = chunk == nil ? LibraryListeningStore.shared.bookmark(for: id)?.wordIndex : nil
        target = MacLibraryTarget(chunkIndex: chunk, readerChunkIndex: word.map { $0 / LibrarySpeech.wordsPerChunk },
                                  listeningWordIndex: word)
        selectedWorkID = id
    }

    private func openScripture(_ scripture: LibraryTextFormatter.ScriptureTarget) {
        target = MacLibraryTarget(scripture: scripture)
        selectedWorkID = "web-bible"
    }

    private func closeWork() {
        selectedWorkID = nil
        target = MacLibraryTarget()
    }

    // MARK: Clipping

    private func clip(_ passage: ConceptDefinition) {
        if !clippedPassages.contains(where: { $0.id == passage.id }) { clippedPassages.append(passage) }
        ClippedPassageStore.save(clippedPassages)
        clippedCard = passage
    }

    private func removeClip(_ passage: ConceptDefinition) {
        clippedPassages.removeAll { $0.id == passage.id }
        ClippedPassageStore.save(clippedPassages)
    }
}

/// Where the reader should open within a work.
struct MacLibraryTarget: Equatable {
    var chunkIndex: Int?
    var readerChunkIndex: Int?
    var listeningWordIndex: Int?
    var startsListening = false
    var sectionTitle: String?
    var scripture: LibraryTextFormatter.ScriptureTarget?
    var requestID = UUID()
}

// MARK: - Reader

private struct MacLibraryReader: View {
    let work: LibraryWork
    let target: MacLibraryTarget
    var onClose: () -> Void
    var onOpenScripture: (LibraryTextFormatter.ScriptureTarget) -> Void
    var onAsk: (ConceptDefinition) -> Void
    var onClip: (ConceptDefinition) -> Void

    @State private var document: LibraryDocument?
    @State private var hasLoaded = false
    @State private var sectionID = ""
    @State private var outlineID = ""
    @State private var highlightedChunk: Int?
    @State private var isTextVisible = false
    private var speech: ResponseSpeechPlayer { .shared }

    var body: some View {
        Group {
            if let document {
                reader(document)
            } else if hasLoaded {
                AngroveEmptyState(systemImage: "book.closed", title: "Document unavailable",
                                  message: "The complete text could not be loaded. Please reopen the Library.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LibraryLoadingView()
            }
        }
        .task(id: target) { await load() }
        .onExitCommand(perform: onClose)
    }

    private func reader(_ document: LibraryDocument) -> some View {
        let sectionIndex = document.sections.firstIndex { $0.id == sectionID } ?? 0
        let section = document.sections[sectionIndex]
        let outline = document.sections.node(withID: outlineID) ?? section
        return HStack(alignment: .top, spacing: 0) {
            MacLibraryOutline(sections: document.sections, selectedOutlineID: outline.id, onClose: onClose) { id in
                let path = document.sections.path(to: id)
                show(sectionID: path?.first?.id ?? sectionID, outlineID: path?.last?.firstReadableDescendant.id ?? id)
            }
            .frame(width: 260)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        LibraryReaderHeader(subject: LibrarySubject.of(workID: work.id).generalTitle, title: document.title,
                            context: document.context,
                            isListening: speech.phase(for: speechKey(outline)) == .speaking && !speech.isPaused,
                            onListen: { listen(document, outline: outline) })
                            .id("reader-top")
                        LibraryTextSection(
                            title: outline.id == section.id || outline.title.contains(": ") ? outline.title : "\(section.title): \(outline.title)",
                            passages: document.passages.filter { outline.chunks.contains($0.chunkIndex) },
                            sourceID: work.id, speechKey: speechKey(outline), highlightedChunkIndex: highlightedChunk,
                            isVisible: isTextVisible, onOpenScripture: onOpenScripture,
                            onAsk: { onAsk(quote($0, book: section.title)) },
                            onClip: { onClip(quote($0, book: section.title)) },
                            onReadFromHere: { chunk, word in
                                listen(document, outline: outline, fromWord: chunk * LibrarySpeech.wordsPerChunk + word)
                            })
                            .id(outline.id)
                        pageButtons(document, index: sectionIndex)
                    }
                    .frame(maxWidth: MacConversationStyle.pageContentMaxWidth)
                    .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
                    .padding(.top, MacConversationStyle.pageTopPadding)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: isTextVisible) { _, visible in
                    guard visible else { return }
                    if let word = target.listeningWordIndex, outline.chunks.contains(word / LibrarySpeech.wordsPerChunk) {
                        proxy.scrollTo(word / LibrarySpeech.wordsPerChunk, anchor: .center)
                    } else if let chunk = highlightedChunk, outline.chunks.contains(chunk) {
                        withAnimation(.springStandard) { proxy.scrollTo(chunk, anchor: .top) }
                    } else {
                        proxy.scrollTo("reader-top", anchor: .top)
                    }
                }
                .onChange(of: speech.scrollRequest) { _, _ in
                    guard speech.activeLibraryWorkID == work.id else { return }
                    withAnimation(.springStandard) { proxy.scrollTo(ReadingScroll.activeWordID, anchor: .center) }
                }
            }
        }
    }

    private func pageButtons(_ document: LibraryDocument, index: Int) -> some View {
        HStack {
            if index > 0 {
                let previous = document.sections[index - 1]
                Button { show(sectionID: previous.id, outlineID: previous.firstReadableDescendant.id) } label: {
                    Label(previous.title, systemImage: "chevron.left")
                }
            }
            Spacer()
            if index < document.sections.count - 1 {
                let next = document.sections[index + 1]
                Button { show(sectionID: next.id, outlineID: next.firstReadableDescendant.id) } label: {
                    Label(next.title, systemImage: "chevron.right").labelStyle(MacTrailingIconLabel())
                }
            }
        }
        .buttonStyle(.plain)
        .font(AngroveTheme.Typography.uiSubheading)
        .foregroundStyle(AngroveTheme.Colors.lightGreen)
        .lineLimit(1)
    }

    private func load() async {
        isTextVisible = false
        hasLoaded = false
        let work = work
        let loaded = await Task.detached(priority: .userInitiated) { LibraryDocument.loadComplete(work) }.value
        guard !Task.isCancelled else { return }
        document = loaded
        hasLoaded = true
        guard let loaded, let first = loaded.sections.first else { return }
        sectionID = first.id
        outlineID = first.firstReadableDescendant.id
        highlightedChunk = target.chunkIndex.flatMap { loaded.readerIndex(forRetrievalChunk: $0) }
        if let title = target.sectionTitle,
           let match = loaded.sections.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            sectionID = match.id
            outlineID = match.firstReadableDescendant.id
        }
        if let scripture = target.scripture, let bookTitle = LibraryDocument.bibleBookTitle(forCode: scripture.bookCode),
           let book = loaded.sections.first(where: { $0.title == bookTitle }) {
            sectionID = book.id
            outlineID = book.children.first(where: { $0.title == "Chapter \(scripture.chapter)" })?.id ?? book.firstReadableDescendant.id
        }
        for chunk in [target.readerChunkIndex, highlightedChunk].compactMap({ $0 }) {
            if let path = loaded.sections.path(containingChunk: chunk), let section = path.first, let outline = path.last {
                sectionID = section.id
                outlineID = outline.id
            }
        }
        if target.startsListening, let outline = loaded.sections.node(withID: outlineID) {
            listen(loaded, outline: outline, fromWord: target.listeningWordIndex)
        }
        await Task.yield()
        withAnimation(.easeIn(duration: 0.25)) { isTextVisible = true }
    }

    private func show(sectionID: String, outlineID: String) {
        withAnimation(.easeOut(duration: 0.2)) { isTextVisible = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            self.sectionID = sectionID
            self.outlineID = outlineID
            highlightedChunk = nil
            withAnimation(.easeIn(duration: 0.2)) { isTextVisible = true }
        }
    }

    private func quote(_ text: String, book: String) -> ConceptDefinition {
        ConceptDefinition(id: stableUUID(from: "library-quote:\(work.id):\(text.lowercased())"), word: work.title,
            partOfSpeech: "", pronunciation: "", meaning: text, example: "", context: work.title, isLibraryQuote: true,
            libraryAttribution: LibraryWorkAttribution.line(workID: work.id, bibleBook: work.id == "web-bible" ? book : nil))
    }

    private func speechKey(_ outline: LibrarySection) -> String {
        LibrarySpeech.key(workID: work.id, outlineID: outline.id)
    }

    /// Reads the page aloud, resumes its bookmark, or pauses it, as the iPhone reader does.
    private func listen(_ document: LibraryDocument, outline: LibrarySection, fromWord word: Int? = nil) {
        let passages = document.passages.filter { outline.chunks.contains($0.chunkIndex) }
        let units = LibrarySpeech.units(for: passages, sourceID: work.id)
        let key = speechKey(outline)
        let source = SpeechSource(title: work.title, page: .library, libraryWorkID: work.id, libraryIndex: document.listeningIndex)
        if let word {
            speech.read(key, units: units, fromWord: word, source: source)
        } else if speech.activeText == key, speech.phase != .idle {
            if speech.isPaused { speech.resume() } else { speech.pause() }
        } else if let bookmark = LibraryListeningStore.shared.bookmark(for: work.id),
                  bookmark.progress < 1, outline.chunks.contains(bookmark.readerChunkIndex) {
            speech.read(key, units: units, fromWord: bookmark.wordIndex, source: source)
        } else {
            speech.toggleStarting(key, units: units, source: source)
        }
    }
}

private struct MacTrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// The work's outline as a desktop sidebar: chapters, with the open chapter's parts beneath it.
private struct MacLibraryOutline: View {
    let sections: [LibrarySection]
    let selectedOutlineID: String
    var onClose: () -> Void
    var onSelect: (String) -> Void

    private var selectedPath: [String] { sections.path(to: selectedOutlineID)?.map(\.id) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacBackCapsule(title: String(localized: "Library"), isPadded: false, action: onClose)

            Text("Contents")
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundStyle(AngroveTheme.Colors.placeholderText)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(sections) { section in
                            row(section, depth: 0)
                            if selectedPath.first == section.id {
                                ForEach(section.children) { child in
                                    row(child, depth: 1)
                                    if selectedPath.dropFirst().first == child.id {
                                        ForEach(child.children) { row($0, depth: 2) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.automatic)
                .onAppear { proxy.scrollTo(selectedPath.first, anchor: .center) }
            }
        }
        .padding(.top, MacConversationStyle.pageTopPadding)
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AngroveTheme.Colors.canvas)
    }

    private func row(_ node: LibrarySection, depth: Int) -> some View {
        ContentsRow(title: node.title, isSelected: selectedPath.contains(node.id)) { onSelect(node.id) }
            .padding(.leading, CGFloat(depth) * 14)
            .id(node.id)
    }
}

/// Picks an existing conversation for a passage, newest first.
struct MacConversationChooser: View {
    let conversations: [InquiryConversation]
    var onChoose: (UUID?) -> Void
    @State private var query = ""

    private var matches: [InquiryConversation] {
        let sorted = MacSidebarConversationActions.sorted(conversations.filter { !$0.isStudyTopic })
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sorted : sorted.filter { MacStudyTopicsView.title(of: $0).localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacPageHeading(title: "Existing Conversations")
            StudyTopicsSearchField(searchText: $query, prompt: Text("Search Conversations"))
            if matches.isEmpty {
                Text("There are no matching conversations yet.")
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(matches) { conversation in
                            Button { onChoose(conversation.id) } label: {
                                Text(MacStudyTopicsView.title(of: conversation))
                                    .font(AngroveTheme.Typography.bodyLarge)
                                    .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            HStack {
                Spacer()
                Button("Cancel") { onChoose(nil) }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(AngroveTheme.Colors.canvas)
    }
}
