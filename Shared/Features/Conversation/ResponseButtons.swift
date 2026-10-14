//
//  ResponseButtons.swift
//  Angrove-iOS
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shared timing for conversation and Insight action entrances.
enum ResponseRevealTiming {
    static let actionStagger = 0.10
    static let actionDuration = 0.28
    static let finishingDuration = 0.35
    static let actionAnimation = Animation.easeOut(duration: actionDuration)
    static let finishingAnimation = Animation.easeOut(duration: finishingDuration)
}

struct ResponseActionEntrance: ViewModifier {
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

struct ResponseButtons: View {
    var isSaved: Bool = false
    var canCopy: Bool = false
    var canQuote: Bool = false
    var canFork: Bool = true
    var copyText: String? = nil
    /// Full card content to read, independent of copying or visible truncation.
    var speechText: String? = nil
    var quoteAccessibilityLabel: String = "Quote"
    /// When set, overrides the default `responseButton` color for all icons.
    var tintColor: Color? = nil
    /// When set, overrides the save/bookmark icon color independently.
    var saveTintColor: Color? = nil
    var onSave: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onQuote: (() -> Void)? = nil
    var onSpeak: (() -> Void)? = nil
    var onFork: (() -> Void)? = nil

    @Environment(\.speechSource) private var speechSource
    private var speech: ResponseSpeechPlayer { .shared }

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

        if onSpeak != nil || speechText.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true {
            items.append(.speak)
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
                .accessibilityLabel(accessibilityLabel(for: action))
            }
        }
        .onAppear(perform: revealButtons)
        .onChange(of: actions.map(\.systemName)) { _, _ in
            revealButtons()
        }
    }

    private func buttonIcon(for action: ResponseButtonAction) -> some View {
        Image(systemName: action.systemName)
            .font(.system(size: 16, weight: action.weight))
            .symbolEffect(.variableColor.iterative, isActive: action == .speak && isSpeaking && !reduceMotion)
            .rotationEffect(action == .fork ? .degrees(90) : .degrees(0))
            .foregroundColor(iconColor(for: action))
            .frame(width: 16, height: 16)
    }

    private var isSpeaking: Bool {
        guard let speechText else { return false }
        return speech.phase(for: speechText) != .idle
    }

    private func accessibilityLabel(for action: ResponseButtonAction) -> String {
        switch action {
        case .save(let isSaved):
            return isSaved ? String(localized: "Remove bookmark") : String(localized: "Bookmark")
        case .copy(let isCopied):
            return isCopied ? String(localized: "Copied") : String(localized: "Copy")
        case .quote:
            return quoteAccessibilityLabel
        case .fork:
            return String(localized: "Branch")
        case .speak:
            return isSpeaking ? String(localized: "Stop reading") : String(localized: "Read card aloud")
        }
    }

    private func iconColor(for action: ResponseButtonAction) -> Color {
        switch action {
        case .speak where isSpeaking:
            return AngroveTheme.Colors.lightGreen
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
                PlatformClipboard.copy(copyText)
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
        case .speak:
            if let onSpeak {
                onSpeak()
            } else if let speechText {
                speech.toggle(speechText, units: CardSpeech.units(for: speechText), source: speechSource)
            }
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
    case speak

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
        case .speak:
            return "speaker.wave.2"
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
