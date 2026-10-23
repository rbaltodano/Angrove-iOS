import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacWorktreeBoxSelectionTests {
    @Test func reverseDragsHaveTheSameBounds() {
        let expected = CGRect(x: -100, y: -50, width: 300, height: 150)
        #expect(WorktreeBoxSelection.rect(from: CGPoint(x: -100, y: -50), to: CGPoint(x: 200, y: 100)) == expected)
        #expect(WorktreeBoxSelection.rect(from: CGPoint(x: 200, y: 100), to: CGPoint(x: -100, y: -50)) == expected)
        #expect(WorktreeBoxSelection.rect(from: CGPoint(x: 200, y: -50), to: CGPoint(x: -100, y: 100)) == expected)
    }

    @Test func overlappingItemsAreSelectedAndShrinkingTheBoxRemovesThem() {
        let board = fixture()
        let ids = board.items.map(\.id)
        board.select(in: CGRect(x: -20, y: -20, width: 200, height: 100))
        #expect(board.selection == Array(ids.prefix(2)))
        board.select(in: CGRect(x: -20, y: -20, width: 50, height: 50))
        #expect(board.selection == [ids[0]])
        board.select(in: CGRect(x: 800, y: 800, width: 30, height: 30))
        #expect(board.selection.isEmpty)
    }

    @Test func additiveSelectionKeepsOnlyTheOriginalSeedAsTheBoxChanges() {
        let board = fixture()
        let ids = board.items.map(\.id)
        board.select(in: CGRect(x: 110, y: -20, width: 100, height: 100), addingTo: [ids[2], UUID()])
        #expect(board.selection == [ids[2], ids[1]])
        board.select(in: CGRect(x: 800, y: 800, width: 30, height: 30), addingTo: [ids[2]])
        #expect(board.selection == [ids[2]])
    }

    @Test func selectionUsesMeasuredBoundsAndDoesNotChangeItemsOrTheCamera() {
        let board = fixture()
        let items = board.items
        let camera = board.viewport
        board.itemSizes.removeValue(forKey: board.items[1].id)
        board.select(in: CGRect(x: -200, y: -200, width: 1000, height: 1000))
        #expect(board.selection == [items[0].id, items[2].id])
        #expect(board.items == items)
        #expect(board.viewport == camera)
    }

    @Test func rectangleRendersInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = ZStack(alignment: .topLeading) {
                AngroveTheme.Colors.canvas
                WorktreeSelectionRectangle(rect: CGRect(x: 20, y: 20, width: 240, height: 140))
            }
            .frame(width: 280, height: 180)
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-box-select-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private func fixture() -> WorktreeBoard {
        let board = WorktreeBoard()
        board.items = [
            WorktreeBoard.Item(origin: .zero, text: "First"),
            WorktreeBoard.Item(origin: CGPoint(x: 150, y: 0), text: "Second"),
            WorktreeBoard.Item(origin: CGPoint(x: 350, y: 0), text: "Third")
        ]
        for item in board.items { board.itemSizes[item.id] = CGSize(width: 100, height: 60) }
        return board
    }
}
