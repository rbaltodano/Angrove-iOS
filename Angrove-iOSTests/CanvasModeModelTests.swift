import Testing
@testable import Angrove_iOS

@Suite("Conversation canvas Study lifecycle")
struct CanvasModeModelTests {
    @Test("Closing Study clears its Exit and Tools controls before the tree unmounts",
          arguments: [false, true])
    func closingCanvasEndsStudy(toolsOpen: Bool) {
        let mode = CanvasModeModel()
        mode.isTopicCanvasVisible = true
        mode.isCanvasStudyMode = true
        mode.isCanvasStudyToolsActive = toolsOpen
        mode.canvasStudyBranchCount = 5

        // Quote closes the canvas directly; no Study exit callback follows from the tree.
        mode.isTopicCanvasVisible = false

        #expect(!mode.isCanvasStudyMode)
        #expect(!mode.isCanvasStudyToolsActive)
        #expect(mode.canvasStudyBranchCount == 5)

        mode.isTopicCanvasVisible = true
        #expect(!mode.isCanvasStudyMode)
        #expect(!mode.isCanvasStudyToolsActive)

        // A fresh Study session can still be entered and closed normally.
        mode.isCanvasStudyMode = true
        mode.isCanvasStudyToolsActive = true
        mode.isTopicCanvasVisible = false
        #expect(!mode.isCanvasStudyMode)
        #expect(!mode.isCanvasStudyToolsActive)
    }

    @Test("Exiting Study within the tree leaves the canvas open")
    func studyExitKeepsCanvasVisible() {
        let mode = CanvasModeModel()
        mode.isTopicCanvasVisible = true
        mode.isCanvasStudyMode = true
        mode.isCanvasStudyToolsActive = true

        mode.isCanvasStudyMode = false
        mode.isCanvasStudyToolsActive = false

        #expect(mode.isTopicCanvasVisible)
    }
}
