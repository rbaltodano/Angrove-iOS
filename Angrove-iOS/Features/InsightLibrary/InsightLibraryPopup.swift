//
//  InsightLibraryPopup.swift
//  Angrove-iOS
//

import SwiftUI

// MARK: - Insight Library Popup

struct InsightLibraryPopup: View {
    let currentConversationInsights: [ConceptDefinition]
    let currentConversationPassages: [ConceptDefinition]
    let allInsights: [ConceptDefinition]
    let clippedPassages: [ConceptDefinition]
    @Binding var savedInsights: [ConceptDefinition]
    var opensPassages: Bool = false
    var onQuote: (ConceptDefinition) -> Void
    var onFork: (ConceptDefinition) -> Void
    var onToggleSaved: (ConceptDefinition) -> Void
    var onToggleClipped: (ConceptDefinition) -> Void = { _ in }

    @State private var selectedScope: InsightLibraryScope?
    @State private var selectedIndex: Int = 0
    @State private var dragOffset: CGFloat = 0

    private var activeScope: InsightLibraryScope {
        selectedScope ?? (opensPassages ? .all : .currentConversation)
    }

    private var visibleInsights: [ConceptDefinition] {
        if opensPassages {
            let passages = activeScope == .all ? clippedPassages : currentConversationPassages
            return passages.filter(\.isLibraryQuote)
        }
        let insights = activeScope == .all ? allInsights : currentConversationInsights
        return insights.filter { !$0.isLibraryQuote }
    }

    private var pageCount: Int {
        visibleInsights.count
    }

    var body: some View {
        VStack(spacing: 24) {
            InsightLibraryScopeTabs(
                selectedScope: Binding(get: { activeScope }, set: { selectedScope = $0 }),
                opensPassages: opensPassages
            )

            if visibleInsights.isEmpty {
                InsightLibraryEmptyState(scope: activeScope, opensPassages: opensPassages)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    ForEach(Array(visibleInsights.enumerated()), id: \.element.id) { index, insight in
                        InsightLibraryCard(
                            insight: insight,
                            isSaved: insight.isLibraryQuote ? isClipped(insight) : isSaved(insight),
                            onQuote: { onQuote(insight) },
                            onFork: { onFork(insight) },
                            onToggleSaved: {
                                if insight.isLibraryQuote { onToggleClipped(insight) }
                                else { onToggleSaved(insight) }
                            }
                        )
                        .frame(maxWidth: 315)
                        .offset(x: CGFloat(index - selectedIndex) * 339 + dragOffset)
                        .opacity(abs(index - selectedIndex) <= 1 ? 1 : 0)
                        .allowsHitTesting(index == selectedIndex)
                    }
                }
                .frame(maxWidth: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            if value.translation.width < -42 {
                                showNextInsight()
                            } else if value.translation.width > 42 {
                                showPreviousInsight()
                            }
                            withAnimation(.insightCardBounce) {
                                dragOffset = 0
                            }
                        }
                )
                .animation(.insightCardBounce, value: selectedIndex)

                InsightLibraryPager(
                    selectedIndex: selectedIndex,
                    pageCount: pageCount,
                    onPrevious: showPreviousInsight,
                    onNext: showNextInsight
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(AngroveTheme.Colors.canvas)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InsightLibraryPopupHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
        .onChange(of: selectedScope) { oldValue, newValue in
            selectedIndex = 0
            dragOffset = 0
        }
        .onChange(of: pageCount) { oldValue, newValue in
            selectedIndex = min(selectedIndex, max(0, newValue - 1))
        }
        .onChange(of: opensPassages) { _, _ in
            selectedScope = nil
            selectedIndex = 0
            dragOffset = 0
        }
    }

    private func isSaved(_ insight: ConceptDefinition) -> Bool {
        savedInsights.contains { $0.word.caseInsensitiveCompare(insight.word) == .orderedSame }
    }

    private func isClipped(_ passage: ConceptDefinition) -> Bool {
        clippedPassages.contains { $0.id == passage.id }
    }

    private func showPreviousInsight() {
        guard pageCount > 0 else { return }
        withAnimation(.insightCardBounce) {
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    private func showNextInsight() {
        guard pageCount > 0 else { return }
        withAnimation(.insightCardBounce) {
            selectedIndex = min(pageCount - 1, selectedIndex + 1)
        }
    }
}

enum InsightLibraryScope {
    case currentConversation
    case all
}

private struct InsightLibraryScopeTabs: View {
    @Binding var selectedScope: InsightLibraryScope
    let opensPassages: Bool
    @Namespace private var selectedTabNamespace

    var body: some View {
        HStack(spacing: 0) {
            if opensPassages {
                tabButton(title: "All", scope: .all)
                tabButton(title: "This Conversation", scope: .currentConversation)
            } else {
                tabButton(title: "This Conversation", scope: .currentConversation)
                tabButton(title: "All", scope: .all)
            }
        }
        .padding(6)
        .background(AngroveTheme.Colors.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1)
        )
    }

    private func tabButton(title: String, scope: InsightLibraryScope) -> some View {
        Button {
            withAnimation(.springLively) {
                selectedScope = scope
            }
        } label: {
            Text(title)
                .font(.figtreeHeading3)
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .background {
                    if selectedScope == scope {
                        Capsule()
                            .fill(AngroveTheme.Colors.componentBackground)
                            .matchedGeometryEffect(id: "selected-insight-scope-tab", in: selectedTabNamespace)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct InsightLibraryCard: View {
    let insight: ConceptDefinition
    let isSaved: Bool
    var maxWidth: CGFloat? = 315
    var shadowOpacity: Double = 0.15
    var onQuote: () -> Void
    var onFork: () -> Void
    var onToggleSaved: () -> Void
    @State private var isConfirmingUnbookmark = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: insight.isLibraryQuote ? "books.vertical" : "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AngroveTheme.Colors.darkGreen)
                    .sfSymbolDrawOn()

                Text(insight.isLibraryQuote ? insight.word : insight.word.capitalized)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canQuote: true,
                    canFork: !insight.isLibraryQuote,
                    quoteAccessibilityLabel: insight.isLibraryQuote ? "Ask about passage" : "Quote",
                    tintColor: AngroveTheme.Colors.placeholderText,
                    saveTintColor: AngroveTheme.Colors.accentRed,
                    onSave: handleSaveTapped,
                    onQuote: onQuote,
                    onFork: onFork
                )
            }

            if insight.isLibraryQuote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("“\(insight.semanticDefinition)”")
                        .paragraphFont()
                        .lineSpacing(FlowLayout.rowSpacing)
                        .italic()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .fixedSize(horizontal: false, vertical: true)
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
                InsightDefinitionsContent(definitions: insight.contextualDefinitions)
            }
        }
        .padding(24)
        .frame(maxWidth: maxWidth)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(
            color: AngroveTheme.Colors.cardGlowBase
                .opacity(shadowOpacity),
            radius: 24,
            x: 0,
            y: 16
        )
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
}

struct InsightLibraryPopupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct InsightLibraryPager: View {
    let selectedIndex: Int
    let pageCount: Int
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .frame(width: 48, height: 48)
                    .background(AngroveTheme.Colors.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
            }
            .disabled(selectedIndex == 0)
            .opacity(selectedIndex == 0 ? 0.45 : 1)

            Text("\(min(selectedIndex + 1, pageCount))/\(max(pageCount, 1))")
                .font(.custom("LibreBaskerville-Regular", size: 14))
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                .frame(minWidth: 54)

            Button(action: onNext) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .frame(width: 48, height: 48)
                    .background(AngroveTheme.Colors.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
            }
            .disabled(selectedIndex >= pageCount - 1)
            .opacity(selectedIndex >= pageCount - 1 ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }
}

private struct InsightLibraryEmptyState: View {
    let scope: InsightLibraryScope
    let opensPassages: Bool

    private var title: String {
        if opensPassages {
            return scope == .all ? "No clipped passages yet" : "No passages in this conversation yet"
        }
        return scope == .currentConversation ? "No insights in this conversation yet" : "No saved insights yet"
    }

    private var message: String {
        if opensPassages {
            return scope == .all
                ? "Select text in the Library and tap Clip to collect passages here."
                : "Passages added to this conversation will appear here. Choose All to add a clipped passage."
        }
        return scope == .currentConversation
            ? "Tap an insight link in a response, then save it to collect it here."
            : "Saved insights will appear here across conversations."
    }

    private var symbol: String {
        opensPassages ? "books.vertical" : "text.bubble"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .sfSymbolDrawOn()

            Text(title)
                .font(.custom("LibreBaskerville-Regular", size: 22))
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                .multilineTextAlignment(.center)

            Text(message)
                .paragraphFont()
                .foregroundColor(AngroveTheme.Colors.bodyText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .background(AngroveTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}
