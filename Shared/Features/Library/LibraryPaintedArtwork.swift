import SwiftUI

/// Each subject uses the owner's approved original export.
nonisolated enum LibraryArtwork: String, CaseIterable, Sendable {
    case scripture, church, councils, confessions, philosophy, history, political

    static func forWork(_ workID: String) -> Self {
        switch LibrarySubject.of(workID: workID) {
        case .scripture: .scripture
        case .earlyChristianity: .church
        case .councilsAndCreeds: .councils
        case .catechismsAndConfessions: .confessions
        case .philosophy: .philosophy
        case .history: .history
        case .politicalThought: .political
        }
    }

    func resource(_ suffix: String) -> URL? {
        let name = "\(rawValue)-\(suffix)"
        return Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "LibraryArtwork")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
    }
}

/// The original artwork stays visible without sprite playback or a reveal mask.
struct LibraryPaintedArtwork: View {
    let image: UIImage?
    var isPageVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInViewport = false
    @State private var hasEnteredView = false

    init(artwork: LibraryArtwork, isPageVisible: Bool = true) {
        image = artwork.resource("final").flatMap { UIImage(contentsOfFile: $0.path) }
        self.isPageVisible = isPageVisible
    }

    init(image: UIImage?, isPageVisible: Bool = true) {
        self.image = image
        self.isPageVisible = isPageVisible
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: geometry.size.width,
                           height: geometry.size.width * image.size.height / image.size.width)
                    .frame(height: geometry.size.height, alignment: .bottom)
            }
        }
        .opacity(hasEnteredView || reduceMotion ? 1 : 0)
        .blur(radius: hasEnteredView || reduceMotion ? 0 : 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            isInViewport = visible
            revealIfNeeded()
        }
        .onChange(of: isPageVisible) { revealIfNeeded() }
    }

    private func revealIfNeeded() {
        guard isInViewport, isPageVisible, !hasEnteredView else { return }
        withAnimation(reduceMotion ? nil : .timingCurve(0.55, 0, 0.17, 1, duration: 0.6)) {
            hasEnteredView = true
        }
    }
}
