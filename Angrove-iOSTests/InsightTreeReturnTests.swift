import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Returning to the Insight Tree")
struct InsightTreeReturnTests {
    @Test("Saved hover survives reopening and stays separate for every tree")
    func scopedHoverPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InsightTreeLocalStateFileStore(rootDirectory: root)
        let conversation = UUID(), anotherConversation = UUID()
        let insight = CanvasSelectionTarget.insight(UUID())
        let node = CanvasSelectionTarget.node(UUID())
        try store.save(insight, key: InsightTreeHoverStore.key(scope: nil))
        try store.save(node, key: InsightTreeHoverStore.key(scope: conversation))
        let reopened = InsightTreeLocalStateFileStore(rootDirectory: root)
        #expect(reopened.load(CanvasSelectionTarget.self, key: InsightTreeHoverStore.key(scope: nil)) == insight)
        #expect(reopened.load(CanvasSelectionTarget.self, key: InsightTreeHoverStore.key(scope: conversation)) == node)
        #expect(reopened.load(CanvasSelectionTarget.self, key: InsightTreeHoverStore.key(scope: anotherConversation)) == nil)
        try store.save(node, key: InsightTreeHoverStore.key(scope: nil))
        #expect(reopened.load(CanvasSelectionTarget.self, key: InsightTreeHoverStore.key(scope: nil)) == node)
    }

    @MainActor
    @Test("Loading a remembered hover does not zoom out to fit a distant tree")
    func restorationDoesNotFitTree() {
        let canvas = makeCanvas(restoring: true)
        canvas.keepTreeInView(in: CGSize(width: 320, height: 780))
        #expect(canvas.cameraState.scale == 1)
        #expect(canvas.cameraState.offset == .zero)
        let retained = makeCanvas(restoring: true, hovering: true)
        #expect(!retained.focusCurrentHover(in: CGSize(width: 320, height: 780)))
        #expect(retained.cameraState.offset == .zero)
    }

    @MainActor
    @Test("A retained hover recenters on return without needing a changed focus ID")
    func retainedHoverRefocuses() {
        let canvas = makeCanvas(hovering: true)
        #expect(canvas.focusCurrentHover(in: CGSize(width: 320, height: 780)))
        #expect(canvas.cameraState.scale >= 1.15)
        #expect(canvas.cameraState.offset != .zero)
        let offset = canvas.cameraState.offset
        canvas.keepTreeInView(in: CGSize(width: 320, height: 780))
        #expect(canvas.cameraState.offset == offset)
    }

    @MainActor
    private func makeCanvas(restoring: Bool = false, hovering: Bool = false) -> InsightTreeCanvasView {
        let id = UUID()
        let node = NodeModel(id: id, conceptLabel: "Remembered", definition: "", insights: [], embedding: [],
                             position: CGPoint(x: 4000, y: 4000), isSuggested: false, suggestedInsights: nil)
        return InsightTreeCanvasView(nodes: [node], edges: [], restoreFocusedCameraRequest: 0,
            focusedInsightID: nil, focusedSearchNodeID: hovering ? id : nil,
            pulsingInsightID: nil, pulsingNodeID: hovering ? id : nil,
            selectedCanvasTargets: [], selectionPulseRequest: 0,
            isRestoringHover: restoring, isHoveringTarget: hovering,
            onNodeTapped: { _ in }, onInsightTapped: { _ in }, onCanvasMoved: {},
            onSuggestConnection: { _ in }, onDismissSuggestedNode: { _ in })
    }

    @MainActor
    @Test("The dot grid reaches the bottom of a small phone at minimum zoom")
    func minimumZoomGridCoverage() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 780)
        defer { window.isHidden = true; window.rootViewController = nil }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "InsightTreeReturnLayouts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let grid = AnimatedDotGridBackground(settledOffset: CGSize(width: 327, height: -841), settledScale: 0.28)
                .background(AngroveTheme.Colors.canvas)
                .environment(\.colorScheme, dark ? .dark : .light)
                .ignoresSafeArea()
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = UIHostingController(rootView: grid)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let png = try #require(image.pngData())
            let filename = dark ? "grid-dark.png" : "grid-light.png"
            try png.write(to: directory.appending(path: filename))
            Attachment.record(png, named: filename)
            // A capped field ends near y=540. Dots must produce contrast below y=700 too.
            let cg = try #require(image.cgImage)
            let crop = try #require(cg.cropping(to: CGRect(x: 0, y: CGFloat(cg.height) * 0.9,
                                                           width: CGFloat(cg.width), height: CGFloat(cg.height) * 0.09)))
            var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let context = try #require(CGContext(data: &bytes, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            let reds = stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
            #expect(Int(reds.max()!) - Int(reds.min()!) > 2)
        }
    }
}
