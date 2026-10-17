import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@MainActor
@Suite(.serialized)
struct SplitInsightCardPreviewTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func cardLayout(scheme: ColorScheme) async throws {
        let concept = ConceptDefinition(word: "Practical wisdom", partOfSpeech: "", pronunciation: "",
            meaning: "The ability to judge what is good in a particular situation and choose a fitting action.", example: "")
        let card = SplitInsightCardPreview(concept: concept)
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
        Attachment.record(png, named: "insight-card-split-ios-\(scheme == .light ? "light" : "dark").png")
        try png.write(to: FileManager.default.temporaryDirectory.appending(path: "insight-card-split-ios-\(scheme == .light ? "light" : "dark").png"))
    }
}

private struct SplitInsightCardPreview: View {
    let concept: ConceptDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: AngroveTheme.Spacing.unit * 2) {
            HStack(spacing: AngroveTheme.Spacing.unit) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                Text(concept.word.capitalized)
                    .font(BrandTypography.font("Figtree-Bold", size: 18))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AngroveTheme.Spacing.unit)
                ResponseButtons(canFork: false,
                    tintColor: AngroveTheme.Colors.placeholderText, onClose: {})
            }
            InsightDefinitionsContent(definitions: concept.contextualDefinitions)
            ResponseButtons(isSaved: true, canQuote: true, canFork: false,
                speechText: CardSpeech.text(for: concept),
                tintColor: AngroveTheme.Colors.placeholderText,
                saveTintColor: AngroveTheme.Colors.accentRed,
                onSave: {}, onQuote: {})
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(AngroveTheme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary,
                    in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        }
    }
}
