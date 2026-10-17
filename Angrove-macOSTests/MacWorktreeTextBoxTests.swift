import Foundation
import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

struct MacWorktreeTextBoxTests {
    @MainActor @Test func hoverChromeNeverRevealsTheBoxWithoutALocalSpotlight() throws {
        for dark in [false, true] {
            func render(visible: Bool, spotlight: CGPoint?) throws -> NSBitmapImageRep {
                let chrome = WorktreeBoxChrome(size: CGSize(width: 320, height: 120), zoom: 1,
                                               isVisible: visible, press: WorktreeBoxPress(), spotlight: spotlight)
                    .padding(16)
                    .background(AngroveTheme.Colors.canvas)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: chrome)
                renderer.scale = 1
                let image = try #require(renderer.cgImage)
                return NSBitmapImageRep(cgImage: image)
            }
            let hidden = try render(visible: false, spotlight: nil)
            let noPointer = try render(visible: true, spotlight: nil)
            let near = try render(visible: true, spotlight: CGPoint(x: 0, y: 60))
            // No pointer must remain fully masked, even if visibility arrives first or fades out.
            var noPointerIsHidden = true
            var distantPixelsAreHidden = true
            for y in 0..<hidden.pixelsHigh {
                for x in 0..<hidden.pixelsWide {
                    if hidden.colorAt(x: x, y: y) != noPointer.colorAt(x: x, y: y) { noPointerIsHidden = false }
                    // Every pixel beyond the spotlight stays identical to the hidden box.
                    if x > 16 + Int(WorktreeTextBoxResize.revealDistance) {
                        if hidden.colorAt(x: x, y: y) != near.colorAt(x: x, y: y) { distantPixelsAreHidden = false }
                    }
                }
            }
            #expect(noPointerIsHidden)
            #expect(distantPixelsAreHidden)
            #expect(hidden.colorAt(x: 16, y: 76) != near.colorAt(x: 16, y: 76))
            let data = try #require(near.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/angrove-boards-hover-\(dark ? "dark" : "light").png"))
        }
    }

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

    @Test func boxShowsWithin48ScreenPointsAtAnyZoom() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        #expect(WorktreeTextBoxResize.isNear(CGPoint(x: 50, y: 20), to: rect, zoom: 1))
        #expect(WorktreeTextBoxResize.isNear(CGPoint(x: 148, y: 20), to: rect, zoom: 1))
        #expect(!WorktreeTextBoxResize.isNear(CGPoint(x: 149, y: 20), to: rect, zoom: 1))
        // At 2×, 48 screen points is 24 canvas points.
        #expect(WorktreeTextBoxResize.isNear(CGPoint(x: 124, y: 20), to: rect, zoom: 2))
        #expect(!WorktreeTextBoxResize.isNear(CGPoint(x: 126, y: 20), to: rect, zoom: 2))
        #expect(!WorktreeTextBoxResize.isNear(nil, to: rect, zoom: 1))
    }

    @MainActor @Test func pointerOnlyPublishesWhenABoxCrossesItsLine() {
        let board = WorktreeBoard()
        let note = WorktreeBoard.Item(origin: CGPoint(x: 8, y: 8), text: "Note")
        board.items = [note]
        board.itemSizes[note.id] = CGSize(width: 100, height: 44)
        let pointer = WorktreeCanvasPointer()
        pointer.update(world: CGPoint(x: 400, y: 20), board: board, zoom: 1)
        #expect(pointer.nearIDs.isEmpty)
        #expect(pointer.nearWorld == nil)
        // 40 points right of the box (within 48): near, with the pointer in box coordinates.
        pointer.update(world: CGPoint(x: 140, y: 20), board: board, zoom: 1)
        #expect(pointer.nearIDs == [note.id])
        #expect(pointer.spotlight(for: note.id, board: board) == CGPoint(x: 140, y: 20))
        pointer.update(world: nil, board: board, zoom: 1)
        #expect(pointer.nearIDs.isEmpty)
        #expect(pointer.nearWorld == nil)
        #expect(pointer.spotlight(for: note.id, board: board) == nil)
    }

    @MainActor @Test func plusAndMinusResizeAboutTheCentre() {
        let board = WorktreeBoard()
        var note = WorktreeBoard.Item(origin: CGPoint(x: 100, y: 100), text: "Note")
        note.size = CGSize(width: 200, height: 100)
        var card = WorktreeBoard.Item(origin: .zero)
        card.insight = ConceptDefinition(word: "grace", partOfSpeech: "", pronunciation: "", meaning: "A gift.", example: "")
        board.items = [note, card]
        #expect(board.resize([note.id], growing: true))
        let grown = board.items[0]
        #expect(abs(grown.size!.width - 220) < 0.001)
        #expect(abs(grown.origin.x - 90) < 0.001)
        #expect(abs(grown.origin.y - 95) < 0.001)
        #expect(board.resize([note.id], growing: false))
        #expect(abs(board.items[0].size!.width - 200) < 0.001)
        // Insight cards keep their size.
        #expect(!board.resize([card.id], growing: true))
    }
}
