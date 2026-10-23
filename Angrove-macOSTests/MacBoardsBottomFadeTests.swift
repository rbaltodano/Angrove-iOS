import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsBottomFadeTests {
    @Test func openingAndClosingControlsCardsLeavesCanvasFadeInPlace() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let board = WorktreeBoard()
            // A saturated photo makes the gradient visible independently of the canvas fill.
            let image = NSImage(size: NSSize(width: 800, height: 700), flipped: false) { rect in
                NSColor.systemBlue.setFill()
                rect.fill()
                return true
            }
            var photo = WorktreeBoard.Item(origin: CGPoint(x: -400, y: -350))
            photo.image = UploadedFile(name: "Fade test", imageData: try #require(image.tiffRepresentation), rotationDegrees: 0)
            photo.size = CGSize(width: 800, height: 700)
            photo.photoLayout = WorktreePhotoLayout(contentSize: photo.size!)
            board.items = [photo]
            let queue = ModelTaskQueue()
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: queue)
            let popup = ModelTasksPopupState()
            let center = ModelCompletionNotificationCenter()
            let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: popup, runtime: runtime)
                .overlayPreferenceValue(MacGlobalModelControlsKey.self) { published in
                    MacGlobalModelControlsDock(published: published, modelTasks: queue, queuePopup: popup)
                }
                .environment(\.modelCompletionNotifications, center)
                .environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .seconds(2))
            let resting = try snapshot(host)
            popup.isOpen = true
            try await Task.sleep(for: .milliseconds(800))
            try expectSameFade(resting, snapshot(host))
            popup.reset()
            let concept = ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                meaning: "Practical wisdom that guides sound judgment.", example: "")
            center.postInsightDefinition(concept, conversationID: nil, postsSystemNotification: false)
            center.open(id: try #require(center.notifications.first).id)
            try await Task.sleep(for: .milliseconds(800))
            let opened = try snapshot(host)
            try expectSameFade(resting, opened)
            let png = try #require(opened.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-board-fixed-fade-\(scheme == .light ? "light" : "dark").png"))
            center.closeInsight()
            try await Task.sleep(for: .milliseconds(800))
            try expectSameFade(resting, snapshot(host))
        }
    }

    private func snapshot<V: View>(_ host: NSHostingView<V>) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func expectSameFade(_ before: NSBitmapImageRep, _ after: NSBitmapImageRep) throws {
        // Outside the centered cards, sample the full height of the bottom gradient.
        for y in stride(from: 390, through: 610, by: 10) {
            let xPixel = Int(CGFloat(before.pixelsWide) * 20 / 760)
            let yPixel = Int(CGFloat(before.pixelsHigh) * CGFloat(y) / 620)
            let lhs = try #require(before.colorAt(x: xPixel, y: yPixel)?.usingColorSpace(.deviceRGB))
            let rhs = try #require(after.colorAt(x: xPixel, y: yPixel)?.usingColorSpace(.deviceRGB))
            #expect(abs(lhs.redComponent - rhs.redComponent) < 0.02)
            #expect(abs(lhs.greenComponent - rhs.greenComponent) < 0.02)
            #expect(abs(lhs.blueComponent - rhs.blueComponent) < 0.02)
        }
    }
}
