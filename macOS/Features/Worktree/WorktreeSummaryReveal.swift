import SwiftUI

/// Uses the note's native layout throughout the reveal, so completion never changes typography.
struct WorktreeSummaryReveal: View {
    let text: String
    var width: CGFloat? = nil
    var minimumHeight: CGFloat? = nil
    let onComplete: () -> Void
    var onEdit: () -> Void = {}
    var animatesReveal = true
    var onRevealedWordCountChange: ((Int) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsed: Double = 0

    private var shouldAnimate: Bool { animatesReveal && !reduceMotion }

    var body: some View {
        WorktreeTextEditor(text: .constant(text), isEditing: false,
            fillsWidth: width != nil, maxWidth: width ?? 480,
            color: AngroveTheme.Colors.paragraphText,
            revealElapsed: shouldAnimate ? elapsed : nil,
            onBeginEditing: {}, onEndEditing: {}, onCommit: {}, onEscape: {})
            .allowsHitTesting(false)
            .frame(width: width, alignment: .topLeading)
            .frame(minHeight: minimumHeight, alignment: .topLeading)
            .overlay {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onEdit)
            }
            .task(id: shouldAnimate) {
                let count = WorktreeTextEditor.wordRanges(in: text).count
                guard shouldAnimate else {
                    onRevealedWordCountChange?(count)
                    onComplete()
                    return
                }
                let clock = ContinuousClock()
                let start = clock.now
                let duration = Double(max(0, (count - 1) / 4)) * 0.0275 + 0.55
                var lastCount = -1
                while !Task.isCancelled {
                    let components = start.duration(to: clock.now).components
                    elapsed = Double(components.seconds) + Double(components.attoseconds) / 1e18
                    let visible = min(count, (Int(elapsed / 0.0275) + 1) * 4)
                    if visible != lastCount {
                        onRevealedWordCountChange?(visible)
                        lastCount = visible
                    }
                    if elapsed >= duration { onComplete(); return }
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                }
            }
    }
}
