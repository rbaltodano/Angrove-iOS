//
//  HomeDashboardView.swift
//  Angrove-iOS
//

import SwiftUI

// MARK: - Home Dashboard

struct HomeDashboardView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    let savedInsights: [ConceptDefinition]
    let userName: String
    let questionOfTheDay: HomeQuestionOfTheDay?
    let looseThread: LooseThreadCard?
    let todayInHistory: TodayInHistoryCard?
    let glossedTerm: GlossedTermCard?
    let yourQuote: YourQuoteCard?
    var onOpenMenu: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onStartQuestion: (HomeQuestionOfTheDay) -> Void
    var onOpenInsightBridge: (UUID, UUID) -> Void
    var onFocusNode: (UUID) -> Void = { _ in }
    var onStartTodayInHistory: (TodayInHistoryCard) -> Void = { _ in }
    var onOpenUserGuide: () -> Void = {}
    var onRefresh: () -> Void = {}
    var onLoadHomeSections: () async -> Void = {}
    var isPageVisible: Bool = true
    var modelDelivery: ModelDeliveryState = .shared
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NewUserCardEligibility.firstUseKey) private var firstUseTimestamp: Double = 0
    @AppStorage(UserGuideReadingHistory.key) private var visitedGuideTopicsJSON = "[]"
    @State private var eligibilityDate = Date()

    private var showsNewUserCard: Bool {
        let visited = (try? JSONDecoder().decode([String].self, from: Data(visitedGuideTopicsJSON.utf8))) ?? []
        return NewUserCardEligibility.shouldShow(
            firstUse: firstUseTimestamp > 0 ? Date(timeIntervalSince1970: firstUseTimestamp) : nil,
            now: eligibilityDate,
            visited: Set(visited),
            topics: Set(UserGuideTopic.all.map(\.id))
        )
    }

    /// Landscape has ample horizontal room but a much shorter reading lane. This lets the
    /// dashboard use the extra width while releasing vertical pressure on a phone.
    private var usesLandscapeLayout: Bool { verticalSizeClass == .compact }

    private var listeningWork: LibraryWork? {
        let speech = ResponseSpeechPlayer.shared
        guard speech.phase != .idle, let workID = speech.activeLibraryWorkID else { return nil }
        return LibraryWork(id: workID, title: speech.nowPlayingTitle, passageCount: 0)
    }

    private func openListeningWork(_ work: LibraryWork) {
        NotificationCenter.default.post(name: .openGroundingSourceInLibrary,
            object: LibraryListeningActions.request(for: work))
    }

    @State private var vineParallax = HomeVineParallax()
    @State private var studyTopics: [StudyTopic] = []
    @State private var usageMonth = MonthlyUsageStore.currentMonth()
    @State private var activeInsight: ConceptDefinition? = nil
    @State private var readingWorks: [RecommendedWork] = []
    /// Embedding every saved Insight is far too slow for `body`, which re-runs on unrelated
    /// shell changes such as the side menu opening. It is computed off the main actor instead.
    @State private var bridgeSuggestion: HomeInsightBridgeSuggestion?
    /// What the page currently shows of its changing sections; nil until the first appearance.
    @State private var shownSections: HomeLiveSections?
    /// True once Home has finished loading and the reveal pause has passed.
    @State private var canRevealNewSections = false

    private var regularConversations: [InquiryConversation] {
        conversations.filter { !$0.isStudyTopic }
    }

    private var featuredConversation: InquiryConversation? {
        HomeConversationResume.featuredConversation(
            in: regularConversations,
            activeConversationID: activeConversationID
        )
    }

    private var unfinishedConversations: [InquiryConversation] {
        regularConversations
            .filter(HomeDashboardContent.isUnfinished)
            .filter { $0.id != featuredConversation?.id }
    }

    private var liveSections: HomeLiveSections {
        HomeLiveSections(
            question: questionOfTheDay,
            today: todayInHistory,
            loose: looseThread,
            glossed: glossedTerm,
            quote: yourQuote,
            bridge: bridgeSuggestion
        )
    }

    /// Content already present when Home appears shows immediately. Sections that arrive
    /// afterwards wait until loading has finished plus a pause, then fade in with a blur so
    /// the reader can see they are new. Removals apply at once.
    private var sections: HomeLiveSections { shownSections ?? liveSections }

    private func revealNewSections() {
        guard let current = shownSections else { return }
        let live = liveSections
        func merged<Value>(_ shown: Value?, _ live: Value?) -> Value? {
            live == nil || canRevealNewSections ? live : shown
        }
        let next = HomeLiveSections(
            question: merged(current.question, live.question),
            today: merged(current.today, live.today),
            loose: merged(current.loose, live.loose),
            glossed: merged(current.glossed, live.glossed),
            quote: merged(current.quote, live.quote),
            bridge: merged(current.bridge, live.bridge)
        )
        guard next != current else { return }
        withAnimation(.easeInOut(duration: 0.5)) { shownSections = next }
    }

    private func loadHomeSections() {
        Task {
            await onLoadHomeSections()
            try? await Task.sleep(for: .seconds(1))
            canRevealNewSections = true
        }
    }

    private var displayUserName: String {
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "friend" : trimmedName
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AngroveTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: usesLandscapeLayout ? 32 : 48) {
                    Color.clear.frame(height: usesLandscapeLayout ? 24 : 57)

                    VStack(alignment: .leading, spacing: 48) {
                        if let todayInHistory = sections.today {
                            HomeTodayInHistorySection(
                                card: todayInHistory,
                                isPageVisible: isPageVisible,
                                onStartConversation: { onStartTodayInHistory(todayInHistory) }
                            )
                            .transition(.blurFade)
                        }

                        HomeFigmaOpeningSection(
                            greeting: HomeDashboardContent.greeting(),
                            userName: displayUserName,
                            month: usageMonth,
                            conversationCount: regularConversations.count,
                            insightCount: savedInsights.count,
                            studyTopicCount: studyTopics.count,
                            unfinishedCount: unfinishedConversations.count,
                            questionOfTheDay: sections.question,
                            usesLandscapeLayout: usesLandscapeLayout,
                            hidesGreetingHeader: sections.today != nil,
                            onStartQuestion: onStartQuestion,
                            listeningWork: listeningWork,
                            onOpenListeningWork: openListeningWork,
                            modelDelivery: modelDelivery
                        )

                        if showsNewUserCard {
                            HomeFigmaDivider()
                            HomeStartHereSection(isPageVisible: isPageVisible, onOpen: onOpenUserGuide)
                        }

                        HomeFigmaDivider()

                        // A fresh install has nothing to resume; a bare heading reads as broken.
                        if let featuredConversation {
                            HomeFigmaResumeSection(
                                conversation: featuredConversation,
                                latestText: HomeDashboardContent.latestText(in: featuredConversation),
                                insights: HomeDashboardContent.insights(
                                    for: featuredConversation,
                                    savedInsights: savedInsights
                                ),
                                onSelectConversation: onSelectConversation,
                                onOpenInsight: { activeInsight = $0 }
                            )

                            HomeFigmaDivider()
                        }

                        if let bridgeSuggestion = sections.bridge {
                            Group {
                            HomeInsightBridgeSection(
                                suggestion: bridgeSuggestion,
                                onOpenInsight: { activeInsight = $0 },
                                onOpen: {
                                    onOpenInsightBridge(
                                        bridgeSuggestion.first.id,
                                        bridgeSuggestion.second.id
                                    )
                                }
                            )

                            HomeFigmaDivider()
                            }
                            .transition(.blurFade)
                        }

                        if let looseThread = sections.loose {
                            Group {
                            HomeLooseThreadSection(
                                card: looseThread,
                                onOpen: { onFocusNode(looseThread.nodeID) }
                            )

                            HomeFigmaDivider()
                            }
                            .transition(.blurFade)
                        }

                        if let glossedTerm = sections.glossed {
                            Group {
                            HomeGlossedTermSection(
                                card: glossedTerm,
                                onOpen: { activeInsight = glossedTerm.concept }
                            )

                            HomeFigmaDivider()
                            }
                            .transition(.blurFade)
                        }

                        if let yourQuote = sections.quote {
                            Group {
                            HomeYourQuoteSection(card: yourQuote)

                            HomeFigmaDivider()
                            }
                            .transition(.blurFade)
                        }

                        if !readingWorks.isEmpty {
                            HomeFigmaReadingSection(works: readingWorks)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, usesLandscapeLayout ? 48 : 36)
                .frame(maxWidth: usesLandscapeLayout ? 1_120 : .infinity, alignment: .center)
                // The vine hangs from the right edge behind the greeting and scrolls away with it.
                .background(alignment: .topTrailing) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        HomeVineWind(parallax: vineParallax)
                            .padding(.top, usesLandscapeLayout ? 48 : 56)
                    }
                }
                // Hang the left vine 132 points below the streak calendar, behind the page.
                .backgroundPreferenceValue(HomeCalendarBoundsKey.self) { anchor in
                    if let anchor, !usesLandscapeLayout, !dynamicTypeSize.isAccessibilitySize {
                        GeometryReader { proxy in
                            HomeVineWind(side: .left, parallax: vineParallax, depth: 0.055, delay: 0.15, returnDelay: 0.05)
                                .offset(y: proxy[anchor].maxY + 132)
                        }
                    }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                vineParallax.scrollOffset = offset
            }
            .leafRefreshable {
                refreshContent()
            }

            AngroveNavButton(onMenuTap: onOpenMenu)
                .padding(.leading, 24)
                .padding(.top, usesLandscapeLayout ? 12 : 24)
                .zIndex(2)
        }
        .onAppear {
            eligibilityDate = Date()
            MonthlyUsageStore.recordVisitIfNeeded()
            usageMonth = MonthlyUsageStore.currentMonth()
            studyTopics = StudyTopicStore.load()
            readingWorks = RecommendedReading.works(for: regularConversations)
            if shownSections == nil { shownSections = liveSections }
            loadHomeSections()
        }
        .onChange(of: liveSections) { revealNewSections() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { eligibilityDate = Date() }
        }
        .onChange(of: isPageVisible) { _, visible in
            if visible { eligibilityDate = Date() }
        }
        .task(id: firstUseTimestamp) {
            eligibilityDate = Date()
            guard firstUseTimestamp > 0 else { return }
            let remaining = firstUseTimestamp + NewUserCardEligibility.lifetime - Date().timeIntervalSince1970
            guard remaining > 0 else { return }
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            eligibilityDate = Date()
        }
        .onChange(of: canRevealNewSections) { revealNewSections() }
        .task(id: savedInsights) {
            let insights = savedInsights
            let suggestion = await Task.detached(priority: .utility) {
                HomeDashboardContent.bridgeSuggestion(from: insights)
            }.value
            guard !Task.isCancelled else { return }
            bridgeSuggestion = suggestion
        }
        .onChange(of: regularConversations.count) {
            readingWorks = RecommendedReading.works(for: regularConversations)
        }
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: .constant(savedInsights))
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AngroveTheme.Colors.canvas)
        }
    }

    private func refreshContent() {
        usageMonth = MonthlyUsageStore.currentMonth()
        studyTopics = StudyTopicStore.load()
        readingWorks = RecommendedReading.works(for: regularConversations)
        onRefresh()
        loadHomeSections()
    }
}

// MARK: - Figma Home Sections

/// Transparent painted ivy, sized independently of the dashboard's reading layout.
private struct HomeVine: View {
    var body: some View {
        Image("HomeVineMasked")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 128, height: 128)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct HomeFigmaOpeningSection: View {
    let greeting: String
    let userName: String
    let month: MonthlyUsageMonth
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int
    let questionOfTheDay: HomeQuestionOfTheDay?
    let usesLandscapeLayout: Bool
    var hidesGreetingHeader: Bool = false
    var onStartQuestion: (HomeQuestionOfTheDay) -> Void
    var listeningWork: LibraryWork? = nil
    var onOpenListeningWork: (LibraryWork) -> Void = { _ in }
    var modelDelivery: ModelDeliveryState = .shared

    private var animatedGreetingHeading: some View {
        let greetingWords = "\(greeting),".split(separator: " ")
        let nameWords = userName.split(separator: " ")
        var headingText = Text(verbatim: "")

        for (index, word) in greetingWords.enumerated() {
            headingText = headingText
                + Text(verbatim: index == 0 ? "" : "\n")
                + Text(verbatim: String(word))
                    .font(AngroveTheme.Typography.titleHome)
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .customAttribute(SettingsRevealWord(index: index))
        }

        for (index, word) in nameWords.enumerated() {
            headingText = headingText
                + Text(verbatim: index == 0 ? "\n" : " ")
                + Text(verbatim: String(word))
                    .font(.custom("LibreBaskerville-Italic", size: 40))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                    .customAttribute(SettingsRevealWord(index: greetingWords.count + index))
        }

        let fullTitle = ([String](greetingWords.map(String.init)) + nameWords.map(String.init)).joined(separator: " ")
        return SettingsAnimatedHeading(
            text: headingText,
            wordCount: greetingWords.count + nameWords.count,
            accessibilityLabel: fullTitle,
            visibilityThreshold: 0.01
        )
        .multilineTextAlignment(.leading)
        .lineSpacing(0)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .center, spacing: usesLandscapeLayout ? 36 : 84) {
            VStack(alignment: .center, spacing: 48) {
                if !hidesGreetingHeader {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsAnimatedHeading(
                            title: HomeDashboardContent.todayString(),
                            font: AngroveTheme.Typography.uiLabel,
                            color: AngroveTheme.Colors.lightGreen,
                            visibilityThreshold: 0.01,
                            revealsOnAppear: true
                        )

                        animatedGreetingHeading
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HomeFigmaUsageAndStats(
                    month: month,
                    conversationCount: conversationCount,
                    insightCount: insightCount,
                    studyTopicCount: studyTopicCount,
                    unfinishedCount: unfinishedCount
                )

                HomeModelDownloadCard(delivery: modelDelivery)

                if let listeningWork {
                    LibraryListeningCard(work: listeningWork, onListen: {
                        LibraryListeningActions.toggle(listeningWork) { request in
                            NotificationCenter.default.post(name: .openGroundingSourceInLibrary, object: request)
                        }
                    }) { onOpenListeningWork(listeningWork) }
                        .id(listeningWork.id)
                        .transition(.blurFade)
                }
            }

            if let questionOfTheDay, !usesLandscapeLayout {
                HomeFigmaQuestionCard(
                    question: questionOfTheDay.question,
                    action: { onStartQuestion(questionOfTheDay) }
                )
                .transition(.blurFade)
            }

            if let questionOfTheDay, usesLandscapeLayout {
                HomeFigmaQuestionCard(
                    question: questionOfTheDay.question,
                    action: { onStartQuestion(questionOfTheDay) }
                )
                .frame(maxWidth: 520)
                .transition(.blurFade)
            }
        }
    }
}

/// Download progress appears immediately beneath the calendar, before other Home cards.
private struct HomeModelDownloadCard: View {
    let delivery: ModelDeliveryState

    var body: some View {
        switch delivery.phase {
        case .waiting, .downloading, .paused, .verifying:
            SettingsControlCard {
                ModelDownloadStatusView(delivery: delivery)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
            )
            .accessibilityIdentifier("home-model-download-card")
        default:
            EmptyView()
        }
    }
}

/// The streak calendar's frame, used to place the left vine below it.
private struct HomeCalendarBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct HomeFigmaUsageAndStats: View {
    let month: MonthlyUsageMonth
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 24))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 24))
        layout {
            HomeFigmaUsageGrid(month: month)
                .anchorPreference(key: HomeCalendarBoundsKey.self, value: .bounds) { $0 }

            HomeFigmaStatsGrid(
                conversationCount: conversationCount,
                insightCount: insightCount,
                studyTopicCount: studyTopicCount,
                unfinishedCount: unfinishedCount
            )
            .frame(maxWidth: .infinity)
        }
    }
}


private struct HomeFigmaResumeSection: View {
    let conversation: InquiryConversation
    let latestText: String
    let insights: [ConceptDefinition]
    var onSelectConversation: (InquiryConversation) -> Void
    var onOpenInsight: (ConceptDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Where You Left Off")

            OpenConversationCard(
                conversation: conversation,
                isActive: true,
                latestAnswer: latestText,
                insights: insights,
                onSelect: { onSelectConversation(conversation) },
                onOpenInsight: onOpenInsight
            )
        }
    }
}

private struct HomeFigmaReadingSection: View {
    let works: [RecommendedWork]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Read Material")

            VStack(alignment: .leading, spacing: 24) {
                ForEach(works, id: \.title) { work in
                    Button {
                        NotificationCenter.default.post(
                            name: .openGroundingSourceInLibrary,
                            object: LibraryNavigationRequest(
                                sourceTitle: work.title,
                                sourceName: work.sourceName
                            )
                        )
                    } label: {
                        HomeFigmaReadingRow(work: work)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


private struct HomeStartHereSection: View {
    var isPageVisible: Bool
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Getting Started with Angrove")
                    .font(AngroveTheme.Typography.illustratedCardHeading)
                    .foregroundStyle(AngroveTheme.Colors.illustratedCardTitle)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 84, alignment: .topLeading)

                Text("See User Guide")
                    .font(AngroveTheme.Typography.uiSubheading)
                    .foregroundStyle(AngroveTheme.Colors.canvas)
                    .frame(minHeight: 28)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AngroveTheme.Colors.lightGreen, in: Capsule())
            }
            .multilineTextAlignment(.leading)
            .padding(AngroveTheme.Spacing.illustratedCardPadding)
            .frame(maxWidth: .infinity, minHeight: 327, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                LibraryPaintedArtwork(image: UIImage(named: "HomeUserStart"), isPageVisible: isPageVisible)
            }
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Getting Started with Angrove. See User Guide")
        .accessibilityHint("Opens the User Guide")
    }
}
