//
//  ResponseButtons.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

/// Shared timing for conversation and Insight action entrances.
enum ResponseRevealTiming {
    static let actionStagger = 0.10
    static let actionDuration = 0.28
    static let finishingDuration = 0.35
    static let actionAnimation = Animation.easeOut(duration: actionDuration)
    static let finishingAnimation = Animation.easeOut(duration: finishingDuration)
}

private struct ResponseActionEntrance: ViewModifier {
    var isVisible: Bool
    var animates: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 4)
            .scaleEffect(isVisible ? 1 : 0.88)
            .animation(animates ? ResponseRevealTiming.actionAnimation : nil, value: isVisible)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

extension EnvironmentValues {
    /// The conversation's title, shown as the read-aloud's title on the Lock Screen.
    @Entry var speechSource = SpeechSource()
}

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
    @State private var showsCopiedConfirmation = false
    @State private var visibleActionCount = 0
    @State private var visibleDisclaimerWords = 0
    private var speech: ResponseSpeechPlayer { .shared }

    private var disclaimerWords: [String] {
        String(localized: "AI can make mistakes, verify important details")
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var actionCount: Int {
        2 + (onRegenerate == nil ? 0 : 1)
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
                speakButton
                if speech.phase(for: copyText) != .idle {
                    Text("Tap and drag on a conversation block to fast forward and rewind")
                        .font(.custom("Figtree-SemiBold", size: 10))
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
                        .font(.custom("Figtree-SemiBold", size: 10))
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
            isVisible: (onRegenerate == nil ? 1 : 2) < visibleActionCount,
            animates: shouldAnimateOnAppear && !reduceMotion
        ))
        .frame(width: 18, height: 16)
    }

    private func actionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
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
        UIPasteboard.general.string = copyText
        withAnimation(.springBouncy) { showsCopiedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showsCopiedConfirmation = false }
        }
    }
}

// MARK: - Shared Response Buttons

/// Shared action row for model responses and insight cards.
struct ResponseButtons: View {
    var isSaved: Bool = false
    var canCopy: Bool = false
    var canQuote: Bool = false
    var canFork: Bool = true
    var copyText: String? = nil
    var quoteAccessibilityLabel: String = "Quote"
    /// When set, overrides the default `responseButton` color for all icons.
    var tintColor: Color? = nil
    /// When set, overrides the save/bookmark icon color independently.
    var saveTintColor: Color? = nil
    var onSave: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onQuote: (() -> Void)? = nil
    var onFork: (() -> Void)? = nil

    @State private var visibleActionCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCopied = false
    @State private var revealRunID = UUID()

    private var actions: [ResponseButtonAction] {
        var items: [ResponseButtonAction] = []

        if onSave != nil {
            items.append(.save(isSaved: isSaved))
        }

        if canCopy || copyText != nil || onCopy != nil {
            items.append(.copy(isCopied: showCopied))
        }

        if canQuote, onQuote != nil {
            items.append(.quote)
        }

        if canFork, onFork != nil {
            items.append(.fork)
        }

        return items
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button {
                    handle(action)
                } label: {
                    buttonIcon(for: action)
                }
                .buttonStyle(.plain)
                .modifier(ResponseActionEntrance(
                    isVisible: visibleActionCount > index,
                    animates: !reduceMotion
                ))
                .frame(width: 16, height: 16)
                .accessibilityLabel(action == .quote ? quoteAccessibilityLabel : (action == .save(isSaved: true) ? "Remove bookmark" : "Bookmark"))
            }
        }
        .onAppear(perform: revealButtons)
        .onChange(of: actions.count) { oldValue, newValue in
            revealButtons()
        }
    }

    private func buttonIcon(for action: ResponseButtonAction) -> some View {
        Image(systemName: action.systemName)
            .font(.system(size: 16, weight: action.weight))
            .rotationEffect(action == .fork ? .degrees(90) : .degrees(0))
            .foregroundColor(iconColor(for: action))
            .frame(width: 16, height: 16)
    }

    private func iconColor(for action: ResponseButtonAction) -> Color {
        switch action {
        case .save:
            return saveTintColor ?? tintColor ?? action.foregroundColor
        default:
            return tintColor ?? action.foregroundColor
        }
    }

    private func handle(_ action: ResponseButtonAction) {
        switch action {
        case .save:
            onSave?()
        case .copy:
            if let copyText {
                UIPasteboard.general.string = copyText
            }
            onCopy?()
            withAnimation(.springBouncy) {
                showCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showCopied = false
                }
            }
        case .quote:
            onQuote?()
        case .fork:
            onFork?()
        }
    }

    private func revealButtons() {
        let runID = UUID()
        revealRunID = runID
        guard !reduceMotion else {
            visibleActionCount = actions.count
            return
        }
        visibleActionCount = 0

        for index in actions.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * ResponseRevealTiming.actionStagger)) {
                guard revealRunID == runID else { return }
                visibleActionCount = max(visibleActionCount, index + 1)
            }
        }
    }
}

private enum ResponseButtonAction: Equatable {
    case save(isSaved: Bool)
    case copy(isCopied: Bool)
    case quote
    case fork

    var systemName: String {
        switch self {
        case .save(let isSaved):
            return isSaved ? "bookmark.fill" : "bookmark"
        case .copy(let isCopied):
            return isCopied ? "checkmark" : "square.on.square"
        case .quote:
            return "arrow.turn.down.right"
        case .fork:
            return "arrow.triangle.branch"
        }
    }

    var weight: Font.Weight {
        switch self {
        case .fork:
            return .bold
        default:
            return .semibold
        }
    }

    var foregroundColor: Color {
        switch self {
        case .save(let isSaved):
            return isSaved ? AngroveTheme.Colors.accent : AngroveTheme.Colors.responseButton
        default:
            return AngroveTheme.Colors.responseButton
        }
    }
}
