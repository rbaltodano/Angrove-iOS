import SwiftUI

struct CompletedResponseSegments: View {
    let segments: [ResponseSegment]
    let displayedCount: Int
    let fullText: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let savedInsightIDs: Set<UUID>
    let insightLinkSequenceByWordStart: [Int: Int]
    let showsInsightUnderlines: Bool
    let onInsightTap: ((String, String) -> Void)?
    let onInlineInsightQuote: ((ConceptDefinition) -> Void)?
    let onInlineInsightFork: ((ConceptDefinition) -> Void)?
    let onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)?
    @Environment(\.openURL) private var openURL

    // MARK: - Segment renderer

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                segmentView(segment: segment, displayedCount: displayedCount)
                    .padding(.top, spacingBeforeSegment(at: index))
            }
        }
    }

    private func spacingBeforeSegment(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if segments[index].isParagraph, segments[index - 1].isParagraph {
            return 24
        }
        return segments[index].isInsight || segments[index - 1].isInsight ? 24 : 16
    }

    @ViewBuilder
    private func segmentView(segment: ResponseSegment, displayedCount: Int) -> some View {
        let available = max(0, min(segment.wordCount, displayedCount - segment.wordStart))
        if available > 0 {
            switch segment.kind {
            case .paragraph:
                // Lay out the FULL paragraph so word positions are final from the
                // start; reveal up to `available` via opacity instead of inserting
                // words (which would re-center each row and slide text sideways).
                wordFlow(
                    words: segment.words,
                    visibleCount: available,
                    globalWordStart: segment.wordStart
                )

            case .heading(let level):
                headingFlow(
                    words: segment.words,
                    visibleCount: available,
                    level: level,
                    globalWordStart: segment.wordStart
                )

            case .orderedList(let items):
                listView(
                    items: items,
                    allWords: segment.words,
                    segmentWordStart: segment.wordStart,
                    itemOffsets: segment.itemWordOffsets,
                    available: available,
                    marker: { "\($0 + 1)." }
                )

            case .unorderedList(let items):
                listView(
                    items: items,
                    allWords: segment.words,
                    segmentWordStart: segment.wordStart,
                    itemOffsets: segment.itemWordOffsets,
                    available: available,
                    marker: { _ in "•" }
                )

            case .insight(let insight):
                InsightLibraryCard(
                    insight: insight,
                    isSaved: savedInsightIDs.contains(insight.id),
                    maxWidth: 315,
                    shadowOpacity: 0.075,
                    onQuote: { onInlineInsightQuote?(insight) },
                    onFork: { onInlineInsightFork?(insight) },
                    onToggleSaved: { onInlineInsightToggleSaved?(insight) }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.glideFadeUp)
            }
        }
    }

    @ViewBuilder
    private func headingFlow(
        words: [String],
        visibleCount: Int,
        level: Int,
        globalWordStart: Int
    ) -> some View {
        FlowLayout(spacing: 5, alignment: responseTextAlignment.textAlignment) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                styledText(for: word, baseFont: headingFont(for: level), allowsInlineMarkdown: false)
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .responseWordMenu(token: word) {
                        displayedTokenLocation(forWordAt: globalWordStart + idx)
                    }
                    .opacity(idx < visibleCount ? 1 : 0)
                    .offset(y: idx < visibleCount ? 0 : 10)
                    .blur(radius: idx < visibleCount ? 0 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .custom("LibreBaskerville-Regular", size: conversationFontSize.pointSize + 8)
        case 2:
            return .custom("LibreBaskerville-Regular", size: conversationFontSize.pointSize + 4)
        default:
            return .custom("Figtree-Bold", size: conversationFontSize.pointSize + 1)
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private func listView(
        items: [String],
        allWords: [String],
        segmentWordStart: Int,
        itemOffsets: [Int],
        available: Int,
        marker: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                let itemStart = itemOffsets[index]
                let itemEnd   = index + 1 < itemOffsets.count ? itemOffsets[index + 1] : allWords.count
                let itemWords = Array(allWords[itemStart..<itemEnd])

                HStack(alignment: .top, spacing: 10) {
                    Text(marker(index))
                        .font(responseFont.textFont(size: conversationFontSize))
                        .foregroundColor(AquinasTheme.Colors.bodyText)
                        .frame(minWidth: 22, alignment: .trailing)
                        .opacity(available > itemStart ? 1 : 0)

                    // Full item is laid out immediately; words reveal in place.
                    wordFlow(
                        words: itemWords,
                        visibleCount: max(0, available - itemStart),
                        globalWordStart: segmentWordStart + itemStart
                    )
                }
            }
        }
    }

    // MARK: - Word flow (unchanged)

    @ViewBuilder
    private func wordFlow(
        words: [String],
        visibleCount: Int,
        globalWordStart: Int
    ) -> some View {
        FlowLayout(
            alignment: responseTextAlignment.textAlignment,
            justified: responseTextAlignment == .center,
            // Define turns a plain word into a wider Insight link in place.
            measurementKey: words.lazy.filter { $0.contains("](") }.count
        ) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                let globalWordIndex = globalWordStart + idx
                let underlineDelay = insightLinkSequenceByWordStart[globalWordIndex]
                    .map { Double($0) * 0.1 } ?? 0
                styledWord(
                    word,
                    globalWordIndex: globalWordIndex,
                    isVisible: idx < visibleCount && showsInsightUnderlines,
                    underlineDelay: underlineDelay
                )
                // All words are laid out up front, so positions are final; reveal
                // each word with a slow fade + upward drift. The offset is purely
                // visual (doesn't affect layout), so positions never shift.
                .opacity(idx < visibleCount ? 1 : 0)
                .offset(y: idx < visibleCount ? 0 : 10)
                .blur(radius: idx < visibleCount ? 0 : 3)
            }
        }
    }

    @ViewBuilder
    private func styledWord(
        _ word: String,
        globalWordIndex: Int,
        isVisible: Bool,
        underlineDelay: Double
    ) -> some View {
        if let link = ParsedInsightLink(token: word), link.isCitation {
            ResponseCitationChip(
                link: link,
                textFont: responseFont.textFont(size: conversationFontSize)
            )
        } else if let link = ParsedInsightLink(token: word) {
            let isLoading = loadingInsightKey == insightLoadingKey(
                for: link.title,
                sourceResponseBlock: fullText
            )
            let isQueued = queuedInsightKeys.contains(
                insightLoadingKey(
                    for: link.title,
                    sourceResponseBlock: fullText
                )
            )
            Button(action: {
                if let onInsightTap {
                    onInsightTap(link.title, fullText)
                } else {
                    openURL(link.url)
                }
            }) {
                insightLinkLabel(
                    link: link,
                    isLoading: isLoading,
                    isQueued: isQueued,
                    isVisible: isVisible,
                    underlineDelay: underlineDelay
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isQueued)
        } else {
            styledText(
                for: word,
                baseFont: responseFont.textFont(size: conversationFontSize),
                allowsInlineMarkdown: true
            )
            .foregroundColor(AquinasTheme.Colors.bodyText)
            .responseWordMenu(token: word) {
                displayedTokenLocation(forWordAt: globalWordIndex)
            }
        }
    }

    /// An inline Insight card occupies one slot in the flat word array but is not a word of the
    /// response text, so it is left out of the index Define resolves against.
    private func displayedTokenLocation(forWordAt globalWordIndex: Int) -> DefinedTermMarkup.Location {
        let cardsBefore = segments.lazy.filter { $0.isInsight && $0.wordStart < globalWordIndex }.count
        return .displayedToken(globalWordIndex - cardsBefore)
    }

    @ViewBuilder
    private func insightLinkLabel(
        link: ParsedInsightLink,
        isLoading: Bool,
        isQueued: Bool,
        isVisible: Bool,
        underlineDelay: Double
    ) -> some View {
        if isLoading {
            let label = HStack(spacing: 0) {
                Text(link.leadingPunctuation)
                Text(link.title).bold()
                Text(link.trailingPunctuation)
            }
            .font(responseFont.textFont(size: conversationFontSize))
            .padding(.horizontal, 2)
            .contentShape(Rectangle())

            label.modifier(
                ThinkingShimmer(
                    isActive: true,
                    color: AquinasTheme.Colors.lightGreen
                )
            )
        } else {
            HStack(spacing: 0) {
                Text(link.leadingPunctuation)
                    .font(responseFont.textFont(size: conversationFontSize))
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                AnimatedInsightUnderlineText(
                    text: link.title,
                    font: responseFont.textFont(size: conversationFontSize),
                    color: AquinasTheme.Colors.secondaryMuted,
                    isVisible: isVisible,
                    animationDelay: underlineDelay,
                    underlineOpacity: 1
                )
                .modifier(
                    QueuedWorkBreatheModifier(
                        isQueued: isQueued
                    )
                )
                Text(link.trailingPunctuation)
                    .font(responseFont.textFont(size: conversationFontSize))
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
    }

    private func insightLoadingKey(for text: String, sourceResponseBlock: String?) -> String {
        "\(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\n\(sourceResponseBlock ?? "")"
    }

    private func styledText(
        for token: String,
        baseFont: Font,
        allowsInlineMarkdown: Bool
    ) -> Text {
        guard allowsInlineMarkdown,
              let markdown = inlineMarkdown(from: token) else {
            return Text(token).font(baseFont)
        }

        var font = baseFont
        if markdown.isBold { font = font.bold() }
        if markdown.isItalic { font = font.italic() }

        var attributed = AttributedString(markdown.text)
        attributed.font = font
        if !markdown.trailingPunctuation.isEmpty {
            var trailing = AttributedString(markdown.trailingPunctuation)
            trailing.font = baseFont
            attributed += trailing
        }
        return Text(attributed)
    }

    private func inlineMarkdown(from token: String) -> (text: String, trailingPunctuation: String, isBold: Bool, isItalic: Bool)? {
        let punctuation = token.reversed().prefix { ".,!?;:".contains($0) }
        let trailing = String(punctuation.reversed())
        let core = String(token.dropLast(trailing.count))
        if core.hasPrefix("**"), core.hasSuffix("**"), core.count > 4 {
            return (String(core.dropFirst(2).dropLast(2)), trailing, true, false)
        }
        if core.hasPrefix("*"), core.hasSuffix("*"), core.count > 2 {
            return (String(core.dropFirst().dropLast()), trailing, false, true)
        }
        return nil
    }

}
