import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Completed Midpoint connector appearance")
struct InsightTreeConnectorAppearanceTests {
    @MainActor
    @Test("Every completed Midpoint source line matches an ordinary concept line", arguments: [ColorScheme.light, .dark])
    func sourceLineOpacity(scheme: ColorScheme) throws {
        let ordinary = try render(scheme: scheme)
        #expect(try render(scheme: scheme, midpoint: true) == ordinary)
        #expect(try render(scheme: scheme, midpoint: true, secondary: true) == ordinary)
        #expect(try render(scheme: scheme, midpoint: true, secondary: true, branchedSource: true) == ordinary)
        #expect(try render(scheme: scheme, branchedSource: true) == ordinary)
        let insight = try renderInsight(scheme: scheme)
        #expect(try renderInsight(scheme: scheme, branched: true) == insight)
        #expect(try renderInsight(scheme: scheme, midpoint: true) == insight)
        #expect(try renderInsight(scheme: scheme, midpoint: true, branched: true) == insight)
        #expect(insight == ordinary)
    }

    @MainActor
    private func renderInsight(scheme: ColorScheme, midpoint: Bool = false, branched: Bool = false) throws -> Data {
        let nodeID = UUID(), insightID = UUID()
        let insight = InsightModel(concept: ConceptDefinition(id: insightID, word: "Source", partOfSpeech: "",
            pronunciation: "", meaning: "A transferred Insight", example: ""))
        var node = NodeModel(id: nodeID, conceptLabel: "Parent", definition: "", insights: [insight],
            embedding: [], position: CGPoint(x: -140, y: 0), isSuggested: false, suggestedInsights: nil)
        node.isMidpointConcept = midpoint
        let canvas = InsightTreeCanvasView(nodes: [node], edges: [], restoreFocusedCameraRequest: 0,
            focusedInsightID: nil, focusedSearchNodeID: nil, pulsingInsightID: nil, pulsingNodeID: nil,
            selectedCanvasTargets: [], selectionPulseRequest: 0, makeNodeChildIDs: branched ? [insightID] : [],
            onNodeTapped: { _ in }, onInsightTapped: { _ in }, onCanvasMoved: {},
            onSuggestConnection: { _ in }, onDismissSuggestedNode: { _ in })
        canvas.revealState.revealedInsightConnectorIDs.insert(insightID)
        let layout = InsightTreeCanvasView.CanvasInsightLayout(nodes: [node], insightsByNode: [nodeID: [insight]],
            placements: [insightID: .init(insight: insight, nodeID: nodeID, index: 0, count: 1,
                isPinnedAtNode: false, world: CGPoint(x: 140, y: 0), elevation: 0, localDepth: 0)])
        let size = CGSize(width: 320, height: 80)
        let renderer = ImageRenderer(content: canvas.insightConnectors(layout: layout,
            camera: .init(scale: 1, offset: .zero), size: size)
            .frame(width: size.width, height: size.height)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.colorScheme, scheme))
        renderer.scale = 3
        let png = try #require(renderer.uiImage?.pngData())
        Attachment.record(png, named: "\(scheme)-insight-midpoint-\(midpoint)-branch-\(branched).png")
        return png
    }

    @MainActor
    private func render(scheme: ColorScheme, midpoint: Bool = false, secondary: Bool = false,
                        branchedSource: Bool = false) throws -> Data {
        let from = UUID(), to = UUID(), childID = UUID()
        let child = InsightModel(concept: ConceptDefinition(id: childID, word: "Child", partOfSpeech: "",
            pronunciation: "", meaning: "A source Insight", example: ""))
        let source = NodeModel(id: from, conceptLabel: "Source", definition: "", insights: branchedSource ? [child] : [],
            embedding: [], position: .zero, isSuggested: false, suggestedInsights: nil)
        var destination = NodeModel(id: to, conceptLabel: "Destination", definition: "", insights: [],
            embedding: [], position: .zero, isSuggested: false, suggestedInsights: nil)
        destination.isMidpointConcept = midpoint
        var edge = EdgeModel(id: UUID(), fromNodeID: from, toNodeID: to, distance: 0.5,
            isSuggested: false, showSuggestButton: false)
        edge.isSecondary = secondary
        let canvas = InsightTreeCanvasView(nodes: [source, destination], edges: [edge], restoreFocusedCameraRequest: 0,
            focusedInsightID: nil, focusedSearchNodeID: nil, pulsingInsightID: nil, pulsingNodeID: nil,
            selectedCanvasTargets: [], selectionPulseRequest: 0, makeNodeChildIDs: branchedSource ? [childID] : [],
            onNodeTapped: { _ in }, onInsightTapped: { _ in }, onCanvasMoved: {},
            onSuggestConnection: { _ in }, onDismissSuggestedNode: { _ in })
        let size = CGSize(width: 320, height: 80)
        let route = InsightTreeConnectorRouting.Route(connector: .init(id: edge.id.uuidString,
            start: CGPoint(x: 20, y: 40), end: CGPoint(x: 300, y: 40), fromNodeID: from, toNodeID: to))
        let renderer = ImageRenderer(content: canvas.graphEdges(routes: [route], size: size, screenPerWorld: 1)
            .frame(width: size.width, height: size.height)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.colorScheme, scheme))
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        let png = try #require(image.pngData())
        Attachment.record(png, named: "\(scheme)-\(midpoint)-\(secondary)-\(branchedSource).png")
        return png
    }
}
