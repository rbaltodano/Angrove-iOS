import SwiftUI
import Testing
import UIKit
import Vision
@testable import Angrove_iOS

@MainActor
@Suite(.serialized)
struct InsightCardPresentationTests {
    @Test("An open reader immediately shows each newly selected quoted Insight", arguments: [ColorScheme.light, .dark])
    func quotedInsightSelectionReplacesMountedCard(scheme: ColorScheme) async throws {
        let concepts = [
            ConceptDefinition(word: "Prudence", partOfSpeech: "", pronunciation: "",
                meaning: "Prudence guides wise choices in daily life.", example: ""),
            ConceptDefinition(word: "Justice", partOfSpeech: "", pronunciation: "",
                meaning: "Justice gives each person what is due.", example: ""),
            ConceptDefinition(word: "Temperance", partOfSpeech: "", pronunciation: "",
                meaning: "Temperance moderates desires with steady restraint.", example: "")
        ]
        let state = ConversationDefinitionState()
        let words = concepts.map { ConversationInsightWord(text: $0.word, sourceResponseBlock: nil) }
        for (word, concept) in zip(words, concepts) {
            state.definitionsByKey[word.id] = concept
        }
        let host = UIHostingController(rootView: QuotedInsightReaderHarness(state: state, concepts: concepts)
            .environment(\.colorScheme, scheme))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 650)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        for (step, index) in [0, 1, 2, 0].enumerated() {
            state.present(words[index])
            try await Task.sleep(for: .milliseconds(900))
            host.view.layoutIfNeeded()
            let image = capture(window)
            let visibleText = try recognizedText(in: image)
            #expect(visibleText.contains(normalized(concepts[index].meaning)))
            for other in concepts.indices where other != index {
                #expect(!visibleText.contains(normalized(concepts[other].meaning)))
            }
            try record(image, name: "insight-switch-\(scheme == .light ? "light" : "dark")-\(step)-\(concepts[index].word.lowercased())")
        }

        state.activeWord = nil
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let closed = capture(window)
        let visibleText = try recognizedText(in: closed)
        for concept in concepts {
            #expect(!visibleText.contains(normalized(concept.meaning)))
        }
        try record(closed, name: "insight-switch-\(scheme == .light ? "light" : "dark")-closed")
    }

    private func capture(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func recognizedText(in image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        let cgImage = try #require(image.cgImage)
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return normalized((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " "))
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private func record(_ image: UIImage, name: String) throws {
        let png = try #require(image.pngData())
        Attachment.record(png, named: "\(name).png")
        try png.write(to: FileManager.default.temporaryDirectory.appending(path: "\(name).png"))
    }

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

private struct QuotedInsightReaderHarness: View {
    let state: ConversationDefinitionState
    let concepts: [ConceptDefinition]

    var body: some View {
        VStack(spacing: 24) {
            QuotedInsightRow(concepts: concepts, alignment: .leading) { concept in
                BranchContextChip(title: concept.word, icon: "text.bubble", animatesAppearance: false,
                    onTap: { state.present(ConversationInsightWord(text: concept.word, sourceResponseBlock: nil)) })
            }
            .frame(height: 72)
            Spacer()
            if let word = state.activeWord {
                DynamicInsightSheetCard(word: word.text, concept: state.definitionsByKey[word.id],
                    isSaved: true, onQuote: {}, onFork: {}, onToggleSaved: {},
                    onClose: { state.activeWord = nil })
                    .id(word.id)
            }
        }
        .padding(24)
        .frame(width: 375, height: 650)
        .background(AngroveTheme.Colors.canvas)
    }
}
