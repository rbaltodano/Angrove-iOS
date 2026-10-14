import SwiftUI

// MARK: - Persistent incremental-stream formatter

/// The same view hierarchy renders both the live prose and its annotated result.
/// Annotation changes token metadata in place; it never swaps the response body.
struct LiveFormattedResponseView: View {
    let text: String
    var animatesReveal = true
    var isReceivingStream = true
    var onBodyRevealComplete: (() -> Void)? = nil
    var onRevealedWordCountChange: ((Int) -> Void)? = nil
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?

    @State private var progress = LiveResponseRevealProgress()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let blocks = LiveResponseBlock.parse(text)
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                LiveResponseBlockView(
                    block: block,
                    animatesReveal: animatesReveal,
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
        .onPreferenceChange(LiveResponseRevealProgressKey.self) {
            progress = $0
            onRevealedWordCountChange?($0.visible)
        }
        .task(id: LiveResponseRevealCompletion(text: text, receiving: isReceivingStream, progress: progress)) {
            guard !isReceivingStream, progress.visible == progress.total,
                  progress.total > 0 || text.isEmpty else { return }
            if animatesReveal && !reduceMotion { try? await Task.sleep(for: .milliseconds(550)) }
            guard !Task.isCancelled else { return }
            onBodyRevealComplete?()
        }
    }

    private func spacingBeforeBlock(at index: Int, in blocks: [LiveResponseBlock]) -> CGFloat {
        guard index > 0 else { return 0 }
        return blocks[index].isParagraph && blocks[index - 1].isParagraph ? 24 : 16
    }
}

private struct LiveResponseBlockView: View {
    let block: LiveResponseBlock
    let animatesReveal: Bool
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
                animatesReveal: animatesReveal,
                sourceResponseBlock: sourceResponseBlock,
                font: responseFont.textFont(size: conversationFontSize),
                color: AngroveTheme.Colors.bodyText,
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
                animatesReveal: animatesReveal,
                sourceResponseBlock: sourceResponseBlock,
                font: headingFont(level: level),
                color: AngroveTheme.Colors.headingText,
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
                        .foregroundColor(AngroveTheme.Colors.bodyText)
                        .frame(minWidth: 22, alignment: .trailing)

                    LiveTokenFlow(
                        source: item,
                        animatesReveal: animatesReveal,
                        sourceResponseBlock: sourceResponseBlock,
                        font: responseFont.textFont(size: conversationFontSize),
                        color: AngroveTheme.Colors.bodyText,
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
            BrandTypography.font(
                "LibreBaskerville-Regular",
                fixedSize: conversationFontSize.pointSize + 8
            )
        case 2:
            BrandTypography.font(
                "LibreBaskerville-Regular",
                fixedSize: conversationFontSize.pointSize + 4
            )
        default:
            BrandTypography.font(
                "Figtree-Bold",
                fixedSize: conversationFontSize.pointSize + 1
            )
        }
    }
}

private struct LiveTokenFlow: View {
    let source: String
    let animatesReveal: Bool
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            justified: allowsInlineMarkdown && responseTextAlignment == .center,
            measurementKey: tokens.filter { $0.annotation != nil }.count
        ) {
            ForEach(tokens) { token in
                tokenView(token)
                    .opacity(token.id < visibleTokenCount ? 1 : 0)
                    .offset(y: token.id < visibleTokenCount ? 0 : 10)
                    .blur(radius: token.id < visibleTokenCount ? 0 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .preference(key: LiveResponseRevealProgressKey.self,
                    value: LiveResponseRevealProgress(visible: min(visibleTokenCount, wordCount), total: wordCount))
        .task(id: wordCount) {
            guard animatesReveal && !reduceMotion else { visibleTokenCount = wordCount; return }
            visibleTokenCount = min(visibleTokenCount, wordCount)
            while visibleTokenCount < wordCount {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.55)) {
                    visibleTokenCount = min(visibleTokenCount + 4, wordCount)
                }
                do { try await Task.sleep(for: .milliseconds(27.5)) } catch { return }
            }
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

    private var wordCount: Int { tokens.lazy.filter { $0.id >= 0 }.count }

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
        // Measure the same bold glyphs used by the annotation overlay. Measuring
        // regular weight gives the overlay too little room and truncates links.
        Text(leadingPunctuation + word + trailingPunctuation)
            .font(font.bold())
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.clear)
            .overlay(alignment: .leading) {
            if isLoading {
                HStack(spacing: 0) {
                    Text(leadingPunctuation)
                    Text(word).bold()
                    Text(trailingPunctuation)
                }
                .fixedSize(horizontal: true, vertical: true)
                .font(font)
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .modifier(
                    ThinkingShimmer(
                        isActive: true,
                        color: AngroveTheme.Colors.lightGreen
                    )
                )
            } else {
                HStack(spacing: 0) {
                    Text(leadingPunctuation)
                        .font(font)
                        .foregroundColor(AngroveTheme.Colors.lightGreen)
                    AnimatedInsightUnderlineText(
                        text: word,
                        font: font,
                        color: AngroveTheme.Colors.lightGreen,
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
                        .foregroundColor(AngroveTheme.Colors.lightGreen)
                }
                .fixedSize(horizontal: true, vertical: true)
            }
            }
            .contentShape(Rectangle())
    }
}

struct LiveResponseRevealProgress: Equatable {
    var visible = 0
    var total = 0
}

private struct LiveResponseRevealCompletion: Equatable {
    let text: String
    let receiving: Bool
    let progress: LiveResponseRevealProgress
}

private struct LiveResponseRevealProgressKey: PreferenceKey {
    static let defaultValue = LiveResponseRevealProgress()
    static func reduce(value: inout LiveResponseRevealProgress, nextValue: () -> LiveResponseRevealProgress) {
        let next = nextValue()
        value.visible += next.visible
        value.total += next.total
    }
}
