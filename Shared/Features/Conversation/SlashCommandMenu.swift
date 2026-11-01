//
//  SlashCommandMenu.swift
//  Angrove-iOS
//
//  Slash-command picker shown when the user types "/" in the chat input.
//  Mirrors the Figma "personality-selector-light-mode" card (node 553:599):
//  a "Commands" heading over a vertical list of command names on the
//  Canvas Secondary card, tappable to insert the command into the input.
//

import Combine
import SwiftUI

/// Live text the user is typing in the composer, mirrored into the picker's header so
/// "/usertext" tracks the field behind the popup. Held as a reference type and observed
/// only by the picker, so per-keystroke updates never re-render the conversation tree.
final class SlashCommandQuery: ObservableObject {
    @Published var text: String = ""
}

/// A single slash command. `name` includes the leading slash (e.g. "/compact").
/// `description` is supporting copy for accessibility / a future two-line layout —
/// the Figma design lists names only, so it isn't rendered in the default card.
struct SlashCommand: Identifiable, Equatable {
    var id: String { name }
    let name: String
    var description: String = ""
}

enum SlashCommandInvocation: Equatable {
    case define(String?)
    case compact
    case clear
    case rename(String?)
    case newConversation
    case tree
    case topic
    case insights

    /// Definition requests create a normal persisted turn rather than a management action.
    var producesResponse: Bool {
        if case .define(.some) = self { return true }
        return false
    }
}

extension SlashCommand {
    /// Commands currently supported by the conversation runtime.
    static let all: [SlashCommand] = [
        SlashCommand(name: "/define",     description: "Define a word or main subject as an Insight card"),
        SlashCommand(name: "/compact",    description: "Condense the conversation so far"),
        SlashCommand(name: "/clear",      description: "Clear the current conversation"),
        SlashCommand(name: "/rename",     description: "Rename the current conversation"),
        SlashCommand(name: "/new",        description: "Start a new conversation"),
        SlashCommand(name: "/tree",       description: "Open this conversation's Insight Tree"),
        SlashCommand(name: "/topic",      description: "Choose a Study Topic for this conversation"),
        SlashCommand(name: "/insights",   description: "Open the Insight library"),
    ]

    static func invocation(for text: String) -> SlashCommandInvocation? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = parts.first else { return nil }
        switch name.lowercased() {
        case "/define":
            return .define(parts.count == 2
                ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : nil)
        case "/compact":
            return parts.count == 1 ? .compact : nil
        case "/clear":
            return parts.count == 1 ? .clear : nil
        case "/rename":
            return .rename(parts.count == 2
                ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : nil)
        case "/new":
            return parts.count == 1 ? .newConversation : nil
        case "/tree":
            return parts.count == 1 ? .tree : nil
        case "/topic":
            return parts.count == 1 ? .topic : nil
        case "/insights":
            return parts.count == 1 ? .insights : nil
        default:
            return nil
        }
    }
}

/// The slash-command picker card. Matches the Figma card exactly (24pt padding,
/// 24pt corner radius, 16pt gap, Figtree Bold 18 heading / SemiBold 14 rows in the
/// paragraph-text color on the Canvas Secondary background with the brown border).
///
/// Pass `maxHeight` to cap the list and let it scroll when it has more commands than fit;
/// leave it `nil` to hug the content (as the Figma frame does).
struct SlashCommandMenu: View {
    @ObservedObject var query: SlashCommandQuery
    var commands: [SlashCommand] = SlashCommand.all
    var maxHeight: CGFloat? = nil
    var onSelect: (SlashCommand) -> Void

    /// 14pt row text at the design's 1.5 line-height → a 21pt line box per row.
    private var rowLineBox: CGFloat { 14 * 1.5 }

    /// Commands whose name matches the typed "/token" (prefix match). A bare "/" shows all.
    private var suggestions: [SlashCommand] {
        let q = query.text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count > 1 else { return commands }
        return commands.filter { $0.name.lowercased().hasPrefix(q) }
    }

    var body: some View {
        commandList
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var commandList: some View {
        if maxHeight != nil {
            ScrollView {
                rows
            }
            .scrollBounceBehavior(.basedOnSize)
            // Bottom fade hints there's more to scroll — fades into the card's canvas color.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        AngroveTheme.Colors.canvasSecondary.opacity(0),
                        AngroveTheme.Colors.canvasSecondary,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        // No inter-row spacing: the 1.5 line-height box already supplies the rhythm
        // the design shows (leading-[1.5], mb-0 between rows).
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { command in
                Button {
                    onSelect(command)
                } label: {
                    Text(command.name)
                        .font(.custom("Figtree-SemiBold", size: 14))
                        .foregroundColor(AngroveTheme.Colors.placeholderText)
                        .frame(maxWidth: .infinity, minHeight: rowLineBox, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(command.name)
                .accessibilityHint(command.description)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: suggestions)
    }
}

/// The Insight picker shown while a question ends in `#title`, styled like the command menu.
/// Tapping an Insight quotes it into the question.
struct InsightQuoteMenu: View {
    @ObservedObject var query: SlashCommandQuery
    let candidates: [ConceptDefinition]
    var quotedIDs: Set<UUID> = []
    var maxHeight: CGFloat = 186
    var onSelect: (ConceptDefinition) -> Void

    private var rowLineBox: CGFloat { 14 * 1.5 }

    private var suggestions: [ConceptDefinition] {
        InsightMention.suggestions(for: query.text, from: candidates, excluding: quotedIDs)
    }

    var body: some View {
        let suggestions = suggestions
        if !suggestions.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions) { insight in
                        Button {
                            onSelect(insight)
                        } label: {
                            Text(insight.word.capitalized)
                                .font(.custom("Figtree-SemiBold", size: 14))
                                .foregroundColor(AngroveTheme.Colors.placeholderText)
                                .frame(maxWidth: .infinity, minHeight: rowLineBox, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(insight.word.capitalized)
                        .accessibilityHint("Quotes this Insight in your question")
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: suggestions.map(\.id))
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: min(maxHeight, CGFloat(suggestions.count) * rowLineBox))
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AngroveTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1)
            )
        }
    }
}

#Preview("Slash Command Menu") {
    ZStack {
        AngroveTheme.Colors.canvas.ignoresSafeArea()
        SlashCommandMenu(query: {
            let q = SlashCommandQuery()
            q.text = "/comp"
            return q
        }(), maxHeight: 186) { command in
            print("Selected \(command.name)")
        }
        .frame(width: 300)
        .padding()
    }
}
