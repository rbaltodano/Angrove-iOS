//
//  LeafRefresh.swift
//  Angrove-iOS
//

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

extension View {
    /// Pull-to-refresh with the leaf in place of the system spinner. Apply to a `ScrollView`.
    ///
    /// Pulling fades and unblurs the first sprite, then steps through the sprites so the fifth
    /// lands just before the release point. Releasing past that point runs `action` while the
    /// looping leaf animation holds the content down; when it completes the leaf fades and blurs
    /// out before the content settles back.
    func leafRefreshable(action: @escaping @MainActor () async -> Void) -> some View {
        modifier(LeafPullToRefresh(action: action))
    }
}

private struct LeafPullToRefresh: ViewModifier {
    let action: @MainActor () async -> Void

    /// Pull distance at which releasing triggers a refresh.
    private let threshold: CGFloat = 84
    /// Space held open above the content while refreshing.
    private let refreshingGap: CGFloat = 56
    /// A synchronous refresh would otherwise flash the leaf for a single frame.
    private let minimumRefreshDuration: Duration = .milliseconds(1_200)
    private let leafSize: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentOffsetY: CGFloat = 0
    @State private var contentInsetTop: CGFloat = 0
    @State private var isInteracting = false
    @State private var isRefreshing = false
    /// The looping leaf fading and blurring out once the refresh completes.
    @State private var isDismissingLeaf = false
    /// Keeps the pull sprites from reappearing while the held-open gap closes after a refresh.
    @State private var hidesPullSprites = false

    private var appliedGap: CGFloat { isRefreshing ? refreshingGap : 0 }

    /// The scroll view's resting top edge, excluding the gap this modifier adds.
    private var baseTop: CGFloat { contentInsetTop - appliedGap }

    /// How far the content sits below its resting position (includes the refreshing gap).
    private var revealed: CGFloat { -contentOffsetY - baseTop }

    private var pullProgress: CGFloat { max(0, revealed) / threshold }

    private var isArmed: Bool { isInteracting && !isRefreshing && pullProgress >= 1 }

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, appliedGap, for: .scrollContent)
            .onScrollGeometryChange(for: ScrollPosition.self) { geometry in
                ScrollPosition(offsetY: geometry.contentOffset.y, insetTop: geometry.contentInsets.top)
            } action: { _, position in
                contentOffsetY = position.offsetY
                contentInsetTop = position.insetTop
                if hidesPullSprites, !isRefreshing, revealed <= 1 { hidesPullSprites = false }
            }
            .onScrollPhaseChange { _, phase in
                let wasArmed = isArmed
                isInteracting = phase == .interacting
                if isInteracting, !isRefreshing { hidesPullSprites = false }
                if wasArmed, !isInteracting {
                    beginRefresh()
                }
            }
            .overlay(alignment: .top) {
                indicator
                    .offset(y: baseTop + revealed / 2 - leafSize / 2)
                    .allowsHitTesting(false)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isArmed) { _, armed in armed }
    }

    @ViewBuilder
    private var indicator: some View {
        if isRefreshing {
            LeafLoadingAnimation(size: leafSize)
                .opacity(isDismissingLeaf ? 0 : min(1, max(0, revealed / refreshingGap)))
                .blur(radius: isDismissingLeaf ? 6 : 0)
        } else if revealed > 0, !hidesPullSprites {
            // First 30% of the pull: sprite 1 fades in and comes into focus. The rest steps
            // through sprites 1–5, reaching 5 at 90% so it is fully grown just before release.
            let fadeIn = min(1, pullProgress / 0.3)
            let stage = reduceMotion
                ? 5
                : pullProgress < 0.3 ? 1 : min(5, 1 + Int((pullProgress - 0.3) / 0.6 * 4))
            LeafSprite(stage: stage, size: leafSize)
                .opacity(fadeIn)
                .blur(radius: (1 - fadeIn) * 6)
        }
    }

    private func beginRefresh() {
        withAnimation(.springStandard) { isRefreshing = true }
        Task { @MainActor in
            let clock = ContinuousClock()
            let start = clock.now
            await action()
            let remaining = minimumRefreshDuration - (clock.now - start)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            // Fade and blur the leaf out, then let the content settle back up.
            withAnimation(.easeOut(duration: 0.35)) { isDismissingLeaf = true }
            try? await Task.sleep(for: .milliseconds(350))
            hidesPullSprites = true
            withAnimation(.springStandard) { isRefreshing = false }
            isDismissingLeaf = false
        }
    }
}

private struct ScrollPosition: Equatable {
    let offsetY: CGFloat
    let insetTop: CGFloat
}
