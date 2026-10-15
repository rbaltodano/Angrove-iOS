import os
import SwiftUI

struct LibraryView: View {
    let onOpenMenu: () -> Void
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    let onReaderVisibilityChange: (Bool) -> Void
    let navigationRequest: LibraryNavigationRequest?
    var onAskInNewConversation: (ConceptDefinition) -> Void = { _ in }
    var onAskInExistingConversation: (ConceptDefinition) -> Void = { _ in }
    var clippedPassages: [ConceptDefinition] = []
    var onRemoveClippedPassage: (ConceptDefinition) -> Void = { _ in }
    var onSaveClippedPassage: (ConceptDefinition) -> Void = { _ in }
    @State private var catalog: LibraryCatalog?
    @State private var searchText = ""
    @State private var dismissSearchFocusRequest = 0
    @State private var selectedWorkID: String?
    @State private var targetChunkIndex: Int?
    @State private var targetReaderChunkIndex: Int?
    @State private var targetListeningWordIndex: Int?
    @State private var startsListening = false
    @State private var readerRequestID: UUID?
    @State private var targetScripture: LibraryTextFormatter.ScriptureTarget?
    @State private var pendingNavigationRequest: LibraryNavigationRequest?
    @State private var isAskMode = false
    @State private var selectedLibraryQuote: ConceptDefinition?
    @State private var showsClippedPassageAskChoices = false
    @State private var clippedPassageCard: ConceptDefinition?
    @State private var viewportHeight: CGFloat = 1
    @EncryptedStringStorage(LibraryRecents.storageKey) private var recentWorkIDsRaw = ""

    private var works: [LibraryWork] { catalog?.works ?? [] }

    private var selectedWork: LibraryWork? {
        works.first { $0.id == selectedWorkID }
    }

    var body: some View {
        ZStack {
            LibraryHomeView(
                catalog: catalog,
                recentWorkIDs: LibraryRecents.decode(recentWorkIDsRaw),
                searchText: $searchText,
                dismissSearchFocusRequest: dismissSearchFocusRequest,
                onOpenWork: { openWork(id: $0.id) },
                onOpenPassage: { openWork(id: $0.workID, atChunk: $0.chunkIndex) },
                onOpenReading: openReading,
                onListen: resumeListening,
                clippedPassages: clippedPassages,
                onRemoveClippedPassage: onRemoveClippedPassage,
                onAskClippedPassage: askAboutClippedPassage,
                isPageVisible: selectedWorkID == nil
            )

            if let selectedWork {
                LibraryDocumentDetail(
                    work: selectedWork,
                    targetTitle: navigationRequest?.sourceTitle,
                    targetChunkIndex: targetChunkIndex,
                    targetReaderChunkIndex: targetReaderChunkIndex,
                    targetListeningWordIndex: targetListeningWordIndex,
                    startsListening: startsListening,
                    onListeningStarted: { startsListening = false },
                    targetScripture: targetScripture,
                    navigationRequestID: readerRequestID,
                    modelTasks: modelTasks,
                    modelTasksPopupState: modelTasksPopupState,
                    isAskMode: $isAskMode,
                    selectedLibraryQuote: $selectedLibraryQuote,
                    onAskNewConversation: { if let selectedLibraryQuote { onAskInNewConversation(selectedLibraryQuote); isAskMode = false } },
                    onAskExistingConversation: { if let selectedLibraryQuote { onAskInExistingConversation(selectedLibraryQuote); isAskMode = false } },
                    onCancelAsk: { isAskMode = false; selectedLibraryQuote = nil },
                    onOpenScripture: openScripture,
                    onClip: clipPassage
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            VStack {
                HStack(spacing: 8) {
                    AngroveNavButton(onMenuTap: onOpenMenu)
                    if selectedWorkID != nil {
                        NavBackCapsuleButton(title: "Library", action: closeDocument)
                            .transition(.studyExitGrow)
                    }
                    Spacer()
                }
                .animation(.springStandard, value: selectedWorkID)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(20)
        }
        .animation(.springStandard, value: selectedWorkID)
        .onChange(of: selectedWorkID) { _, id in
            modelTasksPopupState.reset()
            onReaderVisibilityChange(id != nil)
            if let id {
                recentWorkIDsRaw = LibraryRecents.encode(
                    LibraryRecents.opening(id, in: LibraryRecents.decode(recentWorkIDsRaw))
                )
            }
        }
        .onDisappear { onReaderVisibilityChange(false) }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .sheet(item: $clippedPassageCard) { passage in
            LibraryClippedPassageDrawer(
                passage: passage,
                isClipped: clippedPassages.contains { $0.id == passage.id },
                maximumHeight: viewportHeight * 0.82,
                onAsk: {
                    clippedPassageCard = nil
                    selectedLibraryQuote = passage
                    isAskMode = true
                },
                onToggleClipped: {
                    if clippedPassages.contains(where: { $0.id == passage.id }) {
                        onRemoveClippedPassage(passage)
                    } else {
                        onSaveClippedPassage(passage)
                    }
                }
            )
        }
        .confirmationDialog("Ask about this passage", isPresented: $showsClippedPassageAskChoices, titleVisibility: .visible) {
            Button("New Conversation") {
                if let selectedLibraryQuote { onAskInNewConversation(selectedLibraryQuote) }
            }
            Button("Existing Conversation") {
                if let selectedLibraryQuote { onAskInExistingConversation(selectedLibraryQuote) }
            }
            Button("Cancel", role: .cancel) { selectedLibraryQuote = nil }
        }
        .task {
            // The bundled corpus is tens of megabytes; decode it off the main actor so the
            // homepage chrome appears immediately.
            let loaded = await Task.detached(priority: .userInitiated) {
                LibraryCatalog.loadBundled()
            }.value
            withAnimation(.easeOut(duration: 0.25)) { catalog = loaded }
            // A request that opened the Library arrives as the initial value, which `onChange`
            // never reports; one that arrived while the catalog loaded is held as pending.
            if let request = pendingNavigationRequest ?? navigationRequest {
                pendingNavigationRequest = nil
                applyNavigationRequest(request)
            }
        }
        .onChange(of: navigationRequest) { _, request in
            guard let request else { return }
            if catalog == nil {
                pendingNavigationRequest = request
            } else {
                applyNavigationRequest(request)
            }
        }
    }

    private func applyNavigationRequest(_ request: LibraryNavigationRequest) {
        guard let work = works.first(where: { $0.id == request.sourceID })
            ?? works.first(where: {
                $0.title.caseInsensitiveCompare(request.sourceTitle) == .orderedSame
                    || $0.title.caseInsensitiveCompare(request.sourceName) == .orderedSame
            }) else { return }
        targetScripture = nil
        targetReaderChunkIndex = request.readerChunkIndex
        targetListeningWordIndex = request.listeningWordIndex
        startsListening = request.startsListening
        readerRequestID = request.id
        targetChunkIndex = request.chunkIndex ?? request.resolvedChunkIndex(
            in: BundledPassageCorpus.bundled()?.passages(forSource: work.id) ?? []
        )
        selectedWorkID = work.id
    }

    /// Opens the work being read aloud on the page being read, and scrolls to the word.
    private func openReading(_ work: LibraryWork) {
        withAnimation(.springStandard) {
            applyNavigationRequest(LibraryListeningActions.request(for: work))
        }
    }

    private func resumeListening(_ work: LibraryWork) {
        LibraryListeningActions.toggle(work) { request in
            withAnimation(.springStandard) { applyNavigationRequest(request) }
        }
    }

    private func openScripture(_ target: LibraryTextFormatter.ScriptureTarget) {
        dismissSearchFocusRequest += 1
        withAnimation(.springStandard) {
            targetChunkIndex = nil
            targetReaderChunkIndex = nil
            targetListeningWordIndex = nil
            startsListening = false
            targetScripture = target
            selectedWorkID = "web-bible"
        }
    }

    private func openWork(id: String, atChunk chunkIndex: Int? = nil) {
        dismissSearchFocusRequest += 1
        withAnimation(.springStandard) {
            targetScripture = nil
            targetListeningWordIndex = chunkIndex == nil ? LibraryListeningStore.shared.bookmark(for: id)?.wordIndex : nil
            targetReaderChunkIndex = targetListeningWordIndex.map { $0 / LibrarySpeech.wordsPerChunk }
            startsListening = false
            targetChunkIndex = chunkIndex
            selectedWorkID = id
        }
    }

    private func closeDocument() {
        isAskMode = false
        selectedLibraryQuote = nil
        withAnimation(.springStandard) {
            selectedWorkID = nil
            targetChunkIndex = nil
            targetReaderChunkIndex = nil
            targetListeningWordIndex = nil
            startsListening = false
            targetScripture = nil
        }
    }

    private func clipPassage(_ passage: ConceptDefinition) {
        isAskMode = false
        selectedLibraryQuote = nil
        onSaveClippedPassage(passage)
        clippedPassageCard = passage
    }

    private func askAboutClippedPassage(_ passage: ConceptDefinition) {
        selectedLibraryQuote = passage
        showsClippedPassageAskChoices = true
    }
}

private struct LibraryDocumentDetail: View {
    private struct ReaderLocation: Equatable {
        let workID: String
        let chunkIndex: Int?
        let readerChunkIndex: Int?
        let listeningWordIndex: Int?
        let scripture: LibraryTextFormatter.ScriptureTarget?
        let requestID: UUID?
    }
    private static let readerTopID = "reader-top"
    let work: LibraryWork
    let targetTitle: String?
    var targetChunkIndex: Int?
    /// A reader paragraph whose page to open, without featuring the paragraph.
    var targetReaderChunkIndex: Int?
    var targetListeningWordIndex: Int?
    var startsListening = false
    var onListeningStarted: () -> Void = {}
    var targetScripture: LibraryTextFormatter.ScriptureTarget?
    let navigationRequestID: UUID?
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @Binding var isAskMode: Bool
    @Binding var selectedLibraryQuote: ConceptDefinition?
    var onAskNewConversation: () -> Void
    var onAskExistingConversation: () -> Void
    var onCancelAsk: () -> Void
    let onOpenScripture: (LibraryTextFormatter.ScriptureTarget) -> Void
    let onClip: (ConceptDefinition) -> Void
    @State private var document: LibraryDocument?
    @State private var readerTargetChunkIndex: Int?
    @State private var hasFinishedLoading = false
    @State private var selectedSectionID = "chapter-1"
    @State private var selectedOutlineID = "chapter-1"
    @State private var isContentsOpen = false
    @State private var isPageTextVisible = true
    @State private var pageTransitionTask: Task<Void, Never>?
    private var speech: ResponseSpeechPlayer { .shared }

    private func libraryQuote(_ text: String, bibleBook: String) -> ConceptDefinition {
        ConceptDefinition(
            id: stableUUID(from: "library-quote:\(work.id):\(text.lowercased())"),
            word: work.title,
            partOfSpeech: "",
            pronunciation: "",
            meaning: text,
            example: "",
            context: work.title,
            isLibraryQuote: true,
            libraryAttribution: LibraryWorkAttribution.line(
                workID: work.id,
                bibleBook: work.id == "web-bible" ? bibleBook : nil
            )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            AngroveTheme.Colors.canvas.ignoresSafeArea()
            if let document {
                let selectedIndex = document.sections.firstIndex(where: { $0.id == selectedSectionID }) ?? 0
                let selectedSection = document.sections[selectedIndex]
                let selectedOutline = document.sections.node(withID: selectedOutlineID) ?? selectedSection
                let visibleChunks = selectedOutline.chunks
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 32) {
                            LibraryReaderHeader(
                                subject: LibrarySubject.of(workID: work.id).generalTitle,
                                title: document.title,
                                context: document.context,
                                isListening: speech.phase(for: speechKey(outline: selectedOutline)) == .speaking && !speech.isPaused,
                                onListen: { listen(document: document, outline: selectedOutline) }
                            )
                            .id(Self.readerTopID)
                            LibraryTextSection(
                                title: selectedOutline.id == selectedSection.id || selectedOutline.title.contains(": ")
                                    ? selectedOutline.title
                                    : "\(selectedSection.title): \(selectedOutline.title)",
                                passages: document.passages.filter { visibleChunks.contains($0.chunkIndex) },
                                sourceID: work.id,
                                speechKey: speechKey(outline: selectedOutline),
                                highlightedChunkIndex: readerTargetChunkIndex,
                                isVisible: isPageTextVisible,
                                onOpenScripture: onOpenScripture,
                                onAsk: { selectedText in
                                    selectedLibraryQuote = libraryQuote(selectedText, bibleBook: selectedSection.title)
                                    isAskMode = true
                                },
                                onClip: { selectedText in
                                    onClip(libraryQuote(selectedText, bibleBook: selectedSection.title))
                                },
                                onReadFromHere: { chunkIndex, word in
                                    listen(
                                        document: document, outline: selectedOutline,
                                        fromWord: chunkIndex * LibrarySpeech.wordsPerChunk + word
                                    )
                                }
                            )
                            .id(selectedOutline.id)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 140)
                    }
                    // Clears the floating menu and back buttons, including for scroll-to-passage.
                    .safeAreaPadding(.top, 88)
                    .onChange(of: speech.scrollRequest) { _, _ in
                        scrollToWordBeingRead(with: proxy)
                    }
                    .onChange(of: isPageTextVisible) { _, visible in
                        guard visible else { return }
                        if targetListeningWordIndex.map({ visibleChunks.contains($0 / LibrarySpeech.wordsPerChunk) }) == true ||
                            (speech.isScrollRequestFresh && speech.activeLibraryWorkID == work.id) {
                            scrollToWordBeingRead(with: proxy)
                            return
                        }
                        if let targetChunkIndex = readerTargetChunkIndex, visibleChunks.contains(targetChunkIndex) {
                            withAnimation(.springStandard) {
                                proxy.scrollTo(targetChunkIndex, anchor: .top)
                            }
                        } else {
                            // A new page or work starts at its heading, not the prior scroll offset.
                            proxy.scrollTo(Self.readerTopID, anchor: .top)
                        }
                    }
                }
                // Keep the controls publisher mounted while chapter text changes (it publishes to
                // the shell's single Model Controls bar and renders nothing here). Giving the
                // ScrollView the outline ID would recreate it on every chapter navigation.
                .background {
                        LibraryModelControls(
                            modelTasks: modelTasks,
                            modelTasksPopupState: modelTasksPopupState,
                            isContentsOpen: $isContentsOpen,
                            previousChapterTitle: selectedIndex > 0 ? "\(document.navigationUnit) \(selectedIndex)" : nil,
                            nextChapterTitle: selectedIndex < document.sections.count - 1 ? "\(document.navigationUnit) \(selectedIndex + 2)" : nil,
                            onPreviousChapter: {
                                transitionToPage(
                                    sectionID: document.sections[selectedIndex - 1].id,
                                    outlineID: document.sections[selectedIndex - 1].firstReadableDescendant.id
                                )
                            },
                            onNextChapter: {
                                transitionToPage(
                                    sectionID: document.sections[selectedIndex + 1].id,
                                    outlineID: document.sections[selectedIndex + 1].firstReadableDescendant.id
                                )
                            },
                            isAskMode: $isAskMode,
                            onAskNewConversation: onAskNewConversation,
                            onAskExistingConversation: onAskExistingConversation,
                            onCancelAsk: onCancelAsk
                        ) {
                            LibraryContentsCard(
                                sections: document.sections,
                                selectedOutlineID: selectedOutlineID,
                                onSelectOutline: { outlineID in
                                    let sectionID = document.sections.first(where: { $0.id == outlineID })?.id
                                        ?? selectedSectionID
                                    transitionToPage(sectionID: sectionID, outlineID: outlineID)
                                    withAnimation(.springStandard) {
                                        isContentsOpen = true
                                    }
                                }
                            )
                        }
                    }
            } else if hasFinishedLoading {
                AngroveEmptyState(
                    systemImage: "book.closed",
                    title: "Document unavailable",
                    message: "The complete text could not be loaded. Please reopen the Library."
                )
                .frame(maxHeight: .infinity)
            } else {
                LibraryLoadingView()
            }
        }
        .onDisappear {
            pageTransitionTask?.cancel()
        }
        .task(id: ReaderLocation(
            workID: work.id,
            chunkIndex: targetChunkIndex,
            readerChunkIndex: targetReaderChunkIndex,
            listeningWordIndex: targetListeningWordIndex,
            scripture: targetScripture,
            requestID: navigationRequestID
        )) {
            pageTransitionTask?.cancel()
            isPageTextVisible = false
            hasFinishedLoading = false
            // Outlining a work walks every passage; keep it off the main actor.
            let work = work
            let loadedDocument = await Task.detached(priority: .userInitiated) {
                LibraryDocument.loadComplete(work)
            }.value
            guard !Task.isCancelled else { return }
            document = loadedDocument
            hasFinishedLoading = true
            readerTargetChunkIndex = targetChunkIndex.flatMap { loadedDocument?.readerIndex(forRetrievalChunk: $0) }
            selectedSectionID = document?.sections.first?.id ?? "chapter-1"
            selectedOutlineID = document?.sections.first?.firstReadableDescendant.id ?? "chapter-1"
            if let targetTitle,
               let match = document?.sections.first(where: { $0.title.caseInsensitiveCompare(targetTitle) == .orderedSame }) {
                selectedSectionID = match.id
                selectedOutlineID = match.firstReadableDescendant.id
            }
            if let targetScripture,
               let bookTitle = LibraryDocument.bibleBookTitle(forCode: targetScripture.bookCode),
               let book = document?.sections.first(where: { $0.title == bookTitle }) {
                selectedSectionID = book.id
                selectedOutlineID = book.children.first(where: { $0.title == "Chapter \(targetScripture.chapter)" })?.id
                    ?? book.firstReadableDescendant.id
            }
            if let readerChunk = targetReaderChunkIndex,
               let path = document?.sections.path(containingChunk: readerChunk),
               let section = path.first, let outline = path.last {
                selectedSectionID = section.id
                selectedOutlineID = outline.id
            }
            if let targetChunkIndex = readerTargetChunkIndex,
               let path = document?.sections.path(containingChunk: targetChunkIndex),
               let section = path.first, let outline = path.last {
                selectedSectionID = section.id
                selectedOutlineID = outline.id
            }
            if startsListening, let document,
               let outline = document.sections.node(withID: selectedOutlineID) {
                listen(document: document, outline: outline, fromWord: targetListeningWordIndex)
                onListeningStarted()
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                isPageTextVisible = true
            }
        }
    }

    /// Brings the word being read into view once its paragraph has laid out and marked itself.
    private func scrollToWordBeingRead(with proxy: ScrollViewProxy) {
        guard targetListeningWordIndex != nil || (speech.isScrollRequestFresh && speech.activeLibraryWorkID == work.id) else { return }
        if let word = targetListeningWordIndex ?? speech.activeWord ?? speech.firstWord {
            proxy.scrollTo(word / LibrarySpeech.wordsPerChunk, anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard isPageTextVisible else { return }
            withAnimation(.springStandard) {
                proxy.scrollTo(ReadingScroll.activeWordID, anchor: .center)
            }
        }
    }

    private func speechKey(outline: LibrarySection) -> String {
        LibrarySpeech.key(workID: work.id, outlineID: outline.id)
    }

    /// Reads the page on screen aloud from its first paragraph, or stops it if it is being read.
    private func listen(document: LibraryDocument, outline: LibrarySection, fromWord word: Int? = nil) {
        let passages = document.passages.filter { outline.chunks.contains($0.chunkIndex) }
        let units = LibrarySpeech.units(for: passages, sourceID: work.id)
        let source = SpeechSource(title: work.title, page: .library, libraryWorkID: work.id, libraryIndex: document.listeningIndex)
        if let word {
            speech.read(speechKey(outline: outline), units: units, fromWord: word, source: source)
        } else if speech.activeText == speechKey(outline: outline), speech.phase != .idle {
            if speech.isPaused { speech.resume() } else { speech.pause() }
        } else if let bookmark = LibraryListeningStore.shared.bookmark(for: work.id),
                  bookmark.progress < 1, outline.chunks.contains(bookmark.readerChunkIndex) {
            speech.read(speechKey(outline: outline), units: units, fromWord: bookmark.wordIndex, source: source)
        } else {
            speech.toggleStarting(speechKey(outline: outline), units: units, source: source)
        }
    }

    private func transitionToPage(sectionID: String, outlineID: String) {
        pageTransitionTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            isPageTextVisible = false
        }

        pageTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            selectedSectionID = sectionID
            selectedOutlineID = outlineID
            await Task.yield()
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.2)) {
                isPageTextVisible = true
            }
        }
    }
}

// MARK: - Passage Locator

/// Short, human-readable locations for corpus passages ("John 14", "Nicomachean Ethics, Book V"),
/// drawn from the same outline the Library reader shows. Outlines are built once per work.
/// Matches the conversation's Insight drawer, with scrolling for long clipped passages.
private struct LibraryClippedPassageDrawer: View {
    let passage: ConceptDefinition
    let isClipped: Bool
    let maximumHeight: CGFloat
    let onAsk: () -> Void
    let onToggleClipped: () -> Void
    @State private var contentHeight: CGFloat = 178

    var body: some View {
        ScrollView {
            DynamicInsightSheetCard(
                word: passage.word,
                concept: passage,
                isSaved: false,
                isClipped: isClipped,
                onQuote: onAsk,
                onFork: {},
                onToggleSaved: {},
                onToggleClipped: onToggleClipped
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: InsightSheetContentHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .onPreferenceChange(InsightSheetContentHeightKey.self) { contentHeight = $0 }
        .presentationDetents([.height(min(max(contentHeight + 24, 202), max(maximumHeight, 202)))])
        .presentationDragIndicator(.visible)
        .presentationBackground(AngroveTheme.Colors.canvas)
    }
}
