import SwiftUI

/// The conversation's completed-answer reveal, followed by the canvas's normal editable note.
struct WorktreeSummaryReveal: View {
    let text: String
    let onComplete: () -> Void
    var onEdit: () -> Void = {}
    var animatesReveal = true
    var onRevealedWordCountChange: ((Int) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool { animatesReveal && !reduceMotion }

    var body: some View {
        StreamingMessageView(fullText: text, shouldStream: shouldAnimate,
            responseTextAlignment: .left, responseFont: .sans, conversationFontSize: .medium,
            showsResponseActions: false,
            onBodyRevealComplete: onComplete,
            onRevealedWordCountChange: onRevealedWordCountChange)
            .frame(width: 480, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            .task(id: shouldAnimate) {
                if !shouldAnimate { onComplete() }
            }
    }
}
