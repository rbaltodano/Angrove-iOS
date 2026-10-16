import Foundation
import Testing
@testable import AngroveMac

struct MacWorktreeTextBoxTests {
    @Test func rightEdgeWidensAndLeftEdgeKeepsTheRightSideFixed() {
        let start = CGSize(width: 200, height: 56)
        let right = WorktreeTextBoxResize.frame(origin: .zero, size: start, handle: .right,
                                                translation: CGSize(width: 40, height: 30), zoom: 2)
        #expect(right.size == CGSize(width: 220, height: 56))
        #expect(right.origin == .zero)

        let left = WorktreeTextBoxResize.frame(origin: CGPoint(x: 100, y: 0), size: start, handle: .left,
                                               translation: CGSize(width: 50, height: 0), zoom: 1)
        #expect(left.size.width == 150)
        #expect(left.origin.x == 150)
    }

    @Test func cornersResizeBothWaysWithinTheMinimums() {
        let corner = WorktreeTextBoxResize.frame(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 200, height: 56),
                                                 handle: .topLeft, translation: CGSize(width: 500, height: 500), zoom: 1)
        #expect(corner.size == CGSize(width: WorktreeTextBoxResize.minimumWidth, height: WorktreeTextEditor.lineHeight))
        #expect(corner.origin == CGPoint(x: 10 + 200 - WorktreeTextBoxResize.minimumWidth,
                                         y: 10 + 56 - WorktreeTextEditor.lineHeight))
    }

    @Test func boxShowsWithin84ScreenPointsAtAnyZoom() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        #expect(WorktreeTextBoxResize.isNear(CGPoint(x: 50, y: 20), to: rect, zoom: 1))
        #expect(WorktreeTextBoxResize.isNear(CGPoint(x: 184, y: 20), to: rect, zoom: 1))
        #expect(!WorktreeTextBoxResize.isNear(CGPoint(x: 185, y: 20), to: rect, zoom: 1))
        // At 2×, 84 screen points is 42 canvas points.
        #expect(WorktreeTextBoxResize.isNear(CGPoint(x: 142, y: 20), to: rect, zoom: 2))
        #expect(!WorktreeTextBoxResize.isNear(CGPoint(x: 150, y: 20), to: rect, zoom: 2))
        #expect(!WorktreeTextBoxResize.isNear(nil, to: rect, zoom: 1))
    }
}
