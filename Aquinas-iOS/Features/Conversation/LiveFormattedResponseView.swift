import SwiftUI

// MARK: - Persistent incremental-stream formatter

/// The same view hierarchy renders both the live prose and its annotated result.
/// Annotation changes token metadata in place; it never swaps the response body.
struct LiveFormattedResponseView: View {
    let text: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?

    var body: some View {
        let blocks = LiveResponseBlock.parse(text)
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                LiveResponseBlockView(
                    block: block,
                    sourceResponseBlock: text,
                    responseTextAlignment: responseTextAlignment,
                    responseFont: responseFont,
                    conversationFontSize: conversationFontSize,
                    loadingInsightKey: loadingInsightKey,
                    queuedInsightKeys: queuedInsightKeys,
                    onInsightTap: onInsightTap
                )
                .padding(.top, spacingBeforeBlock(at: index, in: blocks))
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .textSelection(.enabled)
    }

    private func spacingBeforeBlock(at index: Int, in blocks: [LiveResponseBlock]) -> CGFloat {
        guard index > 0 else { return 0 }
        return blocks[index].isParagraph && blocks[index - 1].isParagraph ? 24 : 16
    }
}

private struct LiveResponseBlockView: View {
    let block: LiveResponseBlock
    let sourceResponseBlock: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?

    var body: some View {
        switch block.kind {
        case .paragraph(let text):
            LiveTokenFlow(
                source: text,
                sourceResponseBlock: sourceResponseBlock,
                font: responseFont.textFont(size: conversationFontSize),
                color: AquinasTheme.Colors.bodyText,
                allowsInlineMarkdown: true,
                spacing: 4.5,
                responseTextAlignment: responseTextAlignment,
                annotationSequenceStart: block.annotationSequenceStart,
                loadingInsightKey: loadingInsightKey,
                queuedInsightKeys: queuedInsightKeys,
                onInsightTap: onInsightTap,
                citationFont: responseFont.textFont(size: conversationFontSize)
            )

        case .heading(let level, let text):
            LiveTokenFlow(
                source: text,
                sourceResponseBlock: sourceResponseBlock,
                font: headingFont(level: level),
                color: AquinasTheme.Colors.headingText,
                allowsInlineMarkdown: false,
                spacing: 5,
                responseTextAlignment: responseTextAlignment,
                annotationSequenceStart: block.annotationSequenceStart,
                loadingInsightKey: loadingInsightKey,
                queuedInsightKeys: queuedInsightKeys,
                onInsightTap: onInsightTap,
                citationFont: responseFont.textFont(size: conversationFontSize)
            )

        case .orderedList(let items):
            listView(items: items, marker: { "\($0 + 1)." })

        case .unorderedList(let items):
            listView(items: items, marker: { _ in "•" })
        }
    }

    private func listView(
        items: [String],
        marker: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items.enumerated(), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text(marker(index))
                        .font(responseFont.textFont(size: conversationFontSize))
                        .foregroundColor(AquinasTheme.Colors.bodyText)
                        .frame(minWidth: 22, alignment: .trailing)

                    LiveTokenFlow(
                        source: item,
                        sourceResponseBlock: sourceResponseBlock,
                        font: responseFont.textFont(size: conversationFontSize),
                        color: AquinasTheme.Colors.bodyText,
                        allowsInlineMarkdown: true,
                        spacing: 4.5,
                        responseTextAlignment: responseTextAlignment,
                        annotationSequenceStart: annotationSequenceStart(
                            forItemAt: index,
                            in: items
                        ),
                        loadingInsightKey: loadingInsightKey,
                        queuedInsightKeys: queuedInsightKeys,
                        onInsightTap: onInsightTap,
                        citationFont: responseFont.textFont(size: conversationFontSize)
                    )
                }
            }
        }
    }

    private func annotationSequenceStart(
        forItemAt index: Int,
        in items: [String]
    ) -> Int {
        return block.annotationSequenceStart
            + items.prefix(index).reduce(0) {
                $0 + LiveResponseBlock.insightCount(in: $1)
            }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            .custom(
                "LibreBaskerville-Regular",
                size: conversationFontSize.pointSize + 8
            )
        case 2:
            .custom(
                "LibreBaskerville-Regular",
                size: conversationFontSize.pointSize + 4
            )
        default:
            .custom(
                "Figtree-Bold",
                size: conversationFontSize.pointSize + 1
            )
        }
    }
}

private struct LiveTokenFlow: View {
    let source: String
    let sourceResponseBlock: String
    let font: Font
    let color: Color
    let allowsInlineMarkdown: Bool
    let spacing: CGFloat
    let responseTextAlignment: ResponseTextAlignmentOption
    let annotationSequenceStart: Int
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?
    let citationFont: Font

    @State private var visibleTokenCount = 0
    @Environment(\.openURL) private var openURL

    private static let tokenMemo = ParseMemo<[LiveResponseToken]>(countLimit: 256)

    private var tokens: [LiveResponseToken] {
        Self.tokenMemo.value(for: "\(annotationSequenceStart)\u{1F}\(source)") {
            LiveResponseToken.parse(
                source,
                annotationSequenceStart: annotationSequenceStart
            )
        }
    }

    var body: some View {
        FlowLayout(
            spacing: spacing,
            alignment: responseTextAlignment.textAlignment,
            justified: allowsInlineMarkdown && responseTextAlignment == .center
        ) {
            ForEach(tokens) { token in
                tokenView(token)
                    .opacity(token.id < visibleTokenCount ? 1 : 0)
                    .offset(y: token.id < visibleTokenCount ? 0 : 10)
                    .blur(radius: token.id < visibleTokenCount ? 0 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .onAppear {
            revealNewTokens(animated: true)
        }
        .onChange(of: tokens.count) { _, _ in
            revealNewTokens(animated: true)
        }
    }

    @ViewBuilder
    private func tokenView(_ token: LiveResponseToken) -> some View {
        if let citation = token.citation {
            ResponseCitationChip(link: citation, textFont: citationFont)
        } else if let annotation = token.annotation {
            let insightKey = insightLoadingKey(for: annotation.title)
            let isLoading = loadingInsightKey == insightKey
            let isQueued = queuedInsightKeys.contains(insightKey)
            Button {
                if let onInsightTap {
                    onInsightTap(annotation.title, sourceResponseBlock)
                } else {
                    openURL(annotation.url)
                }
            } label: {
                StableAnnotatedTokenLabel(
                    word: token.source,
                    leadingPunctuation: annotation.leadingPunctuation,
                    trailingPunctuation: annotation.trailingPunctuation,
                    font: font,
                    isLoading: isLoading,
                    isQueued: isQueued,
                    isVisible: token.id < visibleTokenCount,
                    animationDelay: Double(annotation.sequence) * 0.1
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isQueued)
        } else {
            Self.styledText(
                for: token.source,
                baseFont: font,
                allowsInlineMarkdown: allowsInlineMarkdown
            )
            .foregroundColor(color)
            .responseWordMenu(token: token.source) {
                .sourceToken(source: source, index: token.rawIndex)
            }
        }
    }

    private func revealNewTokens(animated: Bool) {
        // Source chips carry negative ids and are not part of the word reveal.
        let wordCount = tokens.lazy.filter { $0.id >= 0 }.count
        guard visibleTokenCount < wordCount else {
            visibleTokenCount = min(visibleTokenCount, wordCount)
            return
        }

        if animated {
            withAnimation(.easeOut(duration: 0.55)) {
                visibleTokenCount = wordCount
            }
        } else {
            visibleTokenCount = wordCount
        }
    }

    private func insightLoadingKey(for title: String) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\n\(sourceResponseBlock)"
    }

    private static func styledText(
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

    private static func inlineMarkdown(
        from token: String
    ) -> (
        text: String,
        trailingPunctuation: String,
        isBold: Bool,
        isItalic: Bool
    )? {
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

private struct StableAnnotatedTokenLabel: View {
    let word: String
    let leadingPunctuation: String
    let trailingPunctuation: String
    let font: Font
    let isLoading: Bool
    let isQueued: Bool
    let isVisible: Bool
    let animationDelay: Double

    var body: some View {
        // This invisible regular-weight token owns layout. Annotation is an
        // overlay, so bolding and the tap target cannot rewrap the paragraph.
        Text(leadingPunctuation + word + trailingPunctuation)
            .font(font)
            .foregroundStyle(.clear)
            .overlay(alignment: .leading) {
            if isLoading {
                HStack(spacing: 0) {
                    Text(leadingPunctuation)
                    Text(word).bold()
                    Text(trailingPunctuation)
                }
                .font(font)
                .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                .modifier(
                    ThinkingShimmer(
                        isActive: true,
                        color: AquinasTheme.Colors.lightGreen
                    )
                )
            } else {
                HStack(spacing: 0) {
                    Text(leadingPunctuation)
                        .font(font)
                        .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                    AnimatedInsightUnderlineText(
                        text: word,
                        font: font,
                        color: AquinasTheme.Colors.secondaryMuted,
                        isVisible: isVisible,
                        animationDelay: animationDelay,
                        underlineOpacity: 1
                    )
                    .modifier(
                        QueuedWorkBreatheModifier(
                            isQueued: isQueued
                        )
                    )
                    Text(trailingPunctuation)
                        .font(font)
                        .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                }
            }
            }
            .contentShape(Rectangle())
    }
}
