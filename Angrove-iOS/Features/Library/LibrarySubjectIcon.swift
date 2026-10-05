import SwiftUI

/// An SF Symbol that coordinates the existing source-row entrance.
struct LibrarySubjectIcon: View {
    let subject: LibrarySubject
    var symbolSize: CGFloat = 15
    var shelfIsVisible: Bool = true
    var entranceDelay: Duration? = nil
    /// Mirrors the entrance fade, so neighbouring content can enter in step with the icon.
    var onRevealChange: ((Bool) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isBootRevealComplete) private var isBootRevealComplete
    @State private var isVisible = false
    @State private var isRevealed = false

    private var shouldPlay: Bool {
        isVisible && shelfIsVisible && scenePhase == .active && isBootRevealComplete
    }

    var body: some View {
        Image(systemName: subject.systemImage)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .accessibilityHidden(true)
        .opacity(reduceMotion || entranceDelay == nil || isRevealed ? 1 : 0)
        .onScrollVisibilityChange(threshold: 0.5) { isVisible = $0 }
        .task(id: shouldPlay && !reduceMotion) {
            guard entranceDelay != nil else { return }
            withTransaction(Transaction(animation: nil)) {
                isRevealed = false
                onRevealChange?(false)
            }
            guard shouldPlay, !reduceMotion else { return }
            do {
                try await Task.sleep(for: entranceDelay ?? .zero)
                // Give SwiftUI a frame to commit the hidden starting state.
                try await Task.sleep(for: .milliseconds(16))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRevealed = true
                    onRevealChange?(true)
                }
            } catch {
                // Viewport exit cancels the pending fade; re-entry restarts the sequence.
            }
        }
    }
}
