//
//  ModelResponse.swift
//  Angrove-iOS
//
//  Created by Ryan on 4/30/26.
//

import Foundation
import SwiftUI

// MARK: - Model Response Card

/// Response bubble with a temporary thinking state, collapsible title, streamed body, and action icons.
struct ModelResponseCard: View {
    let title: String
    let fullText: String
    let shouldAnimateOnAppear: Bool
    let showsThinkingIntro: Bool
    let isAwaitingResponse: Bool
    let isReceivingStream: Bool
    let isQueuedForModel: Bool
    let usesIncrementalStream: Bool
    let thinkingSummary: [String]
    /// The model's current line of reasoning while it thinks; `nil` once it starts answering.
    let liveThought: String?
    let thinkingDurationSeconds: TimeInterval?
    /// The summary as it stood when the model began thinking. The finished response appends the
    /// full thought to `thinkingSummary`; without this the live view would flash every line just
    /// before collapsing.
    @State private var liveSummarySnapshot: [String]?
    /// Retrieved grounding passages for the turn currently generating, rendered as expandable
    /// Source rows in the loading state. Empty once the response is complete.
    let groundingSources: [GroundingSourceSummary]
    let evidenceBasis: ResponseEvidenceBasis?
    let funStatusText: String?
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let savedInsightIDs: Set<UUID>
    var onRegenerate: (() -> Void)? = nil
    var onDuplicateBranch: (() -> Void)? = nil
    var onInsightTap: ((String, String) -> Void)? = nil
    var onInlineInsightQuote: ((ConceptDefinition) -> Void)? = nil
    var onInlineInsightFork: ((ConceptDefinition) -> Void)? = nil
    var onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)? = nil
    var showsResponseActions: Bool = true
    var onRevealStart: (() -> Void)? = nil
    var onBodyRevealComplete: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    @State private var isThinking: Bool
    @State private var isThinkingDocked: Bool
    @State private var isShowingWritingStatus: Bool
    @State private var showTitle: Bool
    @State private var showResponseContent: Bool
    @State private var isThinkingExpanded: Bool = false
    @State private var isThinkingBasisVisible: Bool = false
    @State private var isThinkingDescriptionVisible: Bool = false
    @State private var visibleThinkingLineCount: Int = 0
    @State private var isThinkingCollapsing: Bool = false
    @State private var hasStartedFinishThinking: Bool = false
    @State private var thinkingStartedAt: Date

    let brandBrown = AngroveTheme.Colors.primaryReadable
    /// The narrated "Consulting …" lines are dropped once the same retrieval is listed as
    /// structured Source rows, so **Show Thinking** reports each source exactly once.
    private var thinkingSummaryLines: [String] {
        guard !groundingSources.isEmpty else { return thinkingSummary }
        return thinkingSummary.filter { !GroundingSourceSummary.isNarratedSourceLine($0) }
    }

    /// Sources fade in after the Show Thinking summary; their icons wait for the same beat.
    private var areGroundingSourcesShown: Bool {
        isThinkingDescriptionVisible && visibleThinkingLineCount >= thinkingSummaryLines.count
    }
    private var presentsThinkingUI: Bool {
        showsThinkingIntro || !thinkingSummary.isEmpty
    }
    private var canShowThinkingSummaryButton: Bool {
        !thinkingSummary.isEmpty
            && !isThinking
            && !isAwaitingResponse
            && showResponseContent
    }

    private var responseBasisTitle: String {
        evidenceBasis?.disclosureTitle ?? "Response Details"
    }

    private var responseBasisDescription: String {
        evidenceBasis?.disclosureDescription
            ?? "Details about how this response was prepared."
    }

    init(
        title: String,
        fullText: String,
        shouldAnimateOnAppear: Bool = true,
        showsThinkingIntro: Bool = true,
        isAwaitingResponse: Bool = false,
        isReceivingStream: Bool = false,
        isQueuedForModel: Bool = false,
        usesIncrementalStream: Bool = false,
        thinkingSummary: [String] = [],
        liveThought: String? = nil,
        thinkingDurationSeconds: TimeInterval? = nil,
        groundingSources: [GroundingSourceSummary] = [],
        evidenceBasis: ResponseEvidenceBasis? = nil,
        funStatusText: String? = nil,
        responseTextAlignment: ResponseTextAlignmentOption = .left,
        responseFont: ConversationFontOption = .serif,
        conversationFontSize: ConversationFontSizeOption = .large,
        loadingInsightKey: String? = nil,
        queuedInsightKeys: Set<String> = [],
        savedInsightIDs: Set<UUID> = [],
        onRegenerate: (() -> Void)? = nil,
        onDuplicateBranch: (() -> Void)? = nil,
        onInsightTap: ((String, String) -> Void)? = nil,
        onInlineInsightQuote: ((ConceptDefinition) -> Void)? = nil,
        onInlineInsightFork: ((ConceptDefinition) -> Void)? = nil,
        onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)? = nil,
        showsResponseActions: Bool = true,
        onRevealStart: (() -> Void)? = nil,
        onBodyRevealComplete: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.title = title
        self.fullText = fullText
        self.shouldAnimateOnAppear = shouldAnimateOnAppear
        self.showsThinkingIntro = showsThinkingIntro
        self.isAwaitingResponse = isAwaitingResponse
        self.isReceivingStream = isReceivingStream
        self.isQueuedForModel = isQueuedForModel
        self.usesIncrementalStream = usesIncrementalStream
        self.thinkingSummary = thinkingSummary
        self.liveThought = liveThought
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.groundingSources = groundingSources
        self.evidenceBasis = evidenceBasis
        self.funStatusText = funStatusText
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.loadingInsightKey = loadingInsightKey
        self.queuedInsightKeys = queuedInsightKeys
        self.savedInsightIDs = savedInsightIDs
        self.onRegenerate = onRegenerate
        self.onDuplicateBranch = onDuplicateBranch
        self.onInsightTap = onInsightTap
        self.onInlineInsightQuote = onInlineInsightQuote
        self.onInlineInsightFork = onInlineInsightFork
        self.onInlineInsightToggleSaved = onInlineInsightToggleSaved
        self.showsResponseActions = showsResponseActions
        self.onRevealStart = onRevealStart
        self.onBodyRevealComplete = onBodyRevealComplete
        self.onFinish = onFinish
        let shouldShowThinking = showsThinkingIntro
            && (isAwaitingResponse || shouldAnimateOnAppear)
        _isThinking = State(initialValue: shouldShowThinking)
        _isThinkingDocked = State(initialValue: !shouldShowThinking)
        _isShowingWritingStatus = State(initialValue: isReceivingStream)
        _showTitle = State(initialValue: !shouldAnimateOnAppear)
        _showResponseContent = State(initialValue: !shouldAnimateOnAppear)
        _thinkingStartedAt = State(initialValue: Date())
        // A restored response is already fully presented. Its StreamingMessageView starts with
        // every word visible and therefore does not run the reveal task or call `onFinish`.
        // Treat it as finished up front so a timer/token footer from the interrupted renderer
        // cannot survive a navigate-away / navigate-back cycle.
    }

    var body: some View {
        VStack(spacing: 0) {

            // Single unified VStack — the "Thinking…" row is the SAME view instance
            // throughout. When isThinking flips false the spring carries it from the
            // centred pill position to left-aligned above the title, never disappearing.
            VStack(alignment: .center, spacing: 16) {

                if presentsThinkingUI {
                    // ── "Thinking…" / expandable thinking summary ─────────────
                    if isThinking {
                        LiveThinkingProgressView(
                            summaryLines: liveSummarySnapshot ?? thinkingSummary,
                            liveThought: liveThought,
                            groundingSources: groundingSources,
                            isWritingResponse: isShowingWritingStatus,
                            isQueuedForModel: isQueuedForModel,
                            funStatusText: funStatusText,
                            font: responseFont.textFont(size: conversationFontSize),
                            color: brandBrown,
                            startedAt: thinkingStartedAt,
                            responseTextAlignment: responseTextAlignment
                        )
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if canShowThinkingSummaryButton {
                        Button(action: {
                            if isThinkingExpanded {
                                collapseThinking()
                            } else {
                                isThinkingCollapsing = false
                                isThinkingBasisVisible = false
                                isThinkingDescriptionVisible = false
                                visibleThinkingLineCount = 0
                                withAnimation(.springStandard) {
                                    isThinkingExpanded = true
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(ResponseThinkingDuration.label(seconds: thinkingDurationSeconds))
                                    .font(responseFont.textFont(size: conversationFontSize))

                                Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                            .foregroundColor(AngroveTheme.Colors.headingText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ResponseThinkingDuration.label(seconds: thinkingDurationSeconds))
                        .accessibilityValue(isThinkingExpanded ? "Expanded" : "Collapsed")
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if presentsThinkingUI && !isThinking && isThinkingExpanded {
                    VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 16) {
                        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: conversationFontSize.pointSize, weight: .semibold))
                                Text(responseBasisTitle)
                                    .font(responseFont.textFont(size: conversationFontSize).weight(.bold))
                            }
                            .foregroundStyle(AngroveTheme.Colors.placeholderText)
                            .frame(
                                maxWidth: .infinity,
                                alignment: responseTextAlignment.frameAlignment
                            )
                            .opacity(isThinkingBasisVisible ? 1 : 0)
                            Text(responseBasisDescription)
                                .font(responseFont.textFont(size: conversationFontSize))
                                .lineSpacing(5)
                                .multilineTextAlignment(responseTextAlignment.textAlignment)
                                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: responseTextAlignment.frameAlignment
                                )
                                .opacity(isThinkingDescriptionVisible ? 1 : 0)
                            ForEach(Array(thinkingSummaryLines.enumerated()), id: \.offset) { index, line in
                                ApproachSummaryRow(line: line, alignment: responseTextAlignment)
                                    .font(responseFont.textFont(size: conversationFontSize))
                                    .lineSpacing(8)
                                    .multilineTextAlignment(responseTextAlignment.textAlignment)
                                    .foregroundColor(AngroveTheme.Colors.placeholderText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .opacity(index < visibleThinkingLineCount ? 1 : 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)

                        if !groundingSources.isEmpty {
                            VStack(
                                alignment: responseTextAlignment.horizontalAlignment,
                                spacing: 8
                            ) {
                                ForEach(groundingSources.enumerated(), id: \.element.id) { index, source in
                                    GroundingSourceRow(
                                        source: source,
                                        responseTextAlignment: responseTextAlignment,
                                        placement: index,
                                        isShown: areGroundingSourcesShown,
                                        usesDisclosureEntrance: true
                                    )
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: responseTextAlignment.frameAlignment
                            )
                            .opacity(areGroundingSourcesShown ? 1 : 0)
                        }

                        Button(action: {
                            collapseThinking()
                        }) {
                            HStack(spacing: 6) {
                                Text("Hide Thinking")
                                    .font(responseFont.textFont(size: conversationFontSize))

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(AngroveTheme.Colors.headingText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                    }
                    .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .task {
                        // Lazy transcript reappearance must not restart a completed disclosure.
                        guard !areGroundingSourcesShown else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isThinkingBasisVisible = true
                        }
                        try? await Task.sleep(for: .milliseconds(180))
                        guard !Task.isCancelled, !isThinkingCollapsing else { return }

                        withAnimation(.easeInOut(duration: 0.35)) {
                            isThinkingDescriptionVisible = true
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled, !isThinkingCollapsing else { return }

                        guard !thinkingSummaryLines.isEmpty else {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                visibleThinkingLineCount = 0
                            }
                            return
                        }
                        guard visibleThinkingLineCount < thinkingSummaryLines.count else { return }
                        for lineCount in (visibleThinkingLineCount + 1)...thinkingSummaryLines.count {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                visibleThinkingLineCount = lineCount
                            }
                            try? await Task.sleep(for: .milliseconds(50))
                            guard !Task.isCancelled, !isThinkingCollapsing else { return }
                        }
                    }
                }

                // ── Title + response body (card state only) ───────────────────
                if !isThinking
                    && !isAwaitingResponse
                    && showResponseContent {
                    if showTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(title)
                            .font(.baskervilleDisplay)
                            .foregroundColor(brandBrown)
                            .multilineTextAlignment(responseTextAlignment.textAlignment)
                            .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                            .transition(.glideFadeUp)
                    }

                    StreamingMessageView(
                        fullText: fullText,
                        shouldStream: shouldAnimateOnAppear,
                        isReceivingStream: isReceivingStream,
                        usesIncrementalStream: usesIncrementalStream,
                        responseTextAlignment: responseTextAlignment,
                        responseFont: responseFont,
                        conversationFontSize: conversationFontSize,
                        loadingInsightKey: loadingInsightKey,
                        queuedInsightKeys: queuedInsightKeys,
                        savedInsightIDs: savedInsightIDs,
                        showsResponseActions: showsResponseActions,
                        evidenceBasis: evidenceBasis,
                        onRegenerate: onRegenerate,
                        onBranch: onDuplicateBranch,
                        onInsightTap: onInsightTap,
                        onInlineInsightQuote: onInlineInsightQuote,
                        onInlineInsightFork: onInlineInsightFork,
                        onInlineInsightToggleSaved: onInlineInsightToggleSaved,
                        onRevealStart: onRevealStart,
                        onBodyRevealComplete: {
                            onBodyRevealComplete?()
                        },
                        onFinish: onFinish
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))


                }
            }
            .frame(
                maxWidth: isThinkingDocked ? .infinity : nil,
                alignment: .center
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.5)),
                removal: .modifier(
                    active: BlurFadeModifier(isActive: true),
                    identity: BlurFadeModifier(isActive: false)
                )
            ))
            .animation(.springRelaxed, value: isThinking)
            .animation(.springRelaxed, value: isThinkingDocked)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            if shouldBeginThinking {
                startThinking()
            }
            guard shouldAnimateOnAppear else { return }
            guard !isAwaitingResponse else { return }
            guard showsThinkingIntro else {
                await revealContentWithoutThinking()
                return
            }
            await finishThinking()
        }
        .onChange(of: isAwaitingResponse) { _, isAwaiting in
            if isAwaiting, shouldBeginThinking {
                startThinking()
                return
            }
            guard !isAwaiting else { return }
            Task { @MainActor in
                if showsThinkingIntro {
                    await finishThinking()
                } else {
                    await revealContentWithoutThinking()
                }
            }
        }
        .onChange(of: isReceivingStream) { _, isReceiving in
            guard isReceiving, isThinking else { return }
            withAnimation(.springStandard) {
                isShowingWritingStatus = true
                isThinkingDocked = true
            }
        }
        .onChange(of: liveThought != nil) { _, isThinkingLive in
            if isThinkingLive, liveSummarySnapshot == nil {
                liveSummarySnapshot = thinkingSummary
            }
        }
        .onChange(of: thinkingSummary.isEmpty) { _, isEmpty in
            // A regenerate clears the summary; start the next answer's snapshot fresh.
            if isEmpty { liveSummarySnapshot = nil }
        }
        .onChange(of: thinkingSummary.count) { _, count in
            guard count > 0, isThinking else { return }
            withAnimation(.springStandard) {
                isThinkingDocked = true
            }
        }
    }

    private var shouldBeginThinking: Bool {
        showsThinkingIntro
            && shouldAnimateOnAppear
            && (isAwaitingResponse || isReceivingStream || fullText.isEmpty)
            && !hasStartedFinishThinking
    }

    private func startThinking() {
        thinkingStartedAt = Date()
        hasStartedFinishThinking = false
        isThinkingExpanded = false
        isThinkingBasisVisible = false
        isThinkingDescriptionVisible = false
        visibleThinkingLineCount = 0
        isThinkingCollapsing = false
        withAnimation(.springRelaxed) {
            isThinking = true
            isThinkingDocked = false
            isShowingWritingStatus = isReceivingStream
            showTitle = false
            showResponseContent = false
        }
    }

    /// Used when `showsThinkingIntro` is false (e.g. a cancelled response, which swaps in plain
    /// text and suppresses the thinking UI) — reveals content directly. Must still reset
    /// `isThinking`/`hasStartedFinishThinking`/the elapsed-time clock, or a thinking state left
    /// over from before the cancellation keeps `LiveThinkingProgressView` (and its live timer)
    /// mounted and ticking indefinitely, even though nothing is actually being generated anymore.
    @MainActor
    private func revealContentWithoutThinking() async {
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        hasStartedFinishThinking = true
        withAnimation(.easeOut(duration: 0.22)) {
            isThinking = false
            isThinkingDocked = true
            isShowingWritingStatus = false
            showTitle = true
            showResponseContent = true
        }
    }

    @MainActor
    private func finishThinking() async {
        guard isThinking, !hasStartedFinishThinking else { return }
        hasStartedFinishThinking = true
        let minimumVisibleDuration: TimeInterval = 1.15
        let elapsed = Date().timeIntervalSince(thinkingStartedAt)
        if elapsed < minimumVisibleDuration {
            try? await Task.sleep(for: .milliseconds(Int((minimumVisibleDuration - elapsed) * 1_000)))
            guard !Task.isCancelled else { return }
        }
        withAnimation(.springRelaxed) {
            isThinkingDocked = true
        }

        withAnimation(.springStandard) {
            isThinking = false
        }

        // Let the progress stack finish collapsing before the response and its
        // persistent "Show Thinking" disclosure enter together.
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            isShowingWritingStatus = false
            showTitle = true
            showResponseContent = true
        }
    }

    private func collapseThinking() {
        isThinkingCollapsing = true
        withAnimation(.easeOut(duration: 0.1)) {
            isThinkingBasisVisible = false
            isThinkingDescriptionVisible = false
            visibleThinkingLineCount = 0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            withAnimation(.springStandard) {
                isThinkingExpanded = false
            }
        }
    }
}

/// One thinking line, with a short "Heading:" prefix set in bold. Legacy summaries without a
/// label still render intact. `inheritsStyle` lets a live row take the shimmer's gradient.
private struct ApproachSummaryRow: View {
    let line: String
    let alignment: ResponseTextAlignmentOption
    var inheritsStyle: Bool = false

    private var parts: (heading: String?, detail: String) {
        guard let separator = line.range(of: ": "),
              line.distance(from: line.startIndex, to: separator.lowerBound) < 24 else {
            return (nil, line)
        }
        return (String(line[..<separator.lowerBound]), String(line[separator.upperBound...]))
    }

    var body: some View {
        VStack(alignment: alignment.horizontalAlignment, spacing: 4) {
            if let heading = parts.heading {
                Text(heading)
                    .fontWeight(.bold)
                    .modifier(RowForeground(color: inheritsStyle ? nil : AngroveTheme.Colors.headingText))
            }
            Text(parts.detail)
                .modifier(RowForeground(color: inheritsStyle ? nil : AngroveTheme.Colors.placeholderText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
        .accessibilityElement(children: .combine)
    }
}

/// Applies a fixed color, or leaves the inherited foreground (such as the shimmer) alone.
private struct RowForeground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}

private struct LiveThinkingProgressView: View {
    let summaryLines: [String]
    let liveThought: String?
    let groundingSources: [GroundingSourceSummary]
    let isWritingResponse: Bool
    let isQueuedForModel: Bool
    let funStatusText: String?
    let font: Font
    let color: Color
    let startedAt: Date
    var responseTextAlignment: ResponseTextAlignmentOption = .left

    /// The narrated "Consulting …" lines are dropped once the same retrieval is available as
    /// structured Source rows, so the loading state reports each source exactly once.
    private var visibleSummaryLines: [String] {
        guard !groundingSources.isEmpty else { return summaryLines }
        return summaryLines.filter { !GroundingSourceSummary.isNarratedSourceLine($0) }
    }

    private var showsDetailedProgress: Bool {
        !summaryLines.isEmpty || !groundingSources.isEmpty || isWritingResponse
            || currentThought != nil
    }

    /// The live reasoning line, hidden once answer text starts arriving.
    private var currentThought: String? {
        isWritingResponse ? nil : liveThought
    }

    private var showsWritingResponse: Bool {
        isWritingResponse
    }

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
            Group {
                if showsDetailedProgress {
                    VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
                        ForEach(Array(visibleSummaryLines.enumerated()), id: \.offset) { index, line in
                            ApproachSummaryRow(line: line, alignment: responseTextAlignment, inheritsStyle: true)
                                .font(font)
                                .lineSpacing(8)
                                .multilineTextAlignment(responseTextAlignment.textAlignment)
                                .fixedSize(horizontal: false, vertical: true)
                                .modifier(
                                    ThinkingShimmer(
                                        isActive: !isWritingResponse
                                            && currentThought == nil
                                            && index == visibleSummaryLines.count - 1,
                                        color: color
                                    )
                                )
                                .transition(.glideFadeUp)
                        }

                        // Sources arrive together, but read as a sequence: each row's entrance is
                        // staggered by its placement, so the last source lands last.
                        ForEach(groundingSources.enumerated(), id: \.element.id) { index, source in
                            GroundingSourceRow(
                                source: source,
                                responseTextAlignment: responseTextAlignment,
                                placement: index
                            )
                        }

                        // The model's own reasoning, one line at a time: each completed line
                        // replaces the last rather than accumulating.
                        if let currentThought {
                            ApproachSummaryRow(
                                line: currentThought,
                                alignment: responseTextAlignment,
                                inheritsStyle: true
                            )
                                .font(font)
                                .lineSpacing(8)
                                .lineLimit(3)
                                .multilineTextAlignment(responseTextAlignment.textAlignment)
                                .modifier(ThinkingShimmer(isActive: true, color: color))
                                .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                                .id(currentThought)
                                .transition(.asymmetric(insertion: .glideFadeUp, removal: .opacity))
                                .accessibilityLabel("Thinking: \(currentThought)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                } else {
                    if isQueuedForModel {
                        Text(funStatusText ?? "Question queued")
                            .font(font)
                            .fontWeight(.bold)
                            .modifier(QueuedWorkBreatheModifier(isQueued: true))
                            .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .accessibilityLabel("Question queued")
                    } else {
                        Text(funStatusText ?? "Thinking...")
                            .font(font)
                            .fontWeight(.bold)
                            .modifier(ThinkingShimmer(isActive: true, color: color))
                            .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .accessibilityLabel("Thinking")
                    }
                }
            }

            if showsDetailedProgress {
                ThinkingMetricsFooter(
                    startedAt: startedAt,
                    color: color
                )
                .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                .transition(.opacity)
            }

            // Only actual answer text advances the progress to writing.
            if showsWritingResponse {
                HStack(alignment: .center, spacing: 14) {
                    LeafLoadingAnimation()

                    Text("Writing Response...")
                        .font(font)
                        .fontWeight(.bold)
                        .lineSpacing(8)
                        .multilineTextAlignment(responseTextAlignment.textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(ThinkingShimmer(isActive: true, color: color))
                }
                .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                .transition(.glideFadeUp)
                .accessibilityLabel("Writing response")
            }
        }
        .animation(.easeOut(duration: 0.3), value: summaryLines)
        .animation(.easeOut(duration: 0.3), value: currentThought)
        .animation(.easeOut(duration: 0.3), value: isWritingResponse)
        .animation(.easeInOut(duration: 0.25), value: isQueuedForModel)
    }
}

/// One retrieved source shown while the model is generating. Collapsed it is just the source
/// title; tapped it expands into a bordered card showing the passage retrieval actually pulled,
/// so the grounding claim is inspectable rather than asserted.
private struct GroundingSourceRow: View {
    let source: GroundingSourceSummary
    var responseTextAlignment: ResponseTextAlignmentOption = .left
    /// Position among the retrieved sources; later rows enter after earlier ones.
    var placement: Int = 0
    /// False while the row is laid out but still hidden, so its entrance waits.
    var isShown: Bool = true
    /// Finished thinking disclosures animate from their opening state, never viewport changes.
    var usesDisclosureEntrance: Bool = false

    private static let placementStagger: Duration = .milliseconds(180)

    @State private var isExpanded: Bool = false
    @State private var visiblePassageSegmentCount: Int = 0
    @State private var isTitleRevealed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subject: LibrarySubject { LibrarySubject.of(workID: source.sourceID ?? "") }
    private var isEntranceRevealed: Bool {
        reduceMotion || (usesDisclosureEntrance ? isShown : isTitleRevealed)
    }

    /// The passage broken into the units it reveals in, matching how **Show Thinking** steps
    /// through its summary lines. Explicit line breaks win where the source has them (verse and
    /// heading text); otherwise the passage is split into sentences so continuous prose still
    /// arrives in readable pieces rather than all at once.
    private var passageSegments: [String] {
        let lines = source.passage
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count == 1, let paragraph = lines.first else { return lines }

        var sentences: [String] = []
        paragraph.enumerateSubstrings(
            in: paragraph.startIndex..<paragraph.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            let sentence = substring?.trimmingCharacters(in: .whitespaces) ?? ""
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences.isEmpty ? lines : sentences
    }

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
            Button {
                // Revealing always restarts from nothing, so collapsing and reopening a source
                // plays the same staged entrance rather than snapping straight to full text.
                visiblePassageSegmentCount = 0
                withAnimation(.springStandard) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // The Library's icon for this work's genre, so a source reads the same here as
                    // on its shelf. Curated notes and older saves have no
                    // work and use the default.
                    // Completed disclosures use their opening state; live retrievals retain
                    // the icon-driven entrance.
                    LibrarySubjectIcon(
                        subject: subject,
                        symbolSize: 13,
                        shelfIsVisible: isShown,
                        entranceDelay: usesDisclosureEntrance ? nil : Self.placementStagger * placement,
                        onRevealChange: { isTitleRevealed = $0 }
                    )
                    .opacity(usesDisclosureEntrance && !isEntranceRevealed ? 0 : 1)

                    Text(source.title)
                        .paragraphFont()
                        .lineSpacing(6)
                        .multilineTextAlignment(responseTextAlignment.textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(isEntranceRevealed ? 1 : 0)
                        .offset(x: isEntranceRevealed ? 0 : -8)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(isEntranceRevealed ? 1 : 0)
                        .offset(x: isEntranceRevealed ? 0 : -8)
                }
                .animation(
                    usesDisclosureEntrance && !reduceMotion
                        ? .easeInOut(duration: 0.3).delay(0.18 * Double(placement))
                        : nil,
                    value: isShown
                )
                .foregroundColor(
                    isExpanded
                        ? AngroveTheme.Colors.headingText
                        : AngroveTheme.Colors.placeholderText
                )
                .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 12) {
                    // Corpus passages carry the same string as both title and source name; only
                    // the curated layer names a distinct edition worth repeating here.
                    if source.sourceName != source.title {
                        Text(source.sourceName)
                            .font(.custom("Figtree-Regular", size: 12))
                            .foregroundColor(AngroveTheme.Colors.placeholderText)
                            .multilineTextAlignment(responseTextAlignment.textAlignment)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(visiblePassageSegmentCount > 0 ? 1 : 0)
                    }

                    ForEach(Array(passageSegments.enumerated()), id: \.offset) { index, segment in
                        Text(segment)
                            .paragraphFont()
                            .lineSpacing(6)
                            .foregroundColor(AngroveTheme.Colors.paragraphText)
                            .multilineTextAlignment(responseTextAlignment.textAlignment)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(index < visiblePassageSegmentCount ? 1 : 0)
                    }

                    Button {
                        NotificationCenter.default.post(
                            name: .openGroundingSourceInLibrary,
                            object: LibraryNavigationRequest(source: source)
                        )
                    } label: {
                        Label("Read More", systemImage: "arrow.up.right")
                            .paragraphFont()
                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    }
                    .buttonStyle(.plain)
                    .frame(
                        maxWidth: .infinity,
                        alignment: responseTextAlignment.frameAlignment
                    )
                }
                .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .task {
                    guard visiblePassageSegmentCount < passageSegments.count else { return }
                    // Hold until the card's own padding/background/border spring has settled,
                    // then step the passage in, same cadence as the Show Thinking summary.
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, isExpanded else { return }

                    for segmentCount in (visiblePassageSegmentCount + 1)...passageSegments.count {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            visiblePassageSegmentCount = segmentCount
                        }
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled, isExpanded else { return }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .padding(isExpanded ? 16 : 0)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    isExpanded
                        ? AngroveTheme.Colors.canvasSecondary
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    isExpanded ? AngroveTheme.Colors.border : Color.clear,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source: \(source.title)")
        .accessibilityHint(isExpanded ? "Hide retrieved passage" : "Show retrieved passage")
    }
}

/// Small animated writing mark shown only while the model is composing its response.
/// Elapsed time pinned below the thinking/writing text.
private struct ThinkingMetricsFooter: View {
    let startedAt: Date
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsedSeconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
            HStack(spacing: 4) {
                Text(formattedDuration(elapsedSeconds))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(elapsedSeconds)))
                    // Fixed width (not just monospacedDigit) so the footer doesn't reflow
                    // every second as the digit count changes, e.g. "9s" → "10s" → "1:00".
                    .frame(width: 28, alignment: .leading)


            }
            .font(.custom("Figtree-Regular", size: 12))
            .foregroundColor(color.opacity(0.4))
            .animation(.easeOut(duration: 0.35), value: elapsedSeconds)
        }
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, seconds) : "\(seconds)s"
    }
}

// MARK: - Thinking shimmer

/// Sweeps a bright wave left-to-right across text while the model is thinking.
/// Uses TimelineView(.animation) so phase is derived from wall-clock time —
/// guaranteed per-frame updates, no @State animation batching issues.
struct ThinkingShimmer: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let t  = context.date.timeIntervalSinceReferenceDate
                // Total cycle: 1.0 s sweep + 1.0 s pause = 2.0 s.
                // `phase` only reaches 1.0 at the sweep midpoint; after that it
                // clamps at 1.0 so the band sits off the right edge (invisible)
                // for the pause portion before the next sweep begins. The sweep
                // range clears the band (half-width 0.4) fully past x = 1.0 by
                // the time phase reaches 1.0, so the fade-out happens gradually
                // as part of the sweep itself instead of leaving a bright tail
                // resting on the last character that then snaps away when the
                // next cycle starts.
                let cycle: Double  = 2.0
                let sweepSpan: Double = 1.0
                let tMod  = t.truncatingRemainder(dividingBy: cycle)
                let phase = CGFloat(min(tMod / sweepSpan, 1.0))
                let sweep = phase * 1.9 - 0.4
                content
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                color.opacity(0.25),
                                color.opacity(0.95),
                                color.opacity(0.25),
                            ],
                            startPoint: UnitPoint(x: sweep - 0.4, y: 0.5),
                            endPoint:   UnitPoint(x: sweep + 0.4, y: 0.5)
                        )
                    )
            }
        } else {
            content.foregroundColor(color.opacity(0.5))
        }
    }
}

extension View {
    /// Clips the view only when `active` is true; otherwise leaves overflow visible.
    @ViewBuilder
    func clipped(when active: Bool) -> some View {
        if active {
            self.clipped()
        } else {
            self
        }
    }
}

/// Formats recorded preparation time without inventing durations for older responses.
enum ResponseThinkingDuration {
    static func label(seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return String(localized: "Thought") }
        let total = Int(min(max(0, seconds), Double(Int.max / 2)))
        if total < 60 {
            return String(localized: "Thought for \(total)s")
        }
        return String(localized: "Thought for \(total / 60)m \(total % 60)s")
    }
}
