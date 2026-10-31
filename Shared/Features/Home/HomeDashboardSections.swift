//
//  HomeDashboardSections.swift
//  Angrove
//

import SwiftUI

// Home sections and content shared by the iPhone dashboard and the Mac Home page.

struct HomeFigmaQuestionCard: View {
    let question: String
    var surfaceColor: Color = AngroveTheme.Colors.canvasSecondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsAnimatedHeading(
                    title: "QUESTION OF THE DAY:",
                    font: AngroveTheme.Typography.uiLabel,
                    color: AngroveTheme.Colors.lightGreen
                )

                SettingsAnimatedHeading(
                    title: "“\(question)”",
                    font: .custom("LibreBaskerville-Regular", size: 18),
                    color: AngroveTheme.Colors.primaryReadable
                )
                    .lineSpacing(7)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HomeInsightBridgeSection: View {
    let suggestion: HomeInsightBridgeSuggestion
    var surfaceColor: Color = AngroveTheme.Colors.canvasSecondary
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

                    Text("These insights might be worth connecting in your Insight Tree. Who knows what you'll learn.")
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
            .background(surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onTapGesture(perform: onOpen)
            .homeCardHover()
        }
    }
}

struct HomeInsightBridgeDiagram: View {
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

struct HomeInsightBridgeLabel: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .angroveIcon(.medium)
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

struct HomeLooseThreadSection: View {
    let card: LooseThreadCard
    var surfaceColor: Color = AngroveTheme.Colors.canvasSecondary
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
                .background(surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .homeCardHover()
        }
    }
}

struct HomeTodayInHistorySection: View {
    let card: TodayInHistoryCard
    let isPageVisible: Bool
    var onStartConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsAnimatedHeading(
                    title: "TODAY IN HISTORY",
                    font: AngroveTheme.Typography.uiLabel,
                    color: AngroveTheme.Colors.lightGreen,
                    visibilityThreshold: 0.01,
                    revealsOnAppear: true,
                    isPageVisible: isPageVisible
                )

                SettingsAnimatedHeading(
                    title: card.title,
                    font: AngroveTheme.Typography.titleHome,
                    color: AngroveTheme.Colors.primaryReadable,
                    visibilityThreshold: 0.01,
                    revealsOnAppear: true,
                    isPageVisible: isPageVisible
                )
                .id(card.title)
            }
            // Display headings already start large. Keep them within the reading lane;
            // the description below continues to follow the full accessibility range.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text(card.description)
                .paragraphFont()
                .foregroundColor(AngroveTheme.Colors.paragraphText)
                .lineSpacing(7)

            Button(action: onStartConversation) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .angroveIcon(.small, .strong)

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

struct HomeGlossedTermSection: View {
    let card: GlossedTermCard
    var surfaceColor: Color = AngroveTheme.Colors.canvasSecondary
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
                .background(surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .homeCardHover()
        }
    }
}

struct HomeYourQuoteSection: View {
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

typealias HomeFigmaSectionTitle = AngroveSectionTitle
typealias HomeFigmaDivider = AngroveSectionDivider

struct HomeFigmaUsageGrid: View {
    let month: MonthlyUsageMonth
    var cellSize: CGFloat = 16

    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(cellSize), spacing: 4), count: 7) }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(month.days) { day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.isPlaceholder ? AngroveTheme.Colors.canvas : figmaUsageColor(for: day.level))
                    .frame(width: cellSize, height: cellSize)
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

struct HomeFigmaStatsGrid: View {
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                           count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
            spacing: 8
        ) {
            HomeFigmaStat(value: conversationCount, label: conversationCount == 1 ? "Conversation" : "Conversations")
            HomeFigmaStat(value: insightCount, label: insightCount == 1 ? "Insight" : "Insights")
            HomeFigmaStat(value: studyTopicCount, label: studyTopicCount == 1 ? "Topic" : "Topics")
            HomeFigmaStat(value: unfinishedCount, label: "Open")
        }
    }
}

struct HomeFigmaStat: View {
    let value: Int
    let label: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(AngroveTheme.Typography.uiHeading)
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                .monospacedDigit()

            Text(label)
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 49)
        .frame(maxWidth: .infinity)
    }
}

struct HomeFigmaReadingRow: View {
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

func figmaUsageColor(for level: Int) -> Color {
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
struct HomeLiveSections: Equatable {
    var question: HomeQuestionOfTheDay?
    var today: TodayInHistoryCard?
    var loose: LooseThreadCard?
    var glossed: GlossedTermCard?
    var quote: YourQuoteCard?
    var bridge: HomeInsightBridgeSuggestion?
}

// MARK: - Dashboard Content

nonisolated struct HomeInsightBridgeSuggestion: Sendable, Equatable {
    let first: ConceptDefinition
    let second: ConceptDefinition
    let distance: Double
}

enum HomeDashboardContent {
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

nonisolated extension Array where Element == ConceptDefinition {
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

struct MonthlyUsageMonth: Equatable {
    let title: String
    let totalVisits: Int
    let days: [MonthlyUsageDay]
}

struct MonthlyUsageDay: Identifiable, Equatable {
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

enum MonthlyUsageStore {
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


// MARK: - Card hover

extension EnvironmentValues {
    /// The Mac Home lifts a section's card under the pointer; the iPhone leaves it still.
    @Entry var homeCardsHover = false
}

/// Lifts only the card, never the section title above it.
struct HomeCardHover: ViewModifier {
    @State private var isHovered = false
    @Environment(\.homeCardsHover) private var hovers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if hovers {
            content
                .scaleEffect(isHovered && !reduceMotion ? 1.008 : 1)
                .shadow(color: AngroveTheme.Colors.floatingShadow.opacity(isHovered ? 1 : 0), radius: 18, y: 6)
                .animation(.springQuick, value: isHovered)
                .onHover { isHovered = $0 }
                #if os(macOS)
                .pointerStyle(.link)
                #endif
        } else {
            content
        }
    }
}

extension View {
    func homeCardHover() -> some View { modifier(HomeCardHover()) }
}
