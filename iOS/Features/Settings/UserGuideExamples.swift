//
//  UserGuideExamples.swift
//  Angrove-iOS
//

import SwiftUI

/// Hands-on examples for the User Guide. Each one reuses the real component the feature uses, so
/// the example changes with the design. Content is written ahead of time: examples never call the
/// model.
enum UserGuideExample {
    case definitions
    case tree
    case study
    case midpoint
    case modelTasks
}

/// Places an example with its one-line instruction.
struct UserGuideExampleView: View {
    let example: UserGuideExample
    @Binding var collectedDefinitions: [ConceptDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try It")
                .font(AngroveTheme.Typography.settingsHeading)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)

            switch example {
            case .definitions:
                UserGuideDefinitionsExample(collectedDefinitions: $collectedDefinitions)
            case .tree:
                UserGuideTreeExample(collectedDefinitions: collectedDefinitions)
            case .study:
                UserGuideStudyExample(collectedDefinitions: collectedDefinitions)
            case .midpoint:
                UserGuideMidpointExample(collectedDefinitions: collectedDefinitions)
            case .modelTasks:
                UserGuideModelTasksExample()
            }
        }
    }
}

private struct UserGuideExampleCaption: View {
    /// Guide markup; see `UserGuideText`.
    let text: String

    var body: some View {
        UserGuideText.text(text)
            .settingsText(.paragraph)
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .lineSpacing(FlowLayout.rowSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Definitions

/// A short answer with two underlined terms. Tapping one opens the real definition card, and
/// saving it adds it to the user's Insight Library like any other save.
private struct UserGuideDefinitionsExample: View {
    @Binding var collectedDefinitions: [ConceptDefinition]
    @State private var activeConcept: ConceptDefinition?
    /// The reveal is held until the page has finished sliding in, so it isn't missed.
    @State private var hasStartedReveal = false
    // The same reading settings a conversation uses, so the example text matches a real answer.
    @AppStorage("aquinas.settings.conversationFontSize") private var conversationFontSize: ConversationFontSizeOption = .medium
    @AppStorage(SettingsStorageKey.conversationTextAlignment) private var conversationTextAlignment: ConversationTextAlignmentOption = .left
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif

    private static let passage = """
    Aristotle’s whole picture of reality is teleological: everything has a telos, an end built \
    into its nature, and things are understood by grasping what they are for. An acorn’s telos \
    is to become an oak; an eye’s is to see. [Eudaimonia](aq://eudaimonia) is the same idea \
    applied to a human life as a whole. If everything has a proper end, what is the proper end \
    of a person? Ethics, for Aristotle, is a branch of his [natural philosophy](aq://natural-philosophy).
    """

    private static let concepts: [String: ConceptDefinition] = [
        "eudaimonia": concept(
            "Eudaimonia",
            meaning: "Flourishing: the complete, well-lived human life that Aristotle held every action ultimately aims at. Not a feeling of happiness, but a life lived well over its whole length.",
            context: "Aristotle on the good life"
        ),
        "natural philosophy": concept(
            "Natural philosophy",
            meaning: "The study of nature and how things change, understood through their causes and ends. Aristotle’s ethics builds on this account of human nature to ask what it means for a person to live well.",
            context: "Aristotle’s ethics and nature"
        ),
    ]

    private static func concept(_ word: String, meaning: String, context: String) -> ConceptDefinition {
        ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: word),
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: meaning,
            example: "",
            context: context
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: "Tap an underlined word to open its definition, then tap {bookmark|Save} to add it to your Insights.")

            StreamingMessageView(
                fullText: Self.passage,
                // Reveals word by word, exactly as a finished answer appears in a conversation.
                // Before the reveal starts, the full text lays out invisibly to hold the space.
                shouldStream: hasStartedReveal,
                responseTextAlignment: conversationTextAlignment,
                responseFont: responseFont,
                conversationFontSize: conversationFontSize,
                savedInsightIDs: Set(collectedDefinitions.map(\.id)),
                showsResponseActions: false,
                onInsightTap: { title, _ in
                    activeConcept = Self.concepts[title.lowercased()]
                }
            )
            .id(hasStartedReveal)
            .opacity(hasStartedReveal ? 1 : 0)
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            hasStartedReveal = true
        }
        .sheet(item: $activeConcept) { concept in
            ConceptSheetContent(concept: concept, collectedDefinitions: $collectedDefinitions)
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AngroveTheme.Colors.canvas)
        }
    }
}

// MARK: - Greek Philosophy tree

/// The Node Concept the Insight Tree, Study, and Midpoint examples share: Cynicism and
/// Epicureanism are already in place, and Insights saved in the Definitions example join them.
private enum UserGuideGreekTree {
    static let conversationID = UUID(uuidString: "6F1C2A9E-2D0B-4B8E-9C7A-1E5F3A0B7C31")!
    static let nodeID = UUID(uuidString: "C1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C01")!

    private static let cynicism = insight(
        "Cynicism",
        "The ancient school that held virtue alone is enough for a good life, and that conventions, wealth, and comfort only get in its way.",
        "C1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C02"
    )
    private static let epicureanism = insight(
        "Epicureanism",
        "The school that taught the good life is found in lasting pleasure, chiefly peace of mind and freedom from fear and pain.",
        "C1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C03"
    )

    private static func insight(_ title: String, _ definition: String, _ id: String) -> InsightModel {
        InsightModel(id: UUID(uuidString: id)!, title: title, definition: definition, conversationID: conversationID)
    }

    /// Saved Insights come first, then Cynicism and Epicureanism, as on the website.
    static func insights(collected: [ConceptDefinition]) -> [InsightModel] {
        let saved = collected
            .filter { ["Eudaimonia", "Natural philosophy"].contains($0.word) }
            .map { InsightModel(id: $0.id, title: $0.word, definition: $0.meaning, conversationID: conversationID) }
        return saved + [cynicism, epicureanism]
    }

    static func node(collected: [ConceptDefinition]) -> NodeModel {
        let members = insights(collected: collected)
        // Example Insights aren't new discoveries, so they carry no "new" dot.
        let ids = Set(members.map(\.id))
        InsightDiscoveryStore.saveSeenInsightIDs(Array(InsightDiscoveryStore.loadSeenInsightIDs().union(ids)))
        InsightDiscoveryStore.saveUndiscoveredInsightIDs(InsightDiscoveryStore.loadUndiscoveredInsightIDs().subtracting(ids))
        return NodeModel(
            id: nodeID,
            conceptLabel: "Greek Philosophy",
            definition: "The ancient Greek schools that asked how a person should live.",
            insights: members,
            embedding: [],
            position: .zero,
            isSuggested: false,
            suggestedInsights: nil
        )
    }

    /// Natural philosophy sits farther out, as on the website.
    static func bondLengths(for node: NodeModel) -> [UUID: CGFloat] {
        Dictionary(uniqueKeysWithValues: node.insights.map { ($0.id, $0.title == "Natural philosophy" ? CGFloat(195) : CGFloat(135)) })
    }
}

/// The framed canvas the tree examples sit in.
private struct UserGuideCanvasFrame<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(height: height)
            .background(AngroveTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(AngroveTheme.Colors.divider, lineWidth: 1)
            )
            .padding(.horizontal, -12)
    }
}

// MARK: - Insight Tree

/// The real tree canvas around Greek Philosophy. Insights saved in the Definitions example above
/// join it.
private struct UserGuideTreeExample: View {
    let collectedDefinitions: [ConceptDefinition]

    var body: some View {
        let node = UserGuideGreekTree.node(collected: collectedDefinitions)
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: "Any Insights you saved in the example above join this tree, which starts with Cynicism and Epicureanism.")

            UserGuideCanvasFrame(height: 460) {
                InsightTreeCanvasView(
                    nodes: [node],
                    edges: [],
                    restoreFocusedCameraRequest: 0,
                    focusedInsightID: nil,
                    focusedSearchNodeID: nil,
                    pulsingInsightID: nil,
                    pulsingNodeID: nil,
                    selectedCanvasTargets: [],
                    selectionPulseRequest: 0,
                    insightBondLengths: UserGuideGreekTree.bondLengths(for: node),
                    onNodeTapped: { _ in },
                    onInsightTapped: { _ in },
                    onCanvasMoved: {},
                    onSuggestConnection: { _ in },
                    onDismissSuggestedNode: { _ in }
                )
            }
        }
    }
}

// MARK: - Study

/// The same Greek Philosophy tree. The canvas starts Study when `studyNodeID` changes, so the
/// example shows the tree briefly and then moves into Study.
private struct UserGuideStudyExample: View {
    let collectedDefinitions: [ConceptDefinition]
    @State private var studyNodeID: UUID?

    var body: some View {
        let node = UserGuideGreekTree.node(collected: collectedDefinitions)
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: "Drag to spin the concept and its Insights.")

            UserGuideCanvasFrame(height: 460) {
                GeometryReader { proxy in
                    InsightTreeCanvasView(
                        nodes: [node],
                        edges: [],
                        restoreFocusedCameraRequest: 0,
                        focusedInsightID: nil,
                        focusedSearchNodeID: nil,
                        pulsingInsightID: nil,
                        pulsingNodeID: nil,
                        selectedCanvasTargets: [],
                        selectionPulseRequest: 0,
                        insightBondLengths: UserGuideGreekTree.bondLengths(for: node),
                        onNodeTapped: { _ in },
                        onInsightTapped: { _ in },
                        onCanvasMoved: {},
                        onSuggestConnection: { _ in },
                        onDismissSuggestedNode: { _ in },
                        studyNodeID: studyNodeID,
                        // The ring and the node's zoom both scale from this slot. The real view uses
                        // 300 × 300 on a full screen; 240 keeps every Insight inside this frame.
                        studySlot: CGRect(
                            x: (proxy.size.width - 240) / 2,
                            y: 50,
                            width: 240,
                            height: 240
                        )
                    )
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(900))
                    studyNodeID = UserGuideGreekTree.nodeID
                }
            }
        }
    }
}

// MARK: - Midpoint

/// The real tree canvas with the Greek Philosophy cluster and a second Node Concept, Virtue. The
/// example opens by itself: one Greek Insight is selected, the camera moves across to Virtue, an
/// Insight there is selected, and Midpoint opens between the two. The real feature asks the model
/// for a concept; here the result is written ahead of time.
private struct UserGuideMidpointExample: View {
    let collectedDefinitions: [ConceptDefinition]

    private enum Phase { case idle, thinking, done }

    @State private var selected: [CanvasSelectionTarget] = []
    @State private var isMidpointMode = false
    @State private var weights: [Double] = []
    @State private var targetIndex = 0
    @State private var targetWeight = 0.5
    @State private var percentRequest = 0
    @State private var centerRequest = 0
    @State private var selectionPulse = 0
    @State private var canvasID = UUID()
    @State private var isSelecting = false
    @State private var isScripted = true
    @State private var phase: Phase = .idle
    @State private var focusedInsightID: UUID?
    @State private var dockedInsight: InsightModel?
    @State private var scriptStarted = false

    private static let virtueConversationID = UUID(uuidString: "6F1C2A9E-2D0B-4B8E-9C7A-1E5F3A0B7C21")!
    private static let virtueNode = NodeModel(
        id: UUID(uuidString: "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C01")!,
        conceptLabel: "Virtue",
        definition: "A good habit of mind or will that disposes a person to act well.",
        insights: [
            virtueInsight("Justice", "The constant will to give each person what is owed.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C02"),
            virtueInsight("Mercy", "Compassion for another's distress that moves us to relieve it, giving more than is owed.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C03"),
            virtueInsight("Prudence", "Practical wisdom that judges what the good requires here and now.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C04"),
            virtueInsight("Courage", "Firmness of mind in facing danger or hardship for the sake of the good.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C05"),
        ],
        embedding: [],
        position: CGPoint(x: 520, y: -380),
        isSuggested: false,
        suggestedInsights: nil
    )

    private static func virtueInsight(_ title: String, _ definition: String, _ id: String) -> InsightModel {
        InsightModel(id: UUID(uuidString: id)!, title: title, definition: definition, conversationID: virtueConversationID)
    }

    private var greekNode: NodeModel { UserGuideGreekTree.node(collected: collectedDefinitions) }
    private var nodes: [NodeModel] { [greekNode, Self.virtueNode] }
    private var allInsights: [InsightModel] { nodes.flatMap(\.insights) }
    private var prudence: InsightModel { Self.virtueNode.insights[2] }

    /// Three example results per pair, picked by the balance: leaning toward the first Insight,
    /// near the middle, or leaning toward the second (60% or more counts as leaning).
    private static let results: [String: [(String, String)]] = [
        "Justice|Mercy": [
            ("Restorative Justice", "Giving what is owed in a way that aims to heal the wrong and restore the offender, not only to punish."),
            ("Equity", "Applying a just rule with mercy when its strict letter would defeat its purpose in a particular case."),
            ("Forgiveness", "Freely releasing a debt one could justly claim, while still naming the wrong as a wrong."),
        ],
        "Cynicism|Prudence": [
            ("Ascetic Freedom", "Living deliberately with little, so that nothing outside oneself can compel one’s choices."),
            ("Temperance", "Moderating desire by reason: taking what is needed and refusing what would come to rule over you."),
            ("Prudent Simplicity", "Choosing a plain life because careful judgment sees what actually serves the good."),
        ],
        "Epicureanism|Prudence": [
            ("Tranquility", "The settled peace of mind that comes from wanting little and fearing nothing."),
            ("Moderation of Pleasure", "Choosing the pleasures that last and refusing those that bring later pain."),
            ("Wise Enjoyment", "Judging which pleasures serve a good life, and when to take them."),
        ],
        "Eudaimonia|Prudence": [
            ("Happiness as an End", "The end every action aims at, pursued with the judgment to know what truly leads there."),
            ("Right Reason in Action", "Acting according to reason so that a life moves steadily toward its proper end."),
            ("Deliberation", "Weighing the means to a good end carefully before choosing how to act."),
        ],
        "Natural philosophy|Prudence": [
            ("Natural Order", "The pattern of ends built into things, which reason can read and then follow."),
            ("Practical Knowledge", "Understanding how things work in order to act well among them."),
            ("Prudent Inquiry", "Studying the world with an eye to what a good life asks of us."),
        ],
    ]

    private func concept(for target: CanvasSelectionTarget) -> ConceptDefinition? {
        switch target {
        case .insight(let id):
            guard let insight = allInsights.first(where: { $0.id == id }) else { return nil }
            return ConceptDefinition(id: insight.id, word: insight.title, partOfSpeech: "",
                                     pronunciation: "", meaning: insight.definition, example: "")
        case .node(let id):
            guard let node = nodes.first(where: { $0.id == id }) else { return nil }
            return ConceptDefinition(id: node.id, word: node.conceptLabel, partOfSpeech: "",
                                     pronunciation: "", meaning: node.definition, example: "")
        }
    }

    private var concepts: [ConceptDefinition] { selected.compactMap(concept(for:)) }

    private var result: (title: String, definition: String) {
        let names = concepts.map(\.word)
        let share = weights.first ?? 0.5
        let tier = share >= 0.6 ? 0 : share <= 0.4 ? 2 : 1
        if names.count == 2 {
            if let set = Self.results[names[0] + "|" + names[1]] {
                return set[tier]
            }
            if let set = Self.results[names[1] + "|" + names[0]] {
                return set[2 - tier]
            }
        }
        return ("A new concept", "In the app, Angrove proposes a concept that sits between \(names.joined(separator: ", ")), leaning toward the ideas you weight most.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: "Watch it select an Insight from the Greek Philosophy tree and one from a new Node Concept, then open Midpoint. Drag on the tree, or use the percentages, to shift the balance. To try your own, tap Reset, then Select, choose two Insights, and tap Midpoint.")

            canvas
                .frame(height: 620)
                .background(AngroveTheme.Colors.canvas)
                .overlay(alignment: .bottom) {
                    if let insight = dockedInsight {
                        DockedInsightTreeCard(insight: insight)
                            .id(insight.id)
                            .transition(.bottomDockCard)
                            .padding(.horizontal, 10)
                            .padding(.bottom, Self.dockBottomInset)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(AngroveTheme.Colors.divider, lineWidth: 1)
                )
                .padding(.horizontal, -12)

            if isMidpointMode && phase == .idle {
                MidpointPercentCard(
                    concepts: concepts,
                    weights: weights,
                    onSetPercent: { index, percent in
                        targetIndex = index
                        targetWeight = Double(min(100, max(0, percent))) / 100
                        percentRequest += 1
                    }
                )
                .transition(.opacity)
            }

            UserGuideMidpointDock(
                items: dockItems,
                isThinking: phase == .thinking
            )
            .frame(maxWidth: .infinity)
        }
        .task { await runScript() }
    }

    private var canvas: some View {
        InsightTreeCanvasView(
            nodes: nodes,
            edges: [],
            restoreFocusedCameraRequest: 0,
            focusedInsightID: focusedInsightID,
            focusedSearchNodeID: nil,
            pulsingInsightID: nil,
            pulsingNodeID: nil,
            selectedCanvasTargets: selected,
            selectionPulseRequest: selectionPulse,
            insightBondLengths: Dictionary(uniqueKeysWithValues: allInsights.map { ($0.id, CGFloat(135)) }),
            layoutTargets: [UserGuideGreekTree.nodeID: .zero, Self.virtueNode.id: Self.virtueNode.position],
            isMidpointMode: isMidpointMode,
            midpointCenterRequest: centerRequest,
            midpointTargetIndex: targetIndex,
            midpointTargetWeight: targetWeight,
            midpointPercentRequest: percentRequest,
            onMidpointWeightsChange: { weights = $0 },
            onNodeTapped: { tapped(.node($0.id)) },
            onInsightTapped: { tapped(.insight($0.id), insight: $0) },
            onCanvasMoved: {},
            onSuggestConnection: { _ in },
            onDismissSuggestedNode: { _ in }
        )
        .id(canvasID)
    }

    private static let dockBottomInset: CGFloat = 10

    // MARK: Dock

    private var dockItems: [UserGuideDockItem] {
        if isScripted {
            return [.init(id: "select", title: "Select", icon: "circle.dashed", isEnabled: false, action: {})]
        }
        if phase == .done {
            return [.init(id: "reset", title: "Reset", icon: "arrow.counterclockwise", action: reset)]
        }
        if phase == .thinking { return [] }
        if isMidpointMode {
            return [
                .init(id: "back", title: "Back", icon: "chevron.left", action: back),
                .init(id: "center", title: "Center", icon: "lines.measurement.horizontal", action: { centerRequest += 1 }),
                .init(id: "place", title: "Place", icon: "arrow.down", action: place),
            ]
        }
        var items: [UserGuideDockItem] = [
            .init(id: "select", title: isSelecting ? "Done" : "Select", icon: "circle.dashed", isActive: isSelecting) {
                isSelecting.toggle()
                dockedInsight = nil
            }
        ]
        if selected.count >= 2 {
            items.append(.init(id: "midpoint", title: "Midpoint", icon: "graph.2d") {
                isSelecting = false
                dockedInsight = nil
                isMidpointMode = true
            })
        }
        if !selected.isEmpty {
            items.append(.init(id: "reset", title: "Reset", icon: "arrow.counterclockwise", action: reset))
        }
        return items
    }

    // MARK: Actions

    private func tapped(_ target: CanvasSelectionTarget, insight: InsightModel? = nil) {
        guard !isMidpointMode, !isScripted, phase == .idle else { return }
        if isSelecting {
            toggle(target)
        } else {
            withAnimation(.springStandard) {
                dockedInsight = (insight == nil || dockedInsight?.id == insight?.id) ? nil : insight
            }
            SettingsHaptics.playSelection()
        }
    }

    private func toggle(_ target: CanvasSelectionTarget) {
        if let index = selected.firstIndex(of: target) {
            selected.remove(at: index)
        } else if selected.count < 2 {   // this example balances two
            selected.append(target)
            if selected.count > 1 { selectionPulse += 1 }
        } else {
            selected = [selected[1], target]
            selectionPulse += 1
        }
        SettingsHaptics.playSelection()
    }

    private func back() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isMidpointMode = false
            dockedInsight = nil
        }
    }

    /// The real Place asks the model for a concept; here the written-ahead result appears after the
    /// same Thinking beat, as the Insight's own card.
    private func place() {
        let placed = result
        withAnimation(.springLively) { phase = .thinking }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            let insight = InsightModel(id: UUID(), title: placed.title, definition: placed.definition, conversationID: Self.virtueConversationID)
            withAnimation(.springStandard) {
                isMidpointMode = false
                phase = .done
                dockedInsight = insight
            }
        }
    }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isMidpointMode = false
            isSelecting = false
            dockedInsight = nil
            selected = []
            weights = []
            phase = .idle
            focusedInsightID = nil
        }
        canvasID = UUID()
    }

    /// Selects one Greek Insight, moves across to Virtue, selects Prudence, and opens Midpoint.
    private func runScript() async {
        guard !scriptStarted else { return }
        scriptStarted = true
        try? await Task.sleep(for: .milliseconds(1200))
        guard let from = greekNode.insights.first else { isScripted = false; return }
        selected = [.insight(from.id)]
        selectionPulse += 1
        try? await Task.sleep(for: .milliseconds(1000))
        focusedInsightID = prudence.id
        try? await Task.sleep(for: .milliseconds(2600))
        selected = [.insight(from.id), .insight(prudence.id)]
        selectionPulse += 1
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.easeInOut(duration: 0.25)) {
            isScripted = false
            isMidpointMode = true
        }
    }
}

/// One button in the example's dock.
private struct UserGuideDockItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    var isEnabled = true
    var isActive = false
    let action: () -> Void
}

/// The example's Model Controls: one 64 pt capsule that hugs its buttons (icon and Figtree Bold 14,
/// 8 apart, 24 between), re-measured with springLively as buttons come and go.
private struct UserGuideMidpointDock: View {
    let items: [UserGuideDockItem]
    let isThinking: Bool

    var body: some View {
        HStack(spacing: 24) {
            if isThinking {
                Text("Thinking")
                    .font(.custom("Figtree-Bold", size: 14))
                    .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
                    .modifier(ThinkingShimmer(isActive: true, color: AngroveTheme.Colors.paragraphText.opacity(0.75)))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            ForEach(items) { item in
                Button {
                    SettingsHaptics.playSelection()
                    item.action()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .id("\(item.id)-\(item.title)")
                            .sfSymbolDrawOn()
                        Text(item.title)
                            .font(.custom("Figtree-Bold", size: 14))
                    }
                    .frame(height: 16, alignment: .center)
                    .foregroundColor(item.isActive ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.paragraphText.opacity(0.75))
                    .opacity(item.isEnabled ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .fixedSize(horizontal: true, vertical: true)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
        .modifier(FloatingControlPressFeedback(isButtonPressed: false))
        .animation(.springLively, value: items.map(\.id) + [isThinking ? "thinking" : ""])
    }
}


// MARK: - Model Tasks

/// The real Model Tasks card on its own practice queue. Practice tasks only wait 5–7 seconds; they
/// never touch the model, and nothing reaches the app's real queue.
private struct UserGuideModelTasksExample: View {
    @State private var queue = ModelTaskQueue()
    @State private var definedWordIndex = 0

    private static let practiceWords = ["prudence", "grace", "virtue", "charity", "habit"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            UserGuideExampleCaption(text: "Tap {stop.circle.fill|Stop} on the running task to cancel it, tap {xmark|Remove} on a waiting task to take it out of line, or press and drag a waiting task to change its place.")

            ModelTasksCard(modelTasks: queue)
                .environment(\.openModelTaskPage, { _ in })
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("Add Practice Tasks")
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .accessibilityAddTraits(.isHeader)
                UserGuideExampleCaption(text: "Tap these to add a few tasks to the card above. Add several so some are waiting in line.")
            }

            VStack(alignment: .leading, spacing: 12) {
                practiceButton("Ask a Question", icon: "paperplane.fill") {
                    .userQuestion(branchID: UUID(), responseIndex: 0)
                }
                practiceButton("Define a Word", icon: "text.bubble.fill") {
                    let word = Self.practiceWords[definedWordIndex % Self.practiceWords.count]
                    definedWordIndex += 1
                    return .defineInsight(key: "user-guide-practice-\(UUID())", name: word)
                }
                practiceButton("Create a Midpoint", icon: "graph.2d") { .createMidpoint }
                practiceButton("Update the Insight Tree", icon: "point.3.connected.trianglepath.dotted") {
                    .updateInsightTree
                }
            }
        }
        .onDisappear {
            // Leave nothing running once the reader moves on.
            queue.cancelTasks { _ in true }
        }
    }

    private func practiceButton(
        _ title: LocalizedStringResource,
        icon: String,
        kind: @escaping () -> ModelTaskKind
    ) -> some View {
        Button {
            SettingsHaptics.playSelection()
            queue.enqueue(kind: kind()) {
                try? await Task.sleep(for: .seconds(Double.random(in: 5...7)))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .settingsText(.label)
                Spacer(minLength: 8)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AngroveTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
