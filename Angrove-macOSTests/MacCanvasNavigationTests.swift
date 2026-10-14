import CoreGraphics
import Testing
@testable import AngroveMac

struct MacCanvasNavigationTests {
    private let viewport = CGSize(width: 700, height: 900)

    @Test func ordinaryScrollMovesVerticallyAndPreservesZoom() {
        var camera = CanvasScrollTransform(scale: 1.4, offset: CGSize(width: 40, height: -30))
        camera.apply(delta: CGSize(width: 0, height: 25), command: false, shift: false,
                     anchor: .zero, viewport: viewport)
        #expect(camera.offset == CGSize(width: 40, height: -5))
        #expect(camera.scale == 1.4)
    }
    @Test func shiftScrollMovesOnlyHorizontallyIncludingAppKitRemappedDeltas() {
        for delta in [CGSize(width: 0, height: -25), CGSize(width: -25, height: 0)] {
            var camera = CanvasScrollTransform(scale: 1, offset: CGSize(width: 40, height: -30))
            camera.apply(delta: delta, command: false, shift: true, anchor: .zero, viewport: viewport)
            #expect(camera.offset == CGSize(width: 15, height: -30))
        }
    }
    @Test func commandScrollKeepsTheWorldPointUnderThePointer() {
        let anchor = CGPoint(x: 120, y: 310)
        var state = CanvasScrollTransform(scale: 0.8, offset: CGSize(width: 90, height: -50))
        let before = InsightTreeCamera(scale: state.scale, offset: state.offset).screenToWorld(anchor, in: viewport)
        state.apply(delta: CGSize(width: 0, height: 18), command: true, shift: true,
                    anchor: anchor, viewport: viewport)
        #expect(state.scale > 0.8)
        let after = InsightTreeCamera(scale: state.scale, offset: state.offset).worldToScreen(before, in: viewport)
        #expect(abs(after.x - anchor.x) < 0.0001)
        #expect(abs(after.y - anchor.y) < 0.0001)
        state.apply(delta: CGSize(width: 0, height: -18), command: true, shift: false,
                    anchor: anchor, viewport: viewport)
        #expect(abs(state.scale - 0.8) < 0.0001)
        #expect(abs(state.offset.width - 90) < 0.0001)
        #expect(abs(state.offset.height + 50) < 0.0001)
    }
    @Test func zoomNeverEscapesTheSharedCanvasLimits() {
        var camera = CanvasScrollTransform(scale: 1, offset: .zero)
        camera.apply(delta: CGSize(width: 0, height: 10_000), command: true, shift: false,
                     anchor: .zero, viewport: viewport)
        #expect(camera.scale == 2.6)
        camera.apply(delta: CGSize(width: 0, height: -10_000), command: true, shift: false,
                     anchor: .zero, viewport: viewport)
        #expect(camera.scale == 0.28)
    }
    @Test func dividerStopsAtMinimumThenCollapsesInTheSameDrag() {
        var pane = MacInsightPaneLayout(isPinned: true)
        pane.drag(from: 0, translation: -300, workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 1000) == 500)
        pane.finishDrag()
        pane.drag(from: 500, translation: -100, workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 1000) == 600)
        pane.finishDrag()
        pane.drag(from: 600, translation: 183, workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 1000) == 500)
        #expect(!pane.collapsedDuringDrag)
        pane.drag(from: 600, translation: 184, workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 1000) == 0)
        #expect(pane.collapsedDuringDrag)
        pane.finishDrag()
        #expect(pane.viewportWidth(in: 1000) == 0)
        pane.open()
        #expect(pane.fraction == 0.5)
        pane.drag(from: 500, translation: -2000, workspaceWidth: 1000)
        #expect(pane.fraction == 0.8)
    }
    @Test func narrowWindowsClipInsteadOfShrinkingTheTreeContent() {
        var pane = MacInsightPaneLayout(isPinned: true)
        pane.open(workspaceWidth: 800)
        #expect(pane.viewportWidth(in: 800) == 500)
        #expect(pane.contentWidth(in: 800) == 500)
        #expect(pane.viewportWidth(in: 450) == 360)
        #expect(pane.contentWidth(in: 450) == 500)
        pane.drag(from: 360, translation: 83, workspaceWidth: 450)
        #expect(pane.viewportWidth(in: 450) == 360)
        pane.drag(from: 360, translation: 84, workspaceWidth: 450)
        pane.finishDrag()
        #expect(pane.viewportWidth(in: 450) == 0)
    }
    @Test func draggingBackOutReversesCollapseBeforeRelease() {
        var pane = MacInsightPaneLayout(isPinned: true)
        pane.open()
        pane.drag(from: 500, translation: 84, workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 1000) == 0)
        pane.drag(from: 500, translation: -40, workspaceWidth: 1000)
        pane.finishDrag()
        #expect(pane.viewportWidth(in: 1000) == 540)
    }

    @Test func floatingPaneCollapsesAtTheSameThresholdAndRetainsItsRole() {
        for swapped in [false, true] {
            var pane = MacInsightPaneLayout()
            pane.open(workspaceWidth: 1400)
            if swapped { pane.swap() }
            pane.drag(from: 500, translation: -150, workspaceWidth: 1400)
            pane.finishDrag()
            pane.drag(from: 650, translation: 233, workspaceWidth: 1400)
            #expect(pane.viewportWidth(in: 1400) == 500)
            pane.drag(from: 650, translation: 234, workspaceWidth: 1400)
            #expect(pane.viewportWidth(in: 1400) == 0)
            #expect(pane.isSwapped == swapped)
            #expect(!pane.isPinned)
            pane.drag(from: 650, translation: 100, workspaceWidth: 1400)
            #expect(pane.viewportWidth(in: 1400) == 550)
            pane.finishDrag()
            pane.close()
            pane.open(workspaceWidth: 1400)
            #expect(pane.viewportWidth(in: 1400) == 550)
        }
    }

    @Test func narrowFloatingPaneMeasuresOvershootFromItsVisibleMinimum() {
        var pane = MacInsightPaneLayout()
        pane.open(workspaceWidth: 450)
        pane.drag(from: 402, translation: 83, workspaceWidth: 450)
        #expect(pane.viewportWidth(in: 450) == 402)
        pane.drag(from: 402, translation: 84, workspaceWidth: 450)
        #expect(pane.viewportWidth(in: 450) == 0)
        pane.finishDrag()
        pane.open(workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 1000) == 500)
    }
    @Test func treeToggleRestoresResizedWidthAndOpenIsIdempotent() {
        var pane = MacInsightPaneLayout(isPinned: true)
        pane.toggle(workspaceWidth: 1200)
        #expect(pane.viewportWidth(in: 1200) == 600)
        pane.drag(from: 600, translation: -120, workspaceWidth: 1200)
        pane.finishDrag()
        #expect(pane.viewportWidth(in: 1200) == 720)
        pane.toggle(workspaceWidth: 1200)
        #expect(pane.viewportWidth(in: 1200) == 0)
        pane.close() // Closing an already closed tree keeps its remembered size.
        pane.toggle(workspaceWidth: 1200)
        #expect(pane.viewportWidth(in: 1200) == 720)
        pane.open(workspaceWidth: 1200) // /tree opens; it never closes or resets an open pane.
        #expect(pane.viewportWidth(in: 1200) == 720)
        pane.close()
        pane.open(workspaceWidth: 1200)
        #expect(pane.viewportWidth(in: 1200) == 720)
    }

    @Test func reopeningAfterWindowResizeRespectsMinimumAndMaximumWidths() {
        var pane = MacInsightPaneLayout(fraction: 0.7, isPinned: true)
        pane.close()
        pane.open(workspaceWidth: 450)
        #expect(pane.viewportWidth(in: 450) == 360)
        #expect(pane.contentWidth(in: 450) == 500)
    }
    @Test func floatingTreeRemembersPointWidthAndOnlyUnpinChangesMode() {
        var pane = MacInsightPaneLayout()
        pane.open(workspaceWidth: 1400)
        #expect(pane.viewportWidth(in: 1400) == 500)
        pane.drag(from: 500, translation: -180, workspaceWidth: 1400)
        pane.finishDrag()
        pane.close()
        pane.open(workspaceWidth: 1200)
        #expect(pane.viewportWidth(in: 1200) == 680)
        pane.togglePin(workspaceWidth: 1200)
        #expect(pane.isPinned)
        #expect(pane.viewportWidth(in: 1200) == 680)
        pane.close()
        #expect(pane.isPinned)
        #expect(pane.viewportWidth(in: 1200) == 0)
        pane.open(workspaceWidth: 1200)
        #expect(pane.isPinned)
        #expect(pane.viewportWidth(in: 1200) == 680)
        pane.togglePin(workspaceWidth: 1200)
        #expect(!pane.isPinned)
        #expect(pane.viewportWidth(in: 1200) == 680)
    }

    @Test func floatingTreeClipsInNarrowWindowWithoutLosingRememberedWidth() {
        var pane = MacInsightPaneLayout()
        pane.open(workspaceWidth: 1000)
        #expect(pane.viewportWidth(in: 450) == 402)
        #expect(pane.contentWidth(in: 450) == 500)
        #expect(pane.viewportWidth(in: 1000) == 500)
        pane.drag(from: 500, translation: 50, workspaceWidth: 1000)
        pane.finishDrag()
        #expect(pane.viewportWidth(in: 1000) == 500)
    }

    @Test func swappingKeepsTheSecondaryWidthAndExchangesPinnedSlots() {
        var pane = MacInsightPaneLayout()
        pane.open(workspaceWidth: 1400)
        pane.drag(from: 500, translation: -100, workspaceWidth: 1400)
        pane.swap()
        #expect(pane.treeViewportWidth(in: 1400) == 1400)
        #expect(pane.conversationViewportWidth(in: 1400) == 600)
        pane.togglePin(workspaceWidth: 1400)
        #expect(pane.treeViewportWidth(in: 1400) == 800)
        #expect(pane.conversationViewportWidth(in: 1400) == 600)
        pane.close()
        #expect(pane.isSwapped && pane.isPinned)
        #expect(pane.treeViewportWidth(in: 1400) == 1400)
        #expect(pane.conversationViewportWidth(in: 1400) == 0)
        pane.open(workspaceWidth: 1400)
        #expect(pane.conversationViewportWidth(in: 1400) == 600)
        pane.swap()
        #expect(pane.conversationViewportWidth(in: 1400) == 800)
        #expect(pane.treeViewportWidth(in: 1400) == 600)
        pane.togglePin(workspaceWidth: 1400)
        #expect(pane.conversationViewportWidth(in: 1400) == 1400)
        #expect(pane.treeViewportWidth(in: 1400) == 600)
    }

    @Test func controlsStayInTheirSlotsAcrossFloatingAndPinnedSwaps() {
        var pane = MacInsightPaneLayout()
        pane.open(workspaceWidth: 1400)
        pane.drag(from: 500, translation: -100, workspaceWidth: 1400)
        let floatingMainControls = pane.mainControlsViewportWidth(in: 1400)
        let secondaryControls = pane.viewportWidth(in: 1400)
        #expect(floatingMainControls == 752)
        pane.swap()
        #expect(pane.mainControlsViewportWidth(in: 1400) == floatingMainControls)
        #expect(pane.viewportWidth(in: 1400) == secondaryControls)
        pane.togglePin(workspaceWidth: 1400)
        let pinnedMainControls = pane.mainControlsViewportWidth(in: 1400)
        #expect(pinnedMainControls == 800)
        pane.swap()
        #expect(pane.mainControlsViewportWidth(in: 1400) == pinnedMainControls)
        #expect(pane.viewportWidth(in: 1400) == secondaryControls)
        pane.close()
        #expect(pane.mainControlsViewportWidth(in: 1400) == 1400)
        pane.open(workspaceWidth: 1400)
        #expect(pane.mainControlsViewportWidth(in: 1400) == pinnedMainControls)
    }

}
