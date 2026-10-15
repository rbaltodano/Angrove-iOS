import Observation
import SwiftUI

/// Keeps the departing page mounted until it is hidden, then reveals the latest destination.
@MainActor
@Observable
final class MacPageTransition {
    static let offset: CGFloat = 8

    private(set) var isVisible = true
    private(set) var canRevealContent = true
    private(set) var isTransitioning = false
    /// Model Controls tuck away as a page departs and return once the next page has arrived.
    private(set) var showsControls = true
    private(set) var destination: MacWorkspacePage?
    @ObservationIgnored private var pendingNavigation: (@MainActor () -> Void)?
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    private let fadeDuration: TimeInterval
    private let pauseDuration: TimeInterval

    init(fadeDuration: TimeInterval = 0.25, pauseDuration: TimeInterval = 0.15) {
        self.fadeDuration = fadeDuration
        self.pauseDuration = pauseDuration
    }

    func navigate(to page: MacWorkspacePage, apply: @escaping @MainActor () -> Void) {
        let isDeparting = isTransitioning && !isVisible && pendingNavigation != nil
        destination = page
        pendingNavigation = apply
        // A new request during departure replaces the destination without restarting the exit.
        guard !isDeparting else { return }
        transitionTask?.cancel()
        isTransitioning = true
        transitionTask = Task {
            withAnimation(.easeInOut(duration: fadeDuration)) { isVisible = false }
            withAnimation(.easeIn(duration: 0.26)) { showsControls = false }
            do {
                try await Task.sleep(for: .seconds(fadeDuration + pauseDuration))
                try Task.checkCancellation()
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    canRevealContent = false
                    let navigation = pendingNavigation
                    pendingNavigation = nil
                    navigation?()
                }
                // Let the newly mounted page lay out at the hidden, lowered position first.
                try await Task.sleep(for: .milliseconds(16))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: fadeDuration)) {
                    isVisible = true
                    canRevealContent = true
                }
                withAnimation(.springStandard) { showsControls = true }
                try await Task.sleep(for: .seconds(fadeDuration))
                try Task.checkCancellation()
                isTransitioning = false
                destination = nil
                transitionTask = nil
            } catch { }
        }
    }

    func cancel() {
        transitionTask?.cancel()
        transitionTask = nil
        pendingNavigation = nil
        destination = nil
        isTransitioning = false
        isVisible = true
        canRevealContent = true
        showsControls = true
    }
}

/// The fade and lowered offset a departing or arriving page takes. Pages that keep Model Controls
/// outside their fade apply it themselves, so the controls animate on their own timeline.
struct MacPageFade: Equatable {
    var isVisible = true
    var offset: CGFloat = 0
}

extension EnvironmentValues {
    @Entry var macPageFade = MacPageFade()
    @Entry var macPageControlsVisible = true
}

extension View {
    func macPageFade() -> some View { modifier(MacPageFadeModifier()) }
}

private struct MacPageFadeModifier: ViewModifier {
    @Environment(\.macPageFade) private var fade

    func body(content: Content) -> some View {
        content
            .opacity(fade.isVisible ? 1 : 0)
            .offset(y: fade.offset)
    }
}
