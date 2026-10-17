import SwiftUI

struct InsightLibraryCard: View {
    let insight: ConceptDefinition
    let isSaved: Bool
    var maxWidth: CGFloat? = AngroveTheme.Spacing.insightCardMaxWidth
    var shadowOpacity: Double = 0.15
    var onQuote: () -> Void
    var onFork: () -> Void
    var onToggleSaved: () -> Void
    var onClose: (() -> Void)? = nil
    @State private var isConfirmingUnbookmark = false
    @State private var speechExpansionRequest = 0
    @State private var speechCollapseRequest = 0
    @State private var isPreparingSpeech = false
    @State private var hidesActionsForSpeech = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.speechSource) private var speechSource

    private var speechText: String { CardSpeech.text(for: insight) }
    private var isReadingInsight: Bool { ResponseSpeechPlayer.shared.phase(for: speechText) != .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: insight.isLibraryQuote ? "books.vertical" : "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                    .sfSymbolDrawOn()

                Text(insight.isLibraryQuote ? insight.word : insight.word.capitalized)
                    .font(BrandTypography.font("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canQuote: true,
                    canFork: false,
                    speechText: speechText,
                    quoteAccessibilityLabel: insight.isLibraryQuote ? "Ask about passage" : "Quote",
                    tintColor: AngroveTheme.Colors.placeholderText,
                    saveTintColor: AngroveTheme.Colors.accentRed,
                    onSave: handleSaveTapped,
                    onQuote: onQuote,
                    onSpeak: requestSpeechPlayback,
                    onFork: onFork,
                    onClose: onClose
                )
                .opacity(hidesActionsForSpeech && onClose == nil ? 0 : 1)
                .allowsHitTesting(!hidesActionsForSpeech || onClose != nil)
                .accessibilityHidden(hidesActionsForSpeech && onClose == nil)
                .animation(.easeOut(duration: 0.2), value: hidesActionsForSpeech)

            }

            if insight.isLibraryQuote {
                VStack(alignment: .leading, spacing: 8) {
                    TruncatableParagraph(
                        text: insight.semanticDefinition,
                        speechText: speechText,
                        speechExpansionRequest: speechExpansionRequest,
                        speechCollapseRequest: speechCollapseRequest,
                        automaticallyCollapsesAfterSpeech: false,
                        onSpeechExpansionComplete: startSpeechPlayback,
                        collapsedLineLimit: 5,
                        isItalic: true,
                        isQuoted: true
                    )
                    if let attribution = insight.libraryAttribution {
                        Text(attribution)
                            .paragraphFont()
                            .lineSpacing(FlowLayout.rowSpacing)
                            .foregroundStyle(AngroveTheme.Colors.placeholderText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else {
                InsightDefinitionsContent(
                    definitions: insight.contextualDefinitions,
                    speechExpansionRequest: speechExpansionRequest,
                    speechCollapseRequest: speechCollapseRequest,
                    automaticallyCollapsesAfterSpeech: false,
                    onSpeechExpansionComplete: startSpeechPlayback
                )
            }
        }
        .padding(28)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(
            color: AngroveTheme.Colors.dropShadow
                .opacity(shadowOpacity),
            radius: 24,
            x: 0,
            y: 16
        )
        .insightCardSizing(mobileMaxWidth: maxWidth)
        .onChange(of: isReadingInsight) { _, isReading in
            guard !isReading, !isPreparingSpeech, hidesActionsForSpeech else { return }
            withAnimation(.easeOut(duration: 0.2)) { hidesActionsForSpeech = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                speechCollapseRequest += 1
            }
        }
        .alert(insight.isLibraryQuote ? "Unclip passage?" : "Remove bookmark?", isPresented: $isConfirmingUnbookmark) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onToggleSaved()
            }
        } message: {
            Text(insight.isLibraryQuote
                ? "This passage will be removed from Clipped Passages."
                : "This insight may still appear in the current conversation, but it will be removed from your saved insights.")
        }
    }

    private func handleSaveTapped() {
        if isSaved {
            isConfirmingUnbookmark = true
        } else {
            onToggleSaved()
        }
    }

    private func requestSpeechPlayback() {
        guard !isPreparingSpeech, !isReadingInsight else { return }
        isPreparingSpeech = true
        speechExpansionRequest += 1
    }

    private func startSpeechPlayback() {
        guard isPreparingSpeech else { return }
        hidesActionsForSpeech = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard isPreparingSpeech else { return }
            ResponseSpeechPlayer.shared.toggle(
                speechText,
                units: CardSpeech.units(for: speechText),
                source: speechSource
            )
            isPreparingSpeech = false
        }
    }
}
