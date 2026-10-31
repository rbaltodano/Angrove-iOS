import SwiftUI


// MARK: - Model Response Footer

/// Reveals staggered response actions alongside the word-by-word disclaimer.
struct ModelResponseFooter: View {
    let copyText: String
    var spokenUnits: [SpokenUnit] = []
    var evidenceBasis: ResponseEvidenceBasis? = nil
    var responseTextAlignment: ResponseTextAlignmentOption = .left
    var onRegenerate: (() -> Void)? = nil
    var shouldAnimateOnAppear = false
    var onRevealComplete: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.speechSource) private var speechSource
    @Environment(\.responseFeedbackReport) private var feedbackReport
    @State private var showsCopiedConfirmation = false
    @State private var visibleActionCount = 0
    @State private var visibleDisclaimerWords = 0
    @State private var isThumbsDownSelected = false
    @State private var showsFeedbackSheet = false
    @State private var feedbackSent = false
    private var speech: ResponseSpeechPlayer { .shared }

    private var disclaimerWords: [String] {
        String(localized: "AI can make mistakes, verify important details")
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var actionCount: Int {
        2 + (onRegenerate == nil ? 0 : 1) + (feedbackReport == nil ? 0 : 1)
    }

    /// Index of the thumbs down; copy and the optional regenerate come before it.
    private var feedbackIndex: Int { onRegenerate == nil ? 1 : 2 }

    /// Thumbs down appears only when the conversation offers feedback for this response.
    private var thumbsDownButton: some View {
        Button {
            isThumbsDownSelected.toggle()
            feedbackSent = false
            showsFeedbackSheet = isThumbsDownSelected
        } label: {
            actionIcon(isThumbsDownSelected ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                .foregroundStyle(isThumbsDownSelected ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.responseButton)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Bad response"))
        .accessibilityAddTraits(isThumbsDownSelected ? .isSelected : [])
        .modifier(ResponseActionEntrance(
            isVisible: feedbackIndex < visibleActionCount,
            animates: shouldAnimateOnAppear && !reduceMotion
        ))
        .frame(width: 16, height: 16)
    }

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 6) {
            HStack(spacing: 8) {
                actionButton(
                    symbol: showsCopiedConfirmation ? "checkmark" : "doc.on.doc",
                    index: 0,
                    label: showsCopiedConfirmation ? String(localized: "Response copied") : String(localized: "Copy response"),
                    action: copyResponse
                )
                if let onRegenerate {
                    actionButton(
                        symbol: "arrow.trianglehead.2.clockwise", index: 1,
                        label: String(localized: "Regenerate response"), action: onRegenerate
                    )
                }
                if feedbackReport != nil { thumbsDownButton }
                speakButton
                if speech.phase(for: copyText) != .idle {
                    Text("Tap and drag on a conversation block to fast forward and rewind")
                        .font(BrandTypography.font("Figtree-SemiBold", size: 10))
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .blurReplace))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: speech.phase(for: copyText) != .idle)

            FlowLayout(spacing: 2, alignment: responseTextAlignment.textAlignment) {
                ForEach(Array(disclaimerWords.enumerated()), id: \.offset) { index, word in
                    Text(verbatim: word)
                        .font(BrandTypography.font("Figtree-SemiBold", size: 10))
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .opacity(index < visibleDisclaimerWords ? 1 : 0)
                        .offset(y: index < visibleDisclaimerWords ? 0 : 10)
                        .blur(radius: index < visibleDisclaimerWords ? 0 : 3)
                        .accessibilityHidden(index >= visibleDisclaimerWords)
                }
            }
            .frame(minHeight: 20)
            .animation(shouldAnimateOnAppear && !reduceMotion ? ResponseRevealTiming.finishingAnimation : nil, value: visibleDisclaimerWords)
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .task(id: shouldAnimateOnAppear) {
            await revealFooter()
        }
        .sheet(isPresented: $showsFeedbackSheet, onDismiss: {
            // Cancelling the sheet means no feedback was given, so the thumbs down un-selects.
            if !feedbackSent { isThumbsDownSelected = false }
        }) {
            #if os(macOS)
            MacResponseFeedbackSheet(report: feedbackReport?(), onSent: { feedbackSent = true })
            #else
            ResponseFeedbackSheet(report: feedbackReport?(), onSent: { feedbackSent = true })
            #endif
        }
    }

    private func actionButton(symbol: String, index: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionIcon(symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .modifier(ResponseActionEntrance(
            isVisible: index < visibleActionCount,
            animates: shouldAnimateOnAppear && !reduceMotion
        ))
        .frame(width: 14, height: 16)
    }

    /// Reads the response aloud; tapping again while it is preparing or speaking stops it.
    private var speakButton: some View {
        let phase = speech.phase(for: copyText)
        return Button { speech.toggle(copyText, units: spokenUnits, source: speechSource) } label: {
            actionIcon("speaker.wave.2")
                .symbolEffect(.variableColor.iterative, isActive: phase != .idle && !reduceMotion)
                .foregroundStyle(phase == .idle ? AngroveTheme.Colors.responseButton : AngroveTheme.Colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase == .idle ? String(localized: "Read response aloud") : String(localized: "Stop reading"))
        .modifier(ResponseActionEntrance(
            isVisible: (feedbackIndex + (feedbackReport == nil ? 0 : 1)) < visibleActionCount,
            animates: shouldAnimateOnAppear && !reduceMotion
        ))
        .frame(width: 18, height: 16)
    }

    private func actionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .angroveIcon(.medium)
            .foregroundStyle(AngroveTheme.Colors.responseButton)
            .frame(width: 14, height: 16)
            .contentShape(Rectangle())
    }

    private func revealFooter() async {
        guard shouldAnimateOnAppear && !reduceMotion else {
            visibleActionCount = actionCount
            visibleDisclaimerWords = disclaimerWords.count
            onRevealComplete?()
            return
        }
        visibleActionCount = 0
        visibleDisclaimerWords = 0
        do {
            // Merge both schedules so their first visible elements share the same frame.
            let actionEvents = (1...actionCount).map {
                (time: Double($0 - 1) * ResponseRevealTiming.actionStagger, actions: $0, words: 0)
            }
            let wordEvents = stride(from: 0, to: disclaimerWords.count, by: 4).enumerated().map {
                (time: Double($0.offset) * 0.055, actions: 0, words: min($0.element + 4, disclaimerWords.count))
            }
            let events = (actionEvents + wordEvents).sorted { $0.time < $1.time }
            var elapsed = 0.0
            for event in events {
                if event.time > elapsed {
                    try await Task.sleep(for: .seconds(event.time - elapsed))
                }
                try Task.checkCancellation()
                visibleActionCount = max(visibleActionCount, event.actions)
                visibleDisclaimerWords = max(visibleDisclaimerWords, event.words)
                elapsed = event.time
            }
            let settleTime = max(
                (actionEvents.last?.time ?? 0) + ResponseRevealTiming.actionDuration,
                (wordEvents.last?.time ?? 0) + ResponseRevealTiming.finishingDuration
            )
            try await Task.sleep(for: .seconds(settleTime - elapsed))
            try Task.checkCancellation()
            onRevealComplete?()
        } catch {
            // A removed or regenerated answer cannot reveal another answer's composer.
        }
    }

    private func copyResponse() {
        PlatformClipboard.copy(copyText)
        withAnimation(.springBouncy) { showsCopiedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showsCopiedConfirmation = false }
        }
    }
}

// MARK: - Shared Response Buttons

/// Shared action row for model responses and insight cards.
