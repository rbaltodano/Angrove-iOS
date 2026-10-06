#if DEBUG
import SwiftUI

/// Isolated UI verification content; never enters live storage or generation.
struct StudyBranchPreviewView: View {
    @State private var count = Self.previewCount
    @State private var promoted = false
    @State private var ready = false
    @State private var finished = false
    @State private var children: [InsightModel] = []
    @State private var runID = UUID()
    @State private var parentID = UUID()
    @State private var branchNodeID = UUID()
    @State private var source = InsightModel(title: "Connected Ideas", definition: "Branch preview source.")

    private var usesTree: Bool {
        ProcessInfo.processInfo.arguments.contains("--study-branch-preview-tree")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Branch Preview · Test Content")
                    .font(.caption)
                Spacer()
                Button("Reset", action: reset)
            }
            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            .padding()
            if usesTree {
                treePreview.id(runID)
            } else {
                StudyBranchScene(
                sourceTitle: ProcessInfo.processInfo.arguments.contains("--study-branch-preview-long-title")
                    ? "Understanding how foundational assumptions connect to complex ideas"
                    : "Understanding how ideas connect",
                initialPosition: CGPoint(x: 100, y: 120),
                isPromoted: promoted,
                children: children,
                isReady: ready,
                onFinished: { finished = true },
                onInsightTapped: { _ in }
            )
            .id(runID)
            }
            StudyToolCard()
                .padding(.horizontal, 16)
            StudyBranchDockControls(
                count: count,
                onCountChange: { count = $0 },
                isBusy: promoted && !finished,
                onConfirm: confirm
            )
            .padding(.vertical, 16)
        }
        .background(AngroveTheme.Colors.canvas.ignoresSafeArea())
        .task {
            if ProcessInfo.processInfo.arguments.contains("--study-branch-preview-autoplay") {
                try? await Task.sleep(for: .seconds(1))
                confirm()
            }
        }
    }

    private var treePreview: some View {
        GeometryReader { geometry in
            InsightTreeCanvasView(
                nodes: previewNodes,
                edges: promoted ? [EdgeModel(id: parentID, fromNodeID: parentID,
                    toNodeID: branchNodeID, distance: 0.5, isSuggested: false, showSuggestButton: false)] : [],
                restoreFocusedCameraRequest: 0,
                focusedInsightID: nil,
                focusedSearchNodeID: nil,
                pulsingInsightID: nil,
                pulsingNodeID: nil,
                selectedCanvasTargets: [],
                selectionPulseRequest: 0,
                makeNodeChildIDs: Set(children.map(\.id)),
                generatedMakeNodeChildIDs: ready ? Set(children.map(\.id)) : [],
                insightBondLengths: Dictionary(uniqueKeysWithValues: children.enumerated().map { index, child in
                    (child.id, CGFloat(150 + index * 180 / max(count - 1, 1)))
                }),
                showsAllClusterInsights: true,
                onNodeTapped: { _ in },
                onInsightTapped: { _ in },
                onCanvasMoved: {},
                onSuggestConnection: { _ in },
                onDismissSuggestedNode: { _ in },
                studyNodeID: finished ? branchNodeID : parentID,
                studySlot: CGRect(x: geometry.size.width / 2 - 150,
                    y: geometry.size.height / 2 - 150, width: 300, height: 300),
                studyBranchSource: finished ? nil : source,
                studyBranchNodeID: branchNodeID,
                studyBranchIsPromoted: promoted,
                onStudyBranchFinished: { finished = true }
            )
        }
    }

    private var previewNodes: [NodeModel] {
        let parent = NodeModel(id: parentID, conceptLabel: "Old Parent", insights: promoted ? [] : [source],
            embedding: [1, 0], position: CGPoint(x: -340, y: 0), isSuggested: false)
        guard promoted else { return [parent] }
        return [parent, NodeModel(id: branchNodeID, conceptLabel: source.title, insights: children,
            embedding: [0.7, 0.3], position: .zero, isSuggested: false)]
    }

    private static var previewCount: Int {
        let prefix = "--study-branch-preview-count="
        let value = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
            .flatMap { Int($0.dropFirst(prefix.count)) } ?? 6
        return min(6, max(2, value))
    }

    private func confirm() {
        promoted = true
        Task { @MainActor in
            let delay = ProcessInfo.processInfo.arguments.contains("--study-branch-preview-slow-load") ? 10.0 : 2.0
            try? await Task.sleep(for: .seconds(delay))
            let titles = ["Identify the core idea", "Separate its assumptions", "Trace basic relationships", "Examine causes and effects", "Compare foundational concepts", "Connect the fundamental points"]
            children = titles.prefix(count).map {
                InsightModel(title: $0, definition: "Preview content for visual verification only.")
            }
            ready = true
        }
    }

    private func reset() {
        promoted = false
        ready = false
        finished = false
        children = []
        runID = UUID()
    }
}
#endif
