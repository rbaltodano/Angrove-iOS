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
    var onRefresh: () -> Void = {}
    var onLoadHomeSections: () async -> Void = {}
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Landscape has ample horizontal room but a much shorter reading lane. This lets the
    /// dashboard use the extra width while releasing vertical pressure on a phone.
    private var usesLandscapeLayout: Bool { verticalSizeClass == .compact }

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
        return trimmedName.isEmpty ? "Ryan" : trimmedName
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
                            onStartQuestion: onStartQuestion
                        )

                        HomeFigmaDivider()

                        HomeFigmaResumeSection(
                            conversation: featuredConversation,
                            latestText: featuredConversation.map(HomeDashboardContent.latestText) ?? "",
                            insights: featuredConversation.map {
                                HomeDashboardContent.insights(for: $0, savedInsights: savedInsights)
                            } ?? [],
                            onSelectConversation: onSelectConversation,
                            onOpenInsight: { activeInsight = $0 }
                        )

                        HomeFigmaDivider()

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
                    HomeVineWind(parallax: vineParallax)
                        .padding(.top, usesLandscapeLayout ? 48 : 72)
                }
                // Hang the left vine 132 points below the streak calendar, behind the page.
                .backgroundPreferenceValue(HomeCalendarBoundsKey.self) { anchor in
                    if let anchor, !usesLandscapeLayout {
                        GeometryReader { proxy in
                            HomeVineWind(side: .left, parallax: vineParallax, depth: 0.22, delay: 0.15, returnDelay: 0.05)
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
            MonthlyUsageStore.recordVisitIfNeeded()
            usageMonth = MonthlyUsageStore.currentMonth()
            studyTopics = StudyTopicStore.load()
            readingWorks = RecommendedReading.works(for: regularConversations)
            if shownSections == nil { shownSections = liveSections }
            loadHomeSections()
        }
        .onChange(of: liveSections) { revealNewSections() }
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

private struct HomeFigmaOpeningSection: View {
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

    var body: some View {
        VStack(alignment: .center, spacing: usesLandscapeLayout ? 36 : 84) {
            VStack(alignment: .center, spacing: 48) {
                if !hidesGreetingHeader {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HomeDashboardContent.todayString())
                            .font(AngroveTheme.Typography.uiLabel)
                            .foregroundColor(AngroveTheme.Colors.lightGreen)

                        VStack(alignment: .leading, spacing: 0) {
                            // One word per line ("Good" / "Morning," / name), so even
                            // "Afternoon," keeps the full 40pt on a 402pt phone.
                            ForEach(Array("\(greeting),".split(separator: " ").enumerated()), id: \.offset) { _, word in
                                Text(word)
                                    .font(AngroveTheme.Typography.titleHome)
                            }

                            Text(userName)
                                .font(.custom("LibreBaskerville-Italic", size: 40))
                        }
                        .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }

                HomeFigmaUsageAndStats(
                    month: month,
                    conversationCount: conversationCount,
                    insightCount: insightCount,
                    studyTopicCount: studyTopicCount,
                    unfinishedCount: unfinishedCount
                )
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

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
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

private struct HomeFigmaQuestionCard: View {
    let question: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QUESTION OF THE DAY:")
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundColor(AngroveTheme.Colors.lightGreen)

                Text("\"\(question)\"")
                    .font(.custom("LibreBaskerville-Regular", size: 18))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .lineSpacing(7)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeFigmaResumeSection: View {
    let conversation: InquiryConversation?
    let latestText: String
    let insights: [ConceptDefinition]
    var onSelectConversation: (InquiryConversation) -> Void
    var onOpenInsight: (ConceptDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Where You Left Off")

            if let conversation {
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

private struct HomeInsightBridgeSection: View {
    let suggestion: HomeInsightBridgeSuggestion
    var onOpenInsight: (ConceptDefinition) -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Midpoint to Explore")

            VStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A Bridge Between Ideas")
                        .font(AngroveTheme.Typography.uiHeading)
                        .foregroundColor(AngroveTheme.Colors.primaryReadable)

                    Text("These insights might be worth connecting in your Insight Tree. Who knows what you'll learn")
                        .paragraphFont()
                        .foregroundColor(AngroveTheme.Colors.paragraphText)
                        .lineSpacing(7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HomeInsightBridgeDiagram(
                    firstTitle: suggestion.first.word,
                    secondTitle: suggestion.second.word,
                    onTapFirst: { onOpenInsight(suggestion.first) },
                    onTapSecond: { onOpenInsight(suggestion.second) }
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onTapGesture(perform: onOpen)
        }
    }
}

private struct HomeInsightBridgeDiagram: View {
    let firstTitle: String
    let secondTitle: String
    var onTapFirst: () -> Void
    var onTapSecond: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HomeInsightBridgeLabel(title: firstTitle, action: onTapFirst)
                .frame(maxWidth: .infinity, alignment: .trailing)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 18, y: 64))
                    path.addLine(to: CGPoint(x: 112, y: 8))
                }
                .stroke(
                    AngroveTheme.Colors.lightGreen.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3])
                )
            }
            .frame(width: 130, height: 64)

            HomeInsightBridgeLabel(title: secondTitle, action: onTapSecond)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 200, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HomeInsightBridgeLabel: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                    .frame(width: 14, height: 14)

                Text(title)
                    .font(AngroveTheme.Typography.uiSubheading)
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeLooseThreadSection: View {
    let card: LooseThreadCard
    var onOpen: () -> Void

    private var looseThreadDescription: String {
        switch card.insightCount {
        case 0:
            "You explored this subject, but nothing else in your tree has connected to it yet."
        case 1:
            "One Insight lives here, but it hasn't connected to anything else in your tree yet."
        default:
            "\(card.insightCount) Insights live here, but nothing has connected to them yet."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Loose Thread")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.nodeLabel)
                        .font(AngroveTheme.Typography.uiHeading)
                        .foregroundColor(AngroveTheme.Colors.primaryReadable)

                    Text(looseThreadDescription)
                    .paragraphFont()
                    .foregroundColor(AngroveTheme.Colors.paragraphText)
                    .lineSpacing(7)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AngroveTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeTodayInHistorySection: View {
    let card: TodayInHistoryCard
    var onStartConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY IN HISTORY")
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundColor(AngroveTheme.Colors.lightGreen)

                Text(card.title)
                    .font(.custom("LibreBaskerville-Regular", size: 40))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
            }

            Text(card.description)
                .paragraphFont()
                .foregroundColor(AngroveTheme.Colors.paragraphText)
                .lineSpacing(7)

            Button(action: onStartConversation) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12, weight: .bold))

                    Text("Tell me more...")
                        .paragraphFont()
                        .fontWeight(.bold)
                }
                .foregroundColor(AngroveTheme.Colors.canvas)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(AngroveTheme.Colors.lightGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeGlossedTermSection: View {
    let card: GlossedTermCard
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Terms You Glossed Over")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(AngroveTheme.Typography.uiHeading)
                        .foregroundColor(AngroveTheme.Colors.primaryReadable)

                    Text(card.definition)
                        .paragraphFont()
                        .foregroundColor(AngroveTheme.Colors.paragraphText)
                        .lineSpacing(7)
                        .lineLimit(3)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AngroveTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeYourQuoteSection: View {
    let card: YourQuoteCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUOTE FROM YOU")
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundColor(AngroveTheme.Colors.lightGreen)

            Text("\"\(card.quoteText)\"")
                .font(.custom("LibreBaskerville-Regular", size: 18))
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                .lineSpacing(7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private typealias HomeFigmaSectionTitle = AngroveSectionTitle
private typealias HomeFigmaDivider = AngroveSectionDivider

private struct HomeFigmaUsageGrid: View {
    let month: MonthlyUsageMonth

    private let columns = Array(repeating: GridItem(.fixed(16), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(month.days) { day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.isPlaceholder ? AngroveTheme.Colors.canvas : figmaUsageColor(for: day.level))
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(day.isPlaceholder ? Color.clear : AngroveTheme.Colors.controlBorder, lineWidth: 1)
                    )
                    .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
    }

    private func accessibilityLabel(for day: MonthlyUsageDay) -> String {
        guard !day.isPlaceholder, let dayNumber = day.dayNumber else {
            return "Empty calendar cell"
        }

        return "Day \(dayNumber), \(day.count) sessions"
    }
}

private struct HomeFigmaStatsGrid: View {
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            HomeFigmaStat(value: conversationCount, label: "Conversations")
            HomeFigmaStat(value: insightCount, label: "Insights")
            HomeFigmaStat(value: studyTopicCount, label: "Topics")
            HomeFigmaStat(value: unfinishedCount, label: "Open")
        }
    }
}

private struct HomeFigmaStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(AngroveTheme.Typography.uiHeading)
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                .monospacedDigit()

            Text(label)
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: 49)
        .frame(maxWidth: .infinity)
    }
}

private struct HomeFigmaReadingRow: View {
    let work: RecommendedWork

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("§")
                .font(.custom("LibreBaskerville-Regular", size: 28))
                .foregroundColor(AngroveTheme.Colors.accentRed)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 0) {
                Text(work.title)
                    .font(AngroveTheme.Typography.uiHeading)
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)

                Text(work.reason)
                    .paragraphFont()
                    .foregroundColor(AngroveTheme.Colors.placeholderText)
                    .lineSpacing(7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func figmaUsageColor(for level: Int) -> Color {
    switch level {
    case 1:
        return AngroveTheme.Colors.lightGreen.opacity(0.32)
    case 2:
        return AngroveTheme.Colors.lightGreen.opacity(0.55)
    case 3:
        return AngroveTheme.Colors.lightGreen.opacity(0.78)
    case 4:
        return AngroveTheme.Colors.lightGreen
    default:
        return AngroveTheme.Colors.canvasSecondary
    }
}

/// The Home sections that appear and disappear as content is generated.
private struct HomeLiveSections: Equatable {
    var question: HomeQuestionOfTheDay?
    var today: TodayInHistoryCard?
    var loose: LooseThreadCard?
    var glossed: GlossedTermCard?
    var quote: YourQuoteCard?
    var bridge: HomeInsightBridgeSuggestion?
}

// MARK: - Dashboard Content

private nonisolated struct HomeInsightBridgeSuggestion: Sendable, Equatable {
    let first: ConceptDefinition
    let second: ConceptDefinition
    let distance: Double
}

private enum HomeDashboardContent {
    nonisolated private static let dailyQuestions: [String] = [
        "What does it mean for knowledge to become wisdom?",
        "Where does faith seek understanding in your current study?",
        "Which distinction would clarify the question you keep circling?",
        "What would change if this doctrine became a habit of attention?",
        "Where is your inquiry asking for patience rather than speed?",
        "What is the strongest objection worth taking seriously today?",
        "Which saved insight belongs in conversation with another?"
    ]

    nonisolated static func greeting(date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    nonisolated static func todayString(date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    nonisolated static func questionOfTheDay(date: Date = Date()) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return dailyQuestions[(day - 1) % dailyQuestions.count]
    }

    nonisolated static func bridgeSuggestion(from insights: [ConceptDefinition]) -> HomeInsightBridgeSuggestion? {
        let embeddedInsights = insights.compactMap { insight -> (ConceptDefinition, [Double])? in
            let title = insight.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = insight.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !definition.isEmpty else { return nil }
            guard let embedding = computeEmbedding(for: "\(title). \(definition)") else { return nil }
            return (insight, embedding)
        }

        guard embeddedInsights.count >= 2 else { return nil }

        var bestSuggestion: HomeInsightBridgeSuggestion?
        for leftIndex in embeddedInsights.indices {
            for rightIndex in embeddedInsights.indices where rightIndex > leftIndex {
                let distance = semanticDistance(
                    embeddedInsights[leftIndex].1,
                    embeddedInsights[rightIndex].1
                )
                if bestSuggestion == nil || distance > (bestSuggestion?.distance ?? 0) {
                    bestSuggestion = HomeInsightBridgeSuggestion(
                        first: embeddedInsights[leftIndex].0,
                        second: embeddedInsights[rightIndex].0,
                        distance: distance
                    )
                }
            }
        }

        return bestSuggestion
    }

    nonisolated static func latestText(in conversation: InquiryConversation) -> String {
        for branch in conversation.branches.reversed() {
            for block in branch.activeChatBlocks.reversed() {
                switch block {
                case .text(let answer):
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                case .user(let question, _, _):
                    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }

            let bottom = branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bottom.isEmpty { return bottom }

            let top = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !top.isEmpty { return top }
        }

        return "Start a new line of inquiry."
    }

    nonisolated static func isUnfinished(_ conversation: InquiryConversation) -> Bool {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == "New Conversation" {
            return true
        }

        for branch in conversation.branches {
            let hasDraft = !branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (!branch.topQuestionSubmitted && !branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if hasDraft { return true }

            if let last = branch.activeChatBlocks.last,
               case .user = last {
                return true
            }
        }

        return false
    }

    nonisolated static func insights(for conversation: InquiryConversation, savedInsights: [ConceptDefinition]) -> [ConceptDefinition] {
        // Only surface insights actually saved *within* this conversation — i.e. concepts
        // embedded in its branches — not every saved insight whose word happens to appear
        // somewhere in the conversation text.
        let conceptWords = Set(embeddedConcepts(in: conversation).map { $0.word.lowercased() })

        return savedInsights
            .filter { conceptWords.contains($0.word.lowercased()) }
            .uniquedByWordLocally()
    }

    nonisolated private static func embeddedConcepts(in conversation: InquiryConversation) -> [ConceptDefinition] {
        var concepts: [ConceptDefinition] = []

        for branch in conversation.branches {
            concepts.append(contentsOf: [
                branch.startingConcept,
                branch.attachedConcept,
                branch.branchContextConcept
            ].compactMap { $0 })

            for block in branch.activeChatBlocks {
                if case .user(_, let concept?, _) = block {
                    concepts.append(concept)
                }
            }
        }

        return concepts
    }

}

nonisolated private extension Array where Element == ConceptDefinition {
    func uniquedByWordLocally() -> [ConceptDefinition] {
        var seenWords = Set<String>()
        var uniqueInsights: [ConceptDefinition] = []

        for insight in self {
            let key = insight.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seenWords.contains(key) else { continue }
            seenWords.insert(key)
            uniqueInsights.append(insight)
        }

        return uniqueInsights
    }
}

// MARK: - Monthly Usage

private struct MonthlyUsageMonth: Equatable {
    let title: String
    let totalVisits: Int
    let days: [MonthlyUsageDay]
}

private struct MonthlyUsageDay: Identifiable, Equatable {
    let id: String
    let dayNumber: Int?
    let count: Int

    var isPlaceholder: Bool {
        dayNumber == nil
    }

    var level: Int {
        switch count {
        case 0:
            return 0
        case 1:
            return 1
        case 2:
            return 2
        case 3...4:
            return 3
        default:
            return 4
        }
    }
}

private enum MonthlyUsageStore {
    private static let countsKey = "aquinas.home.monthly-usage.counts.v1"
    private static let lastRecordedAtKey = "aquinas.home.monthly-usage.last-recorded-at.v1"
    private static let minimumRecordInterval: TimeInterval = 30 * 60

    static func recordVisitIfNeeded(date: Date = Date()) {
        let defaults = PrivatePreferences.standard
        if let lastRecordedAt = defaults.object(forKey: lastRecordedAtKey) as? Date,
           date.timeIntervalSince(lastRecordedAt) < minimumRecordInterval {
            return
        }

        var counts = loadCounts()
        let key = dayKey(for: date)
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: countsKey)
        defaults.set(date, forKey: lastRecordedAtKey)
    }

    static func currentMonth(date: Date = Date()) -> MonthlyUsageMonth {
        let calendar = Calendar.current
        let counts = loadCounts()
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstDay = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay) else {
            return MonthlyUsageMonth(title: "", totalVisits: 0, days: [])
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingPlaceholderCount = max(0, firstWeekday - calendar.firstWeekday)
        var days: [MonthlyUsageDay] = (0..<leadingPlaceholderCount).map { index in
            MonthlyUsageDay(id: "placeholder-\(index)", dayNumber: nil, count: 0)
        }

        for dayNumber in dayRange {
            guard let dayDate = calendar.date(byAdding: .day, value: dayNumber - 1, to: firstDay) else {
                continue
            }
            let key = dayKey(for: dayDate)
            days.append(MonthlyUsageDay(id: key, dayNumber: dayNumber, count: counts[key, default: 0]))
        }

        return MonthlyUsageMonth(
            title: date.formatted(.dateTime.month(.wide).year()),
            totalVisits: days.reduce(0) { $0 + $1.count },
            days: days
        )
    }

    private static func loadCounts() -> [String: Int] {
        PrivatePreferences.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
