import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@MainActor
@Suite(.serialized)
struct InsightCardPresentationTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func cardLayout(scheme: ColorScheme) async throws {
        let concept = ConceptDefinition(word: "Practical wisdom", partOfSpeech: "", pronunciation: "",
            meaning: "The ability to judge what is good in a particular situation and choose a fitting action.", example: "")
        let card = DynamicInsightSheetCard(word: concept.word, concept: concept, isSaved: true, onQuote: {}, onFork: {}, onToggleSaved: {}, onClose: {})
            .padding(.horizontal, 24)
            .frame(width: 375, height: 350)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.colorScheme, scheme)
        let host = UIHostingController(rootView: card)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 350)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(1200))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData())
        Attachment.record(png, named: "insight-card-ios-\(scheme == .light ? "light" : "dark").png")
        try png.write(to: FileManager.default.temporaryDirectory.appending(path: "insight-card-ios-\(scheme == .light ? "light" : "dark").png"))
    }
}
