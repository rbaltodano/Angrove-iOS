import SwiftUI

/// The five-sprite growing leaf: grows through sprites 1–4 over 1.2s, then holds the grown leaf
/// for 0.6s, on repeat. Shown while a response is being written and while a refresh runs.
struct LeafLoadingAnimation: View {
    var size: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage = 1

    private var shouldAnimate: Bool {
        !reduceMotion && scenePhase == .active
    }

    var body: some View {
        LeafSprite(stage: reduceMotion ? 5 : stage, size: size)
            .task(id: shouldAnimate) {
                stage = 1
                guard shouldAnimate else { return }

                do {
                    while !Task.isCancelled {
                        for (nextStage, milliseconds) in [(1, 300), (2, 300), (3, 300), (4, 300), (5, 600)] {
                            try Task.checkCancellation()
                            stage = nextStage
                            try await Task.sleep(for: .milliseconds(milliseconds))
                        }
                    }
                } catch {
                    // SwiftUI cancels the loop when the leaf disappears or the app pauses.
                }
            }
    }
}

/// One frame of the leaf animation (`WritingLeaf1`…`WritingLeaf5`).
struct LeafSprite: View {
    let stage: Int
    var size: CGFloat = 24

    var body: some View {
        Image("WritingLeaf\(min(max(stage, 1), 5))")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .transaction { $0.animation = nil }
    }
}
