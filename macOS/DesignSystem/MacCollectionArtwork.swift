import SwiftUI

/// Complete still artwork for the three collection overviews.
enum MacCollectionArtworkKind {
    case boards, studyTopics, conversations

    var assetName: String {
        switch self {
        case .boards: "BoardsMosaicFinal"
        case .studyTopics: "CollectionStudyTopics"
        case .conversations: "CollectionConversations"
        }
    }

    var topOffset: CGFloat {
        switch self {
        case .boards: 0
        case .studyTopics, .conversations: 144
        }
    }

    func width(in pageWidth: CGFloat) -> CGFloat {
        // Keep readable text beside the artwork even in a narrow window.
        max(0, min(420, pageWidth * 0.5,
            pageWidth - MacConversationStyle.pageHorizontalPadding - 280 - 24))
    }

    var aspectRatio: CGFloat {
        switch self {
        case .boards: 1095.0 / 650.0
        case .studyTopics: 1544.0 / 634.0
        case .conversations: 1519.0 / 464.0
        }
    }
}

@Observable
final class MacCollectionArtworkParallax {
    var scrollOffset: CGFloat = 0
}

/// The entire image stays inside the page, aligned to its right edge.
/// Every appearance uses Home's return fade and blur, including the first visit.
struct MacCollectionArtwork: View {
    let kind: MacCollectionArtworkKind
    let parallax: MacCollectionArtworkParallax
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isBootRevealComplete) private var isBootRevealComplete

    var body: some View {
        GeometryReader { geometry in
            let width = kind.width(in: geometry.size.width)
            Image(kind.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: width / kind.aspectRatio)
                .opacity(isShown ? 1 : 0)
                .blur(radius: isShown || reduceMotion ? 0 : 8)
                .offset(y: kind.topOffset + (reduceMotion ? 0 : max(parallax.scrollOffset, 0) * 0.0375))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isBootRevealComplete) {
            guard isBootRevealComplete else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                : .timingCurve(0.55, 0, 0.17, 1, duration: 0.6)) {
                isShown = true
            }
        }
        .onDisappear { isShown = false }
    }
}

/// Reserves the image's real horizontal and vertical footprint in the overview header.
struct MacCollectionArtworkLayout {
    var trailingInset: CGFloat = 0
    var minimumHeaderHeight: CGFloat = 0

    init() {}

    init(kind: MacCollectionArtworkKind, pageWidth: CGFloat) {
        let width = kind.width(in: pageWidth)
        let padding = MacConversationStyle.pageHorizontalPadding
        let contentWidth = min(MacCollectionLayout.contentMaxWidth, max(0, pageWidth - padding * 2))
        let contentTrailingInset = (pageWidth - contentWidth) / 2
        trailingInset = max(0, width + 24 - contentTrailingInset)
        minimumHeaderHeight = max(0,
            kind.topOffset + width / kind.aspectRatio - MacConversationStyle.pageTopPadding)
    }
}

extension EnvironmentValues {
    @Entry var collectionArtworkLayout = MacCollectionArtworkLayout()
}
