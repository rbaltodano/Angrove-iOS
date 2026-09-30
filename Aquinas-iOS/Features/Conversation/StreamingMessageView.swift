//
//  StreamingMessageView.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/21/26.
//

import Foundation
import SwiftUI

// MARK: - Streaming Message View

/// Renders the model response body, animated word-by-word, with heading/list formatting and
/// the shared disclaimer/copy footer.
struct StreamingMessageView: View {
    let fullText: String
    let shouldStream: Bool
    let isReceivingStream: Bool
    let usesIncrementalStream: Bool
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let savedInsightIDs: Set<UUID>
    let showsResponseActions: Bool
    let evidenceBasis: ResponseEvidenceBasis?
    var onQuote: ((String) -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    var onBranch: (() -> Void)? = nil
    var onInsightTap: ((String, String) -> Void)? = nil
    var onInlineInsightQuote: ((ConceptDefinition) -> Void)? = nil
    var onInlineInsightFork: ((ConceptDefinition) -> Void)? = nil
    var onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)? = nil
    var onRevealStart: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil
    /// Reports how many words have been revealed so far — lets a parent keep a live word/token
    /// estimate counting up throughout the actual streaming, not just during the thinking phase.
    var onRevealedWordCountChange: ((Int) -> Void)? = nil

    private let segments: [ResponseSegment]
    private let responseWords: [String]
    private let insightLinkSequenceByWordStart: [Int: Int]
    private let streamBatchSize = 4
    private let streamBatchDelay: UInt64 = 55_000_000

    // Process-level cache keyed by response text. parseSegments + tokenize is
    // O(words) and called every time a parent view re-renders (SwiftUI creates new
    // struct values for comparison). Caching makes repeated inits a O(1) lookup.
    private static let parseCache = ParseMemo<(
        segments: [ResponseSegment],
        words: [String],
        insightLinkSequenceByWordStart: [Int: Int]
    )>(countLimit: 64)

    @State private var displayedWords: [String] = []
    @State private var isFinished: Bool = false
    @State private var hasReportedFinish = false
    @State private var hasReportedRevealStart = false
    @State private var showsInsightUnderlines: Bool

    init(
        fullText: String,
        shouldStream: Bool = true,
        isReceivingStream: Bool = false,
        usesIncrementalStream: Bool = false,
        responseTextAlignment: ResponseTextAlignmentOption = .center,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        loadingInsightKey: String? = nil,
        queuedInsightKeys: Set<String> = [],
        savedInsightIDs: Set<UUID> = [],
        showsResponseActions: Bool = true,
        evidenceBasis: ResponseEvidenceBasis? = nil,
        onQuote: ((String) -> Void)? = nil,
        onRegenerate: (() -> Void)? = nil,
        onBranch: (() -> Void)? = nil,
        onInsightTap: ((String, String) -> Void)? = nil,
        onInlineInsightQuote: ((ConceptDefinition) -> Void)? = nil,
        onInlineInsightFork: ((ConceptDefinition) -> Void)? = nil,
        onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)? = nil,
        onRevealStart: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil,
        onRevealedWordCountChange: ((Int) -> Void)? = nil
    ) {
        self.fullText = fullText
        self.shouldStream = shouldStream
        self.isReceivingStream = isReceivingStream
        self.usesIncrementalStream = usesIncrementalStream
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.loadingInsightKey = loadingInsightKey
        self.queuedInsightKeys = queuedInsightKeys
        self.savedInsightIDs = savedInsightIDs
        self.showsResponseActions = showsResponseActions
        self.evidenceBasis = evidenceBasis
        self.onQuote = onQuote
        self.onRegenerate = onRegenerate
        self.onBranch = onBranch
        self.onInsightTap = onInsightTap
        self.onInlineInsightQuote = onInlineInsightQuote
        self.onInlineInsightFork = onInlineInsightFork
        self.onInlineInsightToggleSaved = onInlineInsightToggleSaved
        self.onRevealStart = onRevealStart
        self.onFinish = onFinish
        self.onRevealedWordCountChange = onRevealedWordCountChange

        let cached: (
            segments: [ResponseSegment],
            words: [String],
            insightLinkSequenceByWordStart: [Int: Int]
        )
        if isReceivingStream {
            // An incremental stream changes `fullText` frequently. Parsing and caching every
            // intermediate prefix makes rendering quadratic and retains hundreds of
            // one-off cache entries. The persistent incremental renderer parses prefixes
            // without adding them to this completed-response cache.
            cached = (segments: [], words: [], insightLinkSequenceByWordStart: [:])
        } else {
            cached = Self.parseCache.value(for: fullText) {
                let segs = ResponseParser.parseSegments(from: fullText)
                return (
                    segments: segs,
                    words: segs.flatMap { $0.words },
                    insightLinkSequenceByWordStart: ResponseParser.insightLinkSequenceByWordStart(in: segs)
                )
            }
        }
        self.segments = cached.segments
        self.responseWords = cached.words
        self.insightLinkSequenceByWordStart = cached.insightLinkSequenceByWordStart
        _displayedWords = State(
            initialValue: shouldStream && !usesIncrementalStream ? [] : cached.words
        )
        _isFinished = State(
            initialValue: usesIncrementalStream ? !isReceivingStream : !shouldStream
        )
        _showsInsightUnderlines = State(
            initialValue: !shouldStream || usesIncrementalStream
        )
    }

    var body: some View {
        Group {
            if usesIncrementalStream {
                incrementalResponse
            } else {
                completedResponse
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .task(id: usesIncrementalStream ? "incremental-stream" : fullText) {
            if usesIncrementalStream, !isReceivingStream {
                finishIncrementalResponse()
            } else if shouldStream && !usesIncrementalStream {
                await streamText()
            }
        }
        .onChange(of: isReceivingStream) { wasReceiving, isReceiving in
            guard wasReceiving, !isReceiving else { return }
            finishIncrementalResponse()
        }
        .onChange(of: displayedWords.count) { _, count in
            onRevealedWordCountChange?(count)
        }
    }

    private var incrementalResponse: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 12) {
            LiveFormattedResponseView(
                text: fullText,
                responseTextAlignment: responseTextAlignment,
                responseFont: responseFont,
                conversationFontSize: conversationFontSize,
                loadingInsightKey: loadingInsightKey,
                queuedInsightKeys: queuedInsightKeys,
                onInsightTap: onInsightTap
            )

            if isFinished && showsResponseActions {
                responseFooter
            }
        }
    }

    private var completedResponse: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 12) {

            // Reserve the final response height up front so the card doesn't jump,
            // then reveal content on top of the ghost via streaming progress.
            ZStack(alignment: .top) {
                segmentsView(displayedCount: responseWords.count)
                    .hidden()

                segmentsView(
                    displayedCount: usesIncrementalStream
                        ? responseWords.count
                        : displayedWords.count
                )
                    .textSelection(.enabled)   // let the user highlight / copy the response text
            }
            .animation(
                usesIncrementalStream ? nil : .easeOut(duration: 0.55),
                value: usesIncrementalStream ? responseWords.count : displayedWords.count
            )

            if isFinished && showsResponseActions {
                responseFooter
            }
        }
    }

    private var responseFooter: some View {
        ModelResponseFooter(
            copyText: InlineInsightMarkup.plainText(from: fullText),
            evidenceBasis: evidenceBasis,
            responseTextAlignment: responseTextAlignment,
            onRegenerate: onRegenerate,
            onBranch: onBranch
        )
        .transition(
            .move(edge: .top)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.95))
        )
    }

    private func finishIncrementalResponse() {
        displayedWords = responseWords
        isFinished = true
        guard !hasReportedFinish else { return }
        hasReportedFinish = true
        onFinish?()
    }

    private func segmentsView(displayedCount: Int) -> some View {
        CompletedResponseSegments(
            segments: segments, displayedCount: displayedCount, fullText: fullText,
            responseTextAlignment: responseTextAlignment, responseFont: responseFont,
            conversationFontSize: conversationFontSize, loadingInsightKey: loadingInsightKey,
            queuedInsightKeys: queuedInsightKeys, savedInsightIDs: savedInsightIDs,
            insightLinkSequenceByWordStart: insightLinkSequenceByWordStart,
            showsInsightUnderlines: showsInsightUnderlines, onInsightTap: onInsightTap,
            onInlineInsightQuote: onInlineInsightQuote, onInlineInsightFork: onInlineInsightFork,
            onInlineInsightToggleSaved: onInlineInsightToggleSaved
        )
    }

    // MARK: - Prototype Stream

    private func streamText() async {
        displayedWords = []
        isFinished = false
        showsInsightUnderlines = false
        guard !responseWords.isEmpty else {
            reportRevealStartIfNeeded()
            return
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else { return }
        let words = responseWords

        for batchStart in stride(from: 0, to: words.count, by: streamBatchSize) {
            let batchEnd = min(batchStart + streamBatchSize, words.count)
            reportRevealStartIfNeeded()
            displayedWords.append(contentsOf: words[batchStart..<batchEnd])
            try? await Task.sleep(nanoseconds: streamBatchDelay)
        }

        // Underlines begin only after the final word has completed its reveal.
        try? await Task.sleep(nanoseconds: 550_000_000)
        guard !Task.isCancelled else { return }
        showsInsightUnderlines = true

        let underlineCount = insightLinkSequenceByWordStart.count
        if underlineCount > 0 {
            let underlineDuration = (Double(underlineCount - 1) * 0.1) + 0.42
            try? await Task.sleep(for: .seconds(underlineDuration))
            guard !Task.isCancelled else { return }
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
            isFinished = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onFinish?()
        }
    }

    private func reportRevealStartIfNeeded() {
        guard !hasReportedRevealStart else { return }
        hasReportedRevealStart = true
        onRevealStart?()
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            StreamingMessageView(
                fullText: """
                This is what an ordered list should look like

                1. First item in the ordered list
                2. Second item in the ordered list
                3. Third item in the ordered list

                Then you should be able to type whatever you want after typing an ordered list and still have it all be a part of the same response.
                """,
                shouldStream: false
            )
            .padding()
        }
    }
    .background(AquinasTheme.Colors.canvas)
}
