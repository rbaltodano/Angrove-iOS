import SwiftUI
import Testing
import AppKit
@testable import AngroveMac

@MainActor
struct InsightCardPresentationTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func cardLayout(scheme: ColorScheme) async throws {
        let concept = ConceptDefinition(word: "Practical wisdom", partOfSpeech: "", pronunciation: "",
            meaning: "The ability to judge what is good in a particular situation and choose a fitting action.", example: "")
        let card = InsightLibraryCard(insight: concept, isSaved: true, onQuote: {}, onFork: {}, onToggleSaved: {}, onClose: {})
            .padding(.horizontal, 24)
            .frame(width: 550, height: 350)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: card)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(1200))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        Attachment.record(png, named: "insight-card-mac-\(scheme == .light ? "light" : "dark").png")
        try png.write(to: FileManager.default.temporaryDirectory.appending(path: "insight-card-mac-\(scheme == .light ? "light" : "dark").png"))
    }
}
