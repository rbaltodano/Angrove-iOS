import SwiftUI

/// Keeps the destination mounted while its startup state is restored. The painted leaf grows
/// once per shell lifetime; background model jobs do not hold the launch screen open.
struct BootPresentation<Content: View>: View {
    let isReady: Bool
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage = 1
    @State private var hasFinishedGrowing = false
    @State private var hasStartedReveal = false
    @State private var hasFinishedReveal = false
    @State private var markOpacity = 0.0
    @State private var revealProgress = 0.0

    private var canReveal: Bool {
        isReady && hasFinishedGrowing && scenePhase == .active
    }

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvas.ignoresSafeArea()

            content
                .offset(y: reduceMotion ? 0 : 32 * (1 - revealProgress))
                .mask {
                    if hasFinishedReveal {
                        // Keep the reveal's full-screen coverage after the animation settles.
                        Rectangle()
                            .ignoresSafeArea()
                    } else {
                        BootRevealMask(progress: revealProgress, reduceMotion: reduceMotion)
                    }
                }
                .allowsHitTesting(hasFinishedReveal)
                .accessibilityHidden(!hasFinishedReveal)

            if !hasFinishedReveal {
                BootMark(
                    stage: reduceMotion ? 5 : stage,
                    leafBlur: reduceMotion ? 0 : 8 * (1 - markOpacity)
                )
                    .opacity(markOpacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .task {
            guard !hasFinishedGrowing else { return }
            do {
                // Hold the first sprite while it sharpens; growth starts after the entrance.
                withAnimation(.easeInOut(duration: 0.5)) {
                    markOpacity = 1
                }
                try await Task.sleep(for: .milliseconds(500))
                if !reduceMotion {
                    for nextStage in 1...5 {
                        stage = nextStage
                        try await Task.sleep(for: .milliseconds(240))
                    }
                }
                hasFinishedGrowing = true
            } catch {
                // Removal cancels the finite sprite sequence.
            }
        }
        .task(id: canReveal) {
            guard canReveal, !hasStartedReveal else { return }
            hasStartedReveal = true
            // Fade the dots and blur the fully grown leaf out before revealing the page.
            withAnimation(.easeInOut(duration: 0.5)) {
                markOpacity = 0
            }
            do {
                try await Task.sleep(for: .milliseconds(500))
                let revealAnimation: Animation = reduceMotion
                    ? .easeInOut(duration: 0.3)
                    : .timingCurve(0.55, 0, 0.17, 1, duration: 1.5)
                withAnimation(revealAnimation) {
                    revealProgress = 1
                }
                try await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 1500))
                hasFinishedReveal = true
            } catch {
                // A scene change must not strand the shell behind an invisible loading screen.
                hasStartedReveal = false
            }
        }
    }
}

private struct BootMark: View {
    let stage: Int
    let leafBlur: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var rotationStart = Date()

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: reduceMotion || scenePhase != .active)) { context in
                Image("BootIconDots")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 256, height: 256)
                    .rotationEffect(.degrees(reduceMotion ? 0 :
                        context.date.timeIntervalSince(rotationStart) * 18))
            }

            Image("WritingLeaf\(stage)")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 144)
                .transaction { $0.animation = nil }
                .blur(radius: leafBlur)
        }
        .overlay(alignment: .bottom) {
            Text("Angrove")
                .font(.custom("LibreBaskerville-Italic", size: 34))
                .foregroundStyle(AngroveTheme.Colors.headingText)
                // Anchor below the artwork without moving the centered leaf and dot grid.
                .alignmentGuide(.bottom) { dimensions in dimensions[.top] - 24 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// A broad, soft opacity ramp gives every vertical position its own fade, including page
/// headers, scroll content and bottom controls, without changing their layout or identity.
@Animatable
private struct BootRevealMask: View {
    var progress: Double
    @AnimatableIgnored var reduceMotion: Bool

    var body: some View {
        Group {
            if progress <= 0 {
                Color.clear
            } else if progress >= 1 {
                Rectangle().fill(AngroveTheme.Colors.primaryBrown)
            } else if reduceMotion {
                Rectangle().fill(AngroveTheme.Colors.primaryBrown).opacity(progress)
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [AngroveTheme.Colors.primaryBrown, .clear],
                        // Spread the fade across 120% of the screen for a gradual reveal.
                        startPoint: UnitPoint(x: 0.5, y: progress * 2.2 - 1.2),
                        endPoint: UnitPoint(x: 0.5, y: progress * 2.2)
                    ))
            }
        }
        .ignoresSafeArea()
    }
}
