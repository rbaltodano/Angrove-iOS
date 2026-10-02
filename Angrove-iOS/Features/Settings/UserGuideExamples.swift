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
    case midpoint
    case midpointThree
    case study
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
            case .midpoint:
                UserGuideMidpointExample()
            case .midpointThree:
                UserGuideMidpointExample(preselected: ["Justice", "Mercy", "Prudence"])
            case .study:
                UserGuideStudyExample()
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
            .font(AngroveTheme.Typography.settingsBody)
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
    For Aquinas, virtue is a [habit](aq://habit) that disposes us to act well, formed by \
    repeated good choices until acting well comes readily. Among the moral virtues, \
    [prudence](aq://prudence) directs the others, because it judges what the good requires here \
    and now.
    """

    private static let concepts: [String: ConceptDefinition] = [
        "habit": concept(
            "Habit",
            meaning: "A settled disposition, formed by repeated acts, that inclines a person to act in a certain way readily and with ease.",
            context: "Virtue as a stable disposition"
        ),
        "prudence": concept(
            "Prudence",
            meaning: "Practical wisdom: the virtue of judging rightly what should be done in a particular situation, which guides the exercise of the other moral virtues.",
            context: "The moral virtues"
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

// MARK: - Midpoint

/// The real tree canvas with four preset Insights. Tapping an Insight selects it, and Midpoint
/// opens the real balance controls. The real feature asks the model for a concept; here the result
/// is written ahead of time.
private struct UserGuideMidpointExample: View {
    /// Titles selected when the example appears; three of them show a multi-Insight Midpoint.
    let preselected: [String]

    @State private var selected: [CanvasSelectionTarget] = []
    @State private var isMidpointMode = false
    @State private var weights: [Double] = []
    @State private var targetIndex = 0
    @State private var targetWeight = 0.5
    @State private var percentRequest = 0
    @State private var selectionPulse = 0
    @State private var canvasID = UUID()
    @State private var isSelecting = false
    @State private var dockedInsight: InsightModel?

    private static let conversationID = UUID(uuidString: "6F1C2A9E-2D0B-4B8E-9C7A-1E5F3A0B7C21")!
    private static let node = NodeModel(
        id: UUID(uuidString: "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C01")!,
        conceptLabel: "Virtue",
        definition: "A good habit of mind or will that disposes a person to act well.",
        insights: [
            insight("Justice", "The constant will to give each person what is owed.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C02"),
            insight("Mercy", "Compassion for another's distress that moves us to relieve it, giving more than is owed.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C03"),
            insight("Prudence", "Practical wisdom that judges what the good requires here and now.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C04"),
            insight("Courage", "Firmness of mind in facing danger or hardship for the sake of the good.", "B1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C05"),
        ],
        embedding: [],
        position: .zero,
        isSuggested: false,
        suggestedInsights: nil
    )

    private static func insight(_ title: String, _ definition: String, _ id: String) -> InsightModel {
        InsightModel(id: UUID(uuidString: id)!, title: title, definition: definition, conversationID: conversationID)
    }

    init(preselected: [String] = []) {
        self.preselected = preselected
        let exampleIDs = Set(Self.node.insights.map(\.id))
        InsightDiscoveryStore.saveSeenInsightIDs(
            Array(InsightDiscoveryStore.loadSeenInsightIDs().union(exampleIDs))
        )
        InsightDiscoveryStore.saveUndiscoveredInsightIDs(
            InsightDiscoveryStore.loadUndiscoveredInsightIDs().subtracting(exampleIDs)
        )
    }

    private func concept(for target: CanvasSelectionTarget) -> ConceptDefinition? {
        switch target {
        case .insight(let id):
            guard let insight = Self.node.insights.first(where: { $0.id == id }) else { return nil }
            return ConceptDefinition(id: insight.id, word: insight.title, partOfSpeech: "",
                                     pronunciation: "", meaning: insight.definition, example: "")
        case .node:
            return ConceptDefinition(id: Self.node.id, word: Self.node.conceptLabel, partOfSpeech: "",
                                     pronunciation: "", meaning: Self.node.definition, example: "")
        }
    }

    private var concepts: [ConceptDefinition] { selected.compactMap(concept(for:)) }
    private var titles: Set<String> { Set(concepts.map(\.word)) }

    private var result: (title: String, definition: String) {
        if titles == ["Justice", "Mercy"], weights.count == 2 {
            let justice = weights[selected.firstIndex { concept(for: $0)?.word == "Justice" } ?? 0]
            if justice >= 0.6 {
                return ("Restorative Justice", "Giving what is owed in a way that aims to heal the wrong and restore the offender, not only to punish.")
            } else if justice <= 0.4 {
                return ("Forgiveness", "Freely releasing a debt one could justly claim, while still naming the wrong as a wrong.")
            }
            return ("Equity", "Applying a just rule with mercy when its strict letter would defeat its purpose in a particular case.")
        }
        if titles == ["Justice", "Mercy", "Prudence"] {
            return ("Discernment", "Judging wisely when a wrong calls for firmness and when it calls for relief, so that both justice and mercy are served.")
        }
        let names = concepts.map(\.word).joined(separator: ", ")
        return ("A new concept", "In the app, Angrove proposes a concept that sits between \(names), leaning toward the ideas you weight most.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: preselected.isEmpty
                ? "Tap an Insight to read it. Tap Select, choose two or more Insights, then tap Midpoint. Drag on the tree, or use the percentages, to shift the balance."
                : "Three Insights are selected here. Drag on the tree, or use the percentages, to see how the balance changes.")

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

            if isMidpointMode {
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

            HStack(spacing: 12) {
                controlButton(isSelecting ? "Done" : "Select", icon: "circle.dashed",
                              enabled: !isMidpointMode) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSelecting.toggle()
                        dockedInsight = nil
                    }
                }
                controlButton(isMidpointMode ? "Back" : "Midpoint", icon: "graph.2d",
                              enabled: isMidpointMode || selected.count >= 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isMidpointMode.toggle()
                        dockedInsight = nil
                    }
                }
                controlButton("Reset", icon: "arrow.counterclockwise", enabled: true) {
                    reset()
                }
            }

            if isMidpointMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXAMPLE RESULT")
                        .font(AngroveTheme.Typography.settingsDetail)
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    Text(result.title)
                        .font(AngroveTheme.Typography.settingsHeading)
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                    Text(result.definition)
                        .font(AngroveTheme.Typography.settingsBody)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .lineSpacing(FlowLayout.rowSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(result.title)
                .transition(.opacity)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AngroveTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .animation(.easeInOut(duration: 0.25), value: result.title)
            }
        }
        .task { await applyPreselection() }
    }

    private var canvas: some View {
        InsightTreeCanvasView(
            nodes: [Self.node],
            edges: [],
            restoreFocusedCameraRequest: 0,
            focusedInsightID: nil,
            focusedSearchNodeID: nil,
            pulsingInsightID: nil,
            pulsingNodeID: nil,
            selectedCanvasTargets: selected,
            selectionPulseRequest: selectionPulse,
            insightBondLengths: Dictionary(uniqueKeysWithValues: Self.node.insights.map { ($0.id, CGFloat(135)) }),
            isMidpointMode: isMidpointMode,
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

    private func tapped(_ target: CanvasSelectionTarget, insight: InsightModel? = nil) {
        guard !isMidpointMode else { return }
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
        guard !isMidpointMode else { return }
        if let index = selected.firstIndex(of: target) {
            selected.remove(at: index)
        } else if selected.count < CanvasSelectionPolicy.maximumCount {
            selected.append(target)
            if selected.count > 1 { selectionPulse += 1 }
        }
        SettingsHaptics.playSelection()
    }

    private func applyPreselection() async {
        guard !preselected.isEmpty, selected.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(900))
        selected = preselected.compactMap { title in
            Self.node.insights.first { $0.title == title }.map { .insight($0.id) }
        }
        selectionPulse += 1
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.easeInOut(duration: 0.25)) { isMidpointMode = true }
    }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isMidpointMode = false
            isSelecting = false
            dockedInsight = nil
            selected = []
            weights = []
        }
        canvasID = UUID()
    }

    private func controlButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SettingsHaptics.playSelection()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(AngroveTheme.Typography.settingsLabel)
            }
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Study

/// The real tree canvas holding one Node Concept with three Insights. The canvas starts Study when
/// `studyNodeID` changes, so the example shows the tree briefly and then moves into Study.
private struct UserGuideStudyExample: View {
    @State private var studyNodeID: UUID?

    init() {
        // Example Insights aren't new discoveries. The canvas reads the seen list when it is
        // created, so mark them before it exists or they carry "new" dots.
        let exampleIDs = Set(Self.node.insights.map(\.id))
        InsightDiscoveryStore.saveSeenInsightIDs(
            Array(InsightDiscoveryStore.loadSeenInsightIDs().union(exampleIDs))
        )
        InsightDiscoveryStore.saveUndiscoveredInsightIDs(
            InsightDiscoveryStore.loadUndiscoveredInsightIDs().subtracting(exampleIDs)
        )
    }

    private static let conversationID = UUID(uuidString: "6F1C2A9E-2D0B-4B8E-9C7A-1E5F3A0B7C11")!
    private static let node = NodeModel(
        id: UUID(uuidString: "A1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C01")!,
        conceptLabel: "Virtue",
        definition: "A good habit of mind or will that disposes a person to act well.",
        insights: [
            insight("Prudence", "Practical wisdom that judges what the good requires here and now.", "A1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C02"),
            insight("Temperance", "Moderation of desire for pleasure according to reason.", "A1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C03"),
            insight("Courage", "Firmness of mind in facing danger or hardship for the sake of the good.", "A1C7E0D4-5B2F-4E8A-8D1C-3F6B9E2A4C04"),
        ],
        embedding: [],
        position: .zero,
        isSuggested: false,
        suggestedInsights: nil
    )

    private static func insight(_ title: String, _ definition: String, _ id: String) -> InsightModel {
        InsightModel(id: UUID(uuidString: id)!, title: title, definition: definition, conversationID: conversationID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: "Drag the ring beneath Virtue to spin it, pinch to zoom, and tap an Insight to bring it forward.")

            GeometryReader { proxy in
                InsightTreeCanvasView(
                    nodes: [Self.node],
                    edges: [],
                    restoreFocusedCameraRequest: 0,
                    focusedInsightID: nil,
                    focusedSearchNodeID: nil,
                    pulsingInsightID: nil,
                    pulsingNodeID: nil,
                    selectedCanvasTargets: [],
                    selectionPulseRequest: 0,
                    onNodeTapped: { _ in },
                    onInsightTapped: { _ in },
                    onCanvasMoved: {},
                    onSuggestConnection: { _ in },
                    onDismissSuggestedNode: { _ in },
                    studyNodeID: studyNodeID,
                    // The ring and the node's zoom both scale from this slot. The real view uses
                    // 300 × 300 on a full screen; 240 keeps all three Insights inside this frame.
                    studySlot: CGRect(
                        x: (proxy.size.width - 240) / 2,
                        y: 50,
                        width: 240,
                        height: 240
                    )
                )
            }
            .frame(height: 460)
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                studyNodeID = Self.node.id
            }
            .background(AngroveTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(AngroveTheme.Colors.divider, lineWidth: 1)
            )
            .padding(.horizontal, -12)
        }
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
                    .font(AngroveTheme.Typography.settingsLabel)
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
                    .font(AngroveTheme.Typography.settingsLabel)
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
