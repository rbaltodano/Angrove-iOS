import SwiftUI

// Shared transition shorthand.
extension AnyTransition {
    static var streamedTextFade: AnyTransition {
        .opacity.animation(.easeInOut(duration: 0.55))
    }

    static var glideFadeUp: AnyTransition {
        .modifier(active: GlideFadeModifier(isActive: true), identity: GlideFadeModifier(isActive: false))
        .animation(.easeOut(duration: 0.22))
    }

    static var blurSlideUp: AnyTransition {
        glideFadeUp
    }

    static var blurredTitleReplacement: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: GlideFadeModifier(isActive: true),
                identity: GlideFadeModifier(isActive: false)
            )
            .animation(.easeOut(duration: 0.5)),
            removal: .modifier(
                active: GlideFadeModifier(isActive: true),
                identity: GlideFadeModifier(isActive: false)
            )
            .animation(.easeInOut(duration: 0.5))
        )
    }
}

/// Lightweight entrance effect for streamed words.
struct GlideFadeModifier: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 3 : 0)
            .opacity(isActive ? 0 : 1)
            .offset(y: isActive ? 14 : 0)
            .scaleEffect(isActive ? 0.95 : 1)
    }
}

/// Compatibility name for older response-card code.
typealias BlurFadeModifier = GlideFadeModifier


// MARK: - Blur-fade transition

private struct NavIconBlurFade: ViewModifier {
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
    }
}

extension AnyTransition {
    /// Fades in/out while blurring from 8 pt → 0 (insertion) and 0 → 8 pt (removal).
    static var blurFade: AnyTransition {
        .modifier(
            active:   NavIconBlurFade(opacity: 0, blur: 8),
            identity: NavIconBlurFade(opacity: 1, blur: 0)
        )
    }
}

extension AnyTransition {
    /// The blur-and-fade a deleted conversation card leaves with, and a new card arrives with.
    static var blurFadeShrink: AnyTransition {
        .blurFade.combined(with: .scale(scale: 0.96))
    }
}
