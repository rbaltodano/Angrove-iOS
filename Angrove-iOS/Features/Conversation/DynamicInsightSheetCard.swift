//
//  DynamicInsightSheetCard.swift
//  Angrove-iOS
//
//  The Insight card shown when a concept link in a model response is tapped. It matches the
//  loaded card on other pages, but shows a simple loading state while the definition is generated.
//

import SwiftUI

struct DynamicInsightSheetCard: View {
    let word: String
    /// nil while the definition is generating; set once ready.
    let concept: ConceptDefinition?
    let isSaved: Bool
    var isClipped: Bool = false
    var funStatusText: String? = nil
    var onQuote: () -> Void
    var onFork: () -> Void
    var onToggleSaved: () -> Void
    var onToggleClipped: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let concept {
                if concept.isLibraryQuote {
                    libraryQuoteContent(concept)
                } else {
                    loadedHeader
                    InsightDefinitionsContent(definitions: concept.contextualDefinitions)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AngroveTheme.Colors.lightGreen)

                    Text(funStatusText ?? "Generating relevant definition...")
                        .paragraphFont()
                        .foregroundColor(AngroveTheme.Colors.placeholderText)
                        .accessibilityLabel("Generating relevant definition")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .cardGlow()
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var loadedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AngroveTheme.Colors.darkGreen)

            Text(word.capitalized)
                .font(.custom("Figtree-Bold", size: 18))
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            ResponseButtons(
                isSaved: isSaved,
                canQuote: true,
                canFork: false,
                speechText: concept.map { CardSpeech.text(for: $0) },
                tintColor: AngroveTheme.Colors.placeholderText,
                saveTintColor: AngroveTheme.Colors.accentRed,
                onSave: onToggleSaved,
                onQuote: onQuote,
                onFork: onFork
            )
        }
    }

    private func libraryQuoteContent(_ concept: ConceptDefinition) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AngroveTheme.Colors.darkGreen)
                Text(concept.word)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                ResponseButtons(
                    isSaved: isClipped,
                    canQuote: true,
                    canFork: false,
                    speechText: CardSpeech.text(for: concept),
                    quoteAccessibilityLabel: "Ask about passage",
                    tintColor: AngroveTheme.Colors.placeholderText,
                    saveTintColor: AngroveTheme.Colors.accentRed,
                    onSave: onToggleClipped,
                    onQuote: onQuote
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                CardSpeechText(
                    text: concept.semanticDefinition,
                    speechText: CardSpeech.text(for: concept),
                    isItalic: true, isQuoted: true
                )

                if let attribution = concept.libraryAttribution {
                    Text(attribution)
                        .paragraphFont()
                        .lineSpacing(FlowLayout.rowSpacing)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

struct InsightDefinitionsContent: View {
    let definitions: [InsightDefinition]
    var speechExpansionRequest = 0
    var speechCollapseRequest = 0
    var automaticallyCollapsesAfterSpeech = true
    var onSpeechExpansionComplete: (() -> Void)? = nil

    @State private var completedSpeechExpansions: [Int: Set<Int>] = [:]
    @State private var completedRequests: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(definitions.enumerated()), id: \.element.id) { index, definition in
                InsightDefinitionEntry(
                    context: definition.context,
                    meaning: definition.meaning,
                    showsDistinction: definitions.count > 1,
                    speechText: CardSpeech.text(for: definitions),
                    wordStart: CardSpeech.wordStart(for: index, in: definitions),
                    speechExpansionRequest: speechExpansionRequest,
                    speechCollapseRequest: speechCollapseRequest,
                    automaticallyCollapsesAfterSpeech: automaticallyCollapsesAfterSpeech,
                    onSpeechExpansionComplete: {
                        reportSpeechExpansionComplete(at: index, request: speechExpansionRequest)
                    }
                )
            }
        }
    }

    private func reportSpeechExpansionComplete(at index: Int, request: Int) {
        guard request > 0, request == speechExpansionRequest else { return }
        guard !completedRequests.contains(request) else { return }
        var completedIndexes = completedSpeechExpansions[request] ?? []
        completedIndexes.insert(index)
        completedSpeechExpansions[request] = completedIndexes
        guard completedIndexes.count == definitions.count else { return }
        completedRequests.insert(request)
        onSpeechExpansionComplete?()
    }
}

private struct InsightDefinitionEntry: View {
    let context: String
    let meaning: String
    let showsDistinction: Bool
    let speechText: String
    let wordStart: Int
    let speechExpansionRequest: Int
    let speechCollapseRequest: Int
    let automaticallyCollapsesAfterSpeech: Bool
    let onSpeechExpansionComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDistinction && !context.isEmpty {
                CardSpeechText(
                    text: "In regards to \(context)", speechText: speechText,
                    wordStart: wordStart, color: AngroveTheme.Colors.headingText,
                    isItalic: true, isBold: true
                )
            }

            TruncatableParagraph(
                text: meaning, speechText: speechText,
                speechWordStart: wordStart + (showsDistinction && !context.isEmpty
                    ? CardSpeech.words(in: "In regards to \(context)").count : 0),
                speechExpansionRequest: speechExpansionRequest,
                speechCollapseRequest: speechCollapseRequest,
                automaticallyCollapsesAfterSpeech: automaticallyCollapsesAfterSpeech,
                onSpeechExpansionComplete: onSpeechExpansionComplete
            )
        }
    }
}
