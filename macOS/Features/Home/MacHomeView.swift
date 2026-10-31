import SwiftUI

/// The desktop Home page. It reuses the iPhone dashboard's sections and on-device selectors,
/// arranged as a month-at-a-glance header followed by full-width reading sections.
struct MacHomeView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    var onOpenConversation: (UUID) -> Void
    var onStart: (NewConversationRequest) -> Void
    var onOpenInsights: () -> Void
    var onQuoteInsight: (ConceptDefinition) -> Void = { _ in }
    var onOpenGuide: () -> Void = {}
    var onNewConversation: () -> Void = {}
    var queuePopup: ModelTasksPopupState? = nil
    @State private var ownQueuePopup = ModelTasksPopupState()
    @State private var activeInsight: ConceptDefinition?
    @State private var readingWorks: [RecommendedWork] = []
    @AppStorage(NewUserCardEligibility.firstUseKey) private var firstUse: Double = 0
    @AppStorage(MacHomeStartHere.openedKey) private var openedGuide = false

    @State private var savedInsights = InsightLibraryStore.load()
    @State private var studyTopics = StudyTopicStore.load()
    @State private var usageMonth = MonthlyUsageStore.currentMonth()
    @State private var questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
    @State private var todayInHistory: TodayInHistoryCard?
    @State private var looseThread: LooseThreadCard?
    @State private var glossedTerm: GlossedTermCard?
    @State private var yourQuote: YourQuoteCard?
    @State private var bridge: HomeInsightBridgeSuggestion?
    @State private var vineParallax = HomeVineParallax()
    @State private var isSingleColumn = false
    @Environment(\.isBootPageRevealAnimating) private var isPageRevealed

    private var regularConversations: [InquiryConversation] { conversations.filter { !$0.isStudyTopic } }

    private var featuredConversation: InquiryConversation? {
        HomeConversationResume.featuredConversation(in: regularConversations, activeConversationID: activeConversationID)
    }

    private var unfinishedCount: Int {
        regularConversations.filter(HomeDashboardContent.isUnfinished)
            .filter { $0.id != featuredConversation?.id }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 72) {
                if isSingleColumn {
                    VStack(alignment: .leading, spacing: 48) {
                        MacHomeHeader()
                        ViewThatFits(in: .horizontal) {
                            calendarRow
                            calendarStack
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        // The greeting and the calendar share one row, 84 points apart.
                        HStack(alignment: .center, spacing: 84) {
                            MacHomeHeader()
                            calendarRow
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Narrower: the stats drop below the calendar, and the greeting lines up with its top.
                        HStack(alignment: .top, spacing: 84) {
                            MacHomeHeader()
                            calendarStack
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // The question of the day takes a row of its own.
                MacHomeModelDownloadCard()
                if let questionOfTheDay {
                    // Alone in its row, but only as wide as one column's cards.
                    columns(stackedSpacing: 0) {
                        HomeFigmaQuestionCard(question: questionOfTheDay.question, surfaceColor: AngroveTheme.Colors.canvasSecondary) {
                            onStart(questionOfTheDay.conversationRequest)
                        }
                        .macHomeHover()
                    } trailing: {
                        Color.clear.frame(height: 0)
                    }
                    .transition(.blurFade)
                }
                columns { leadingColumn } trailing: { trailingColumn }
                readingSection
            }
            .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
            // Once the cards stack, the calendar moves under the greeting and the vine shrinks.
            .onGeometryChange(for: Bool.self) { $0.size.width < Self.twoColumnMinWidth } action: { isSingleColumn = $0 }
            .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
            .padding(.top, MacConversationStyle.pageTopPadding)
            // Clears the floating New Conversation control at the bottom of the window.
            .padding(.bottom, 140)
            .macOverlayScroller()
            .frame(maxWidth: .infinity)
            .zIndex(1)
            // The vine sits on its own layer beneath all of the page's content.
            .background(alignment: .topTrailing) {
                // In two columns, twice the iPhone's size, so the vine reaches down into the question row.
                HomeVineWind(width: isSingleColumn ? 211 : 422, parallax: vineParallax)
                    .padding(.top, 24)
                    .zIndex(-1)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            vineParallax.scrollOffset = offset
        }
        .scrollIndicators(.automatic)
        .environment(\.homeCardsHover, true)
        .background(AngroveTheme.Colors.canvas)
        .background {
            MacPageControls(actions: [MacPageControlAction(title: String(localized: "New Conversation"), symbol: "plus", action: onNewConversation)],
                modelTasks: MacApplicationRuntime.shared.modelTasks, queuePopup: queuePopup ?? ownQueuePopup)
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .macConversationSaved)) { _ in
            savedInsights = InsightLibraryStore.load()
            studyTopics = StudyTopicStore.load()
        }
        .sheet(item: $activeInsight) { insight in
            MacHomeInsightSheet(insight: insight, isSaved: savedInsights.contains { $0.id == insight.id },
                onQuote: { activeInsight = nil; onQuoteInsight(insight) },
                onToggleSaved: { toggleSaved(insight) })
        }
        .task(id: savedInsights) {
            let insights = savedInsights
            let suggestion = await Task.detached(priority: .utility) {
                HomeDashboardContent.bridgeSuggestion(from: insights)
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { bridge = suggestion }
        }
    }

    // MARK: Columns

    /// Two 448-point columns and their gutter: wider than a reading page, narrower than the
    /// card grids, so lines and cards keep a comfortable length on a large display.
    static let contentMaxWidth: CGFloat = 960
    /// Two 320-point columns and their gutter; below this the columns stack.
    static let twoColumnMinWidth: CGFloat = 320 * 2 + 64

    /// Side by side when the window allows, stacked otherwise; empty trailing content collapses.
    private func columns(stackedSpacing: CGFloat = 64, @ViewBuilder _ leading: () -> some View,
                         @ViewBuilder trailing: () -> some View) -> some View {
        let leading = leading()
        let trailing = trailing()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 64) {
                leading.frame(minWidth: 320, idealWidth: 320, maxWidth: .infinity)
                trailing.frame(minWidth: 320, idealWidth: 320, maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: stackedSpacing) {
                leading
                trailing
            }
        }
    }

    private var leadingColumn: some View {
        VStack(alignment: .leading, spacing: 64) {
            if let featuredConversation {
                VStack(alignment: .leading, spacing: 20) {
                    HomeFigmaSectionTitle("Where You Left Off")
                    MacHomeResumeCard(conversation: featuredConversation,
                                      latestText: HomeDashboardContent.latestText(in: featuredConversation),
                                      insights: HomeDashboardContent.insights(for: featuredConversation, savedInsights: savedInsights),
                                      onOpenInsight: { activeInsight = $0 }) {
                        onOpenConversation(featuredConversation.id)
                    }
                }
            }

            if let work = listeningWork {
                LibraryListeningCard(work: work, surfaceColor: AngroveTheme.Colors.canvasSecondary, isPageVisible: isPageRevealed, onListen: {
                    LibraryListeningActions.toggle(work) { openInLibrary($0) }
                }) { openInLibrary(LibraryListeningActions.request(for: work)) }
                    .macHomeHover()
                    .id(work.id)
                    .transition(.blurFade)
            }

            if MacHomeStartHere.shows(firstUse: firstUse, openedGuide: openedGuide) {
                MacHomeStartHere {
                    openedGuide = true
                    onOpenGuide()
                }
            }

        }
    }

    private var trailingColumn: some View {
        VStack(alignment: .leading, spacing: 64) {
            if let todayInHistory {
                HomeTodayInHistorySection(card: todayInHistory, isPageVisible: true) {
                    onStart(NewConversationRequest(question: todayInHistory.title, eyebrow: "TODAY IN HISTORY",
                        promptContext: todayInHistory.taggedPromptContext, subtitle: todayInHistory.description))
                }
                .transition(.blurFade)
            }
            discoveryColumn
        }
    }

    /// Reading suggestions close the page, below everything else.
    @ViewBuilder private var readingSection: some View {
        if !readingWorks.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HomeFigmaSectionTitle("Read Material")
                ForEach(readingWorks, id: \.title) { work in
                    Button {
                        openInLibrary(LibraryNavigationRequest(sourceTitle: work.title, sourceName: work.sourceName))
                    } label: { HomeFigmaReadingRow(work: work).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
        }
    }

    private var calendarRow: some View {
        HStack(alignment: .center, spacing: 24) {
            HomeFigmaUsageGrid(month: usageMonth, cellSize: 22)
            statsGrid
        }
        .fixedSize()
    }

    private var calendarStack: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaUsageGrid(month: usageMonth, cellSize: 22)
            statsGrid
        }
        .fixedSize()
    }

    private var statsGrid: some View {
        HomeFigmaStatsGrid(conversationCount: regularConversations.count, insightCount: savedInsights.count,
                           studyTopicCount: studyTopics.count, unfinishedCount: unfinishedCount)
            .frame(width: 220)
    }

    @ViewBuilder private var discoveryColumn: some View {
        let sections = discoverySections
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 48) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 { HomeFigmaDivider() }
                    section.view
                }
            }
        }
    }

    private var discoverySections: [MacHomeSection] {
        var result: [MacHomeSection] = []
        if let bridge {
            result.append(MacHomeSection(id: "bridge", view: AnyView(
                HomeInsightBridgeSection(suggestion: bridge, surfaceColor: AngroveTheme.Colors.canvasSecondary,
                    onOpenInsight: { activeInsight = $0 }, onOpen: onOpenInsights))))
        }
        if let looseThread {
            result.append(MacHomeSection(id: "loose", view: AnyView(
                HomeLooseThreadSection(card: looseThread, surfaceColor: AngroveTheme.Colors.canvasSecondary) {
                    onOpenConversation(looseThread.conversationID)
                })))
        }
        if let glossedTerm {
            result.append(MacHomeSection(id: "glossed", view: AnyView(
                HomeGlossedTermSection(card: glossedTerm, surfaceColor: AngroveTheme.Colors.canvasSecondary) {
                    activeInsight = glossedTerm.concept
                })))
        }
        if let yourQuote {
            result.append(MacHomeSection(id: "quote", view: AnyView(HomeYourQuoteSection(card: yourQuote))))
        }
        return result
    }

    private var listeningWork: LibraryWork? {
        let speech = ResponseSpeechPlayer.shared
        guard speech.phase != .idle, let id = speech.activeLibraryWorkID else { return nil }
        return LibraryWork(id: id, title: speech.nowPlayingTitle, passageCount: 0)
    }

    private func openInLibrary(_ request: LibraryNavigationRequest) {
        NotificationCenter.default.post(name: .openGroundingSourceInLibrary, object: request)
    }

    private func toggleSaved(_ insight: ConceptDefinition) {
        var library = InsightLibraryStore.load()
        if library.contains(where: { $0.id == insight.id }) { library.removeAll { $0.id == insight.id } }
        else { library.append(insight) }
        InsightLibraryStore.save(library)
        savedInsights = library
    }

    // MARK: Loading

    private func refresh() async {
        // The Mac never had the iPhone's Documents-date heuristic; its first visit starts the week.
        if firstUse <= 0 { firstUse = Date().timeIntervalSince1970 }
        MonthlyUsageStore.recordVisitIfNeeded()
        usageMonth = MonthlyUsageStore.currentMonth()
        savedInsights = InsightLibraryStore.load()
        studyTopics = StudyTopicStore.load()
        questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
        readingWorks = RecommendedReading.works(for: regularConversations)
        let today = HomeDiscovery.todayInHistory()
        var loose: LooseThreadCard?
        var glossed: GlossedTermCard?
        var quote: YourQuoteCard?
        if let id = HomeSectionSourceSelector.selectConversationID(conversations: conversations,
                                                                    activeConversationID: activeConversationID) {
            glossed = HomeDiscovery.glossedTerm(in: GlossedTermStore.records(for: id), savedInsightIDs: Set(savedInsights.map(\.id)))
            quote = HomeDiscovery.yourQuote(in: id)
            loose = await HomeDiscovery.looseThread(in: id, savedInsights: savedInsights,
                                                    embeddingProvider: MacApplicationRuntime.shared.embeddingProvider)
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            todayInHistory = today
            looseThread = loose
            glossedTerm = glossed
            yourQuote = quote
        }
        requestQuestionOfTheDayIfNeeded()
    }

    /// Mirrors the iPhone refresh: one background task drafts a question from a recent
    /// conversation through the shared model boundary; failure leaves the card absent.
    private func requestQuestionOfTheDayIfNeeded() {
        let runtime = MacApplicationRuntime.shared
        guard questionOfTheDay == nil, runtime.modelIsAvailable,
              HomeQuestionOfTheDayStore.isEligibleForRefresh(),
              !runtime.modelTasks.contains(where: { $0.kind == .refreshQuestionOfTheDay }),
              let source = DailyQuestionSourceSelector.select(conversations: conversations, savedInsights: savedInsights)
        else { return }
        runtime.modelTasks.enqueue(kind: .refreshQuestionOfTheDay, originPage: .home, priority: .background) {
            guard let draft = try? await runtime.model.generateQuestionOfTheDay(
                from: source.context, conversationTitle: source.conversation.title,
                insights: Array(source.insights.prefix(4))), !Task.isCancelled else { return }
            let text = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard HomeQuestionOfTheDay.isValidQuestionText(text) else { return }
            let cited = draft.citedInsightTitle.flatMap { title in
                source.insights.first { $0.word.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            }
            let generated = HomeQuestionOfTheDay(question: text,
                reasonForAsking: draft.reasonForAsking.trimmingCharacters(in: .whitespacesAndNewlines),
                citedInsight: cited, sourceConversationID: source.conversation.id,
                sourceConversationTitle: source.conversation.title)
            HomeQuestionOfTheDayStore.save(generated)
            withAnimation(.easeInOut(duration: 0.35)) { questionOfTheDay = generated }
        }
    }
}

private struct MacHomeSection: Identifiable {
    let id: String
    let view: AnyView
}

private struct MacHomeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsAnimatedHeading(title: HomeDashboardContent.todayString(), font: AngroveTheme.Typography.uiLabel,
                                    color: AngroveTheme.Colors.lightGreen, visibilityThreshold: 0.01, revealsOnAppear: true)
            MacHomeGreeting(greeting: HomeDashboardContent.greeting(), name: MacPersonalization.greetingName)
        }
    }
}

// MARK: - Greeting

private struct MacHomeGreeting: View {
    let greeting: String
    let name: String

    var body: some View {
        let greetingWords = "\(greeting),".split(separator: " ").map(String.init)
        let nameWords = name.split(separator: " ").map(String.init)
        var text = Text(verbatim: "")
        for (index, word) in greetingWords.enumerated() {
            text = text + Text(verbatim: index == 0 ? "" : " ")
                + Text(verbatim: word).font(MacPageHeading.pageFont).foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .customAttribute(SettingsRevealWord(index: index))
        }
        for (index, word) in nameWords.enumerated() {
            text = text + Text(verbatim: index == 0 ? "\n" : " ")
                + Text(verbatim: word).font(.custom("LibreBaskerville-Italic", fixedSize: 40)).foregroundColor(AngroveTheme.Colors.lightGreen)
                    .customAttribute(SettingsRevealWord(index: greetingWords.count + index))
        }
        return SettingsAnimatedHeading(text: text, wordCount: greetingWords.count + nameWords.count,
                                       accessibilityLabel: "\(greeting), \(name)", visibilityThreshold: 0.01)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cards

enum MacHomePreviewText {
    static func plainText(from text: String) -> String {
        let prose = InlineInsightMarkup.plainText(from: text)
        guard let parsed = try? AttributedString(markdown: prose,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return prose }
        return String(parsed.characters)
    }
}

private struct MacHomeResumeCard: View {
    let conversation: InquiryConversation
    let latestText: String
    let insights: [ConceptDefinition]
    var onOpenInsight: (ConceptDefinition) -> Void
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .angroveIcon(.small)
                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    }
                    Text(MacStudyTopicsView.title(of: conversation))
                        .font(AngroveTheme.Typography.uiHeading)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .angroveIcon(.small, .strong)
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                }
                Text(verbatim: MacHomePreviewText.plainText(from: latestText))
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .lineSpacing(6)
                    .lineLimit(3)
                if !insights.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(insights.prefix(4)) { insight in
                            Button { onOpenInsight(insight) } label: {
                                Label(insight.word, systemImage: "text.bubble.fill")
                                    .font(AngroveTheme.Typography.uiSubheading)
                                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .macHomeHover()
        .accessibilityHint("Opens the conversation")
    }
}

/// The iPhone's first-week card, pointing at the Mac User Guide until it has been opened.
private struct MacHomeStartHere: View {
    static let openedKey = "angrove.mac.home.user-guide-opened"
    var onOpen: () -> Void

    static func shows(firstUse: Double, openedGuide: Bool, now: Date = Date()) -> Bool {
        !openedGuide && firstUse > 0 && now.timeIntervalSince1970 - firstUse < NewUserCardEligibility.lifetime
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Getting Started with Angrove")
                    .font(AngroveTheme.Typography.illustratedCardHeading)
                    .foregroundStyle(AngroveTheme.Colors.illustratedCardTitle)
                    .lineSpacing(7)
                    .frame(maxWidth: 300, minHeight: 84, alignment: .topLeading)
                Text("See User Guide")
                    .font(AngroveTheme.Typography.uiSubheading)
                    .foregroundStyle(AngroveTheme.Colors.canvas)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AngroveTheme.Colors.lightGreen, in: Capsule())
            }
            .multilineTextAlignment(.leading)
            .padding(AngroveTheme.Spacing.illustratedCardPadding)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                Image("HomeUserStart")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360)
                    .accessibilityHidden(true)
            }
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .macHomeHover()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Getting Started with Angrove. See User Guide")
        .accessibilityAddTraits(.isButton)
    }
}

/// The shared Insight card, as the iPhone's Home sheet presents it.
private struct MacHomeInsightSheet: View {
    let insight: ConceptDefinition
    let isSaved: Bool
    var onQuote: () -> Void
    var onToggleSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InsightLibraryCard(insight: insight, isSaved: isSaved, maxWidth: 520, shadowOpacity: 0,
                           onQuote: onQuote, onFork: onQuote, onToggleSaved: onToggleSaved)
            .padding(24)
            .frame(width: 568)
            .background(AngroveTheme.Colors.canvas)
            .onExitCommand { dismiss() }
    }
}

private extension View {
    func macHomeHover() -> some View { homeCardHover() }
}
