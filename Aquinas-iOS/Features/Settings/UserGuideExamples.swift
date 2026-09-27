//
//  UserGuideExamples.swift
//  Aquinas-iOS
//

import SwiftUI

/// Hands-on examples for the User Guide. Each one reuses the real component the feature uses, so
/// the example changes with the design. Content is written ahead of time: examples never call the
/// model.
enum UserGuideExample {
    case definitions
    case midpoint
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
                .font(AquinasTheme.Typography.uiHeading)
                .foregroundStyle(AquinasTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)

            switch example {
            case .definitions:
                UserGuideDefinitionsExample(collectedDefinitions: $collectedDefinitions)
            case .midpoint:
                UserGuideMidpointExample()
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
            .font(AquinasTheme.Typography.body)
            .foregroundStyle(AquinasTheme.Colors.paragraphText)
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
    @AppStorage(SettingsStorageKey.conversationTextAlignment) private var conversationTextAlignment: ConversationTextAlignmentOption = .center
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .sans

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
            .background(AquinasTheme.Colors.canvasSecondary)
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
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }
}

// MARK: - Midpoint

/// The real Midpoint balance card over two preset Insights. The real feature asks the model for
/// candidates; here the result switches between three results written ahead of time.
private struct UserGuideMidpointExample: View {
    @State private var justicePercent = 50

    private static let justice = ConceptDefinition(
        word: "Justice",
        partOfSpeech: "",
        pronunciation: "",
        meaning: "The constant will to give each person what is owed.",
        example: ""
    )
    private static let mercy = ConceptDefinition(
        word: "Mercy",
        partOfSpeech: "",
        pronunciation: "",
        meaning: "Compassion for another's distress that moves us to relieve it, giving more than is owed.",
        example: ""
    )

    private var result: (title: String, definition: String) {
        switch justicePercent {
        case 60...:
            ("Restorative Justice", "Giving what is owed in a way that aims to heal the wrong and restore the offender, not only to punish.")
        case ...40:
            ("Forgiveness", "Freely releasing a debt one could justly claim, while still naming the wrong as a wrong.")
        default:
            ("Equity", "Applying a just rule with mercy when its strict letter would defeat its purpose in a particular case.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserGuideExampleCaption(text: "Change the balance between Justice and Mercy. Drag a percentage or tap its arrows, and watch the midpoint shift.")

            MidpointPercentCard(
                concepts: [Self.justice, Self.mercy],
                weights: [Double(justicePercent) / 100, Double(100 - justicePercent) / 100],
                onSetPercent: { index, percent in
                    let clamped = min(100, max(0, percent))
                    justicePercent = index == 0 ? clamped : 100 - clamped
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("EXAMPLE RESULT")
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                Text(result.title)
                    .font(AquinasTheme.Typography.uiHeading)
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                Text(result.definition)
                    .font(AquinasTheme.Typography.body)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .lineSpacing(FlowLayout.rowSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(result.title)
            .transition(.opacity)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: result.title)
        }
    }
}

// MARK: - Study

/// The real tree canvas holding one Node Concept with three Insights. The canvas starts Study when
/// `studyNodeID` changes, so the example shows the tree briefly and then moves into Study.
private struct UserGuideStudyExample: View {
    @State private var hoveredInsight: InsightModel?
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
                    onNodeTapped: { _ in hoveredInsight = nil },
                    onInsightTapped: { hoveredInsight = $0 },
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
            .frame(height: 480)
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                studyNodeID = Self.node.id
            }
            .background(AquinasTheme.Colors.canvas)
            .clipped()
            // Full screen width, like the real Study view, instead of inset by the page margins.
            .padding(.horizontal, -24)

            VStack(alignment: .leading, spacing: 8) {
                Text(hoveredInsight?.title ?? Self.node.conceptLabel)
                    .font(AquinasTheme.Typography.uiHeading)
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                Text(hoveredInsight?.definition ?? Self.node.definition)
                    .font(AquinasTheme.Typography.body)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .lineSpacing(FlowLayout.rowSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: hoveredInsight?.id)
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
                    .font(AquinasTheme.Typography.uiSubheading)
                    .foregroundStyle(AquinasTheme.Colors.headingText)
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
                    .font(.custom("Figtree-Bold", size: 14))
                Spacer(minLength: 8)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(AquinasTheme.Colors.lightGreen)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AquinasTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
