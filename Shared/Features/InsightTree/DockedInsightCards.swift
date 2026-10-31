//
//  DockedInsightCards.swift
//  Angrove-iOS
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct DockedInsightTreeCard: View {
    let insight: InsightModel
    var isSaved: Bool = false

    /// When true, the body text fades/transforms/blurs in like a streamed model response.
    var animateIn: Bool = false
    /// Insight links grown under the card content while Make Node generates children — each
    /// appears in sync with its child's reveal haptic.
    var linkedInsights: [InsightModel] = []
    var onToggleSaved: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onFork:   (() -> Void)? = nil
    var onSelectLinkedInsight: ((InsightModel) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var textRevealed = false
    @State private var speechExpansionRequest = 0
    @State private var speechCollapseRequest = 0
    @State private var isPreparingSpeech = false
    @State private var hidesActionsForSpeech = false

    @Environment(\.speechSource) private var speechSource
    private var speech: ResponseSpeechPlayer { .shared }
    private var isReadingInsight: Bool { speech.phase(for: insight.definition) != .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: .small, delay: 0.18, color: AngroveTheme.Colors.lightGreen)

                Text(insight.title)
                    .font(BrandTypography.font("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: false,
                    copyText: definitionText,
                    speechText: definitionText,
                    tintColor: AngroveTheme.Colors.placeholderText,
                    saveTintColor: isSaved ? AngroveTheme.Colors.accentRed : nil,
                    onSave: onToggleSaved,
                    onSpeak: requestSpeechPlayback,
                    onFork: { onFork?() },
                    onClose: onClose
                )
                .opacity(hidesActionsForSpeech && onClose == nil ? 0 : 1)
                .allowsHitTesting(!hidesActionsForSpeech || onClose != nil)
                .accessibilityHidden(hidesActionsForSpeech && onClose == nil)
                .animation(.easeOut(duration: 0.2), value: hidesActionsForSpeech)

            }

            TruncatableParagraph(
                text: definitionText,
                speechText: definitionText,
                speechExpansionRequest: speechExpansionRequest,
                speechCollapseRequest: speechCollapseRequest,
                automaticallyCollapsesAfterSpeech: false,
                onSpeechExpansionComplete: startSpeechPlayback
            )
                .modifier(GlideFadeModifier(isActive: animateIn && !textRevealed))

            // Insight links grown one-by-one as Make Node reveals each child (on its haptic).
            if !linkedInsights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(linkedInsights, id: \.id) { linked in
                        DockedInsightLinkRow(insight: linked) { onSelectLinkedInsight?($0) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .contextMenu {
            if let onRemove {
                Button("Remove from conversation", systemImage: "trash", role: .destructive, action: onRemove)
            }
        }
        .onAppear {
            // The border + background fade in with the card; 0.15s later the body text
            // animates in (blur/fade/transform), like a streamed model response.
            guard animateIn else { return }
            textRevealed = false
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                textRevealed = true
            }
        }
        .onChange(of: isReadingInsight) { _, isReading in
            guard !isReading, !isPreparingSpeech, hidesActionsForSpeech else { return }
            withAnimation(.easeOut(duration: 0.2)) { hidesActionsForSpeech = false }
            // Let the action row and the paragraph's ellipsis return before folding the text.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                speechCollapseRequest += 1
            }
        }
        // Trim the bottom: the definition's .lineSpacing(12) leaves trailing space below the
        // last line, so a full 32 there reads as noticeably more space than the 32 up top.
        .dockedCardChrome(bottomPadding: 28, clipsContent: false)
    }

    private func requestSpeechPlayback() {
        guard !isPreparingSpeech, !isReadingInsight else { return }
        isPreparingSpeech = true
        speechExpansionRequest += 1
    }

    private func startSpeechPlayback() {
        guard isPreparingSpeech else { return }
        hidesActionsForSpeech = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard isPreparingSpeech else { return }
            speech.toggle(
                definitionText,
                units: CardSpeech.units(for: definitionText),
                source: speechSource
            )
            isPreparingSpeech = false
        }
    }

    private var definitionText: String {
        insight.definition.isEmpty || insight.definition.lowercased() == insight.title.lowercased()
            ? "This is an example of what an Insight Card will look like, the definition as relates to subject will be here"
            : insight.definition
    }
}

extension View {
    /// The docked Insight card's chrome: padding, full width, fill, 28 pt continuous corners,
    /// hairline border, and soft shadow. Shared so other docked cards match it exactly.
    /// `clipsContent` false lets content move past the card's edge (the Study tool card's
    /// sliding copy); the card itself looks the same.
    func dockedCardChrome(bottomPadding: CGFloat, clipsContent: Bool = true) -> some View {
        self
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(insightTreeInsightColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .modifier(DockedCardClip(isEnabled: clipsContent))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
            )
            .cardGlow()
    }
}

private struct DockedCardClip: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            content
        }
    }
}

/// A node concept's docked card. Shows its title, action buttons, and definition,
/// then lists links to its child/member insights underneath.
struct DockedNodeTreeCard: View {
    let node: NodeModel

    var isSaved: Bool = false
    var showsChildInsights: Bool = true
    var onSelectInsight: (InsightModel) -> Void
    var onToggleSaved: (() -> Void)? = nil
    var onFork: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleInsightCount = 0

    /// Fallback body when a node carries no definition of its own (auto clustered concepts).
    private var summaryText: String {
        let titles = node.insights.prefix(3).map(\.title)
        guard !titles.isEmpty else {
            return "\(node.conceptLabel) is a developing subject in this insight map."
        }

        return "\(node.conceptLabel) gathers related insights around \(titles.joined(separator: ", "))."
    }

    private var bodyText: String {
        node.definition.isEmpty ? summaryText : node.definition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                ConversationHeading(title: node.conceptLabel) { label in
                    Text(label)
                        .font(BrandTypography.font("Figtree-Bold", size: 18))
                        .foregroundColor(AngroveTheme.Colors.primaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: false,
                    copyText: bodyText,
                    speechText: bodyText,
                    tintColor: AngroveTheme.Colors.placeholderText,
                    saveTintColor: AngroveTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork,
                    onClose: onClose
                )

            }

            TruncatableParagraph(text: bodyText, speechText: bodyText)

            // Links to the concept's child / member insights.
            if showsChildInsights && !node.insights.isEmpty {
                DockedNodeInsightLinks(
                    insights: node.insights,
                    visibleInsightCount: visibleInsightCount,
                    onSelectInsight: onSelectInsight
                )
                .id(node.id)
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .cardGlow()
        .task(id: node.insights.map(\.id)) {
            visibleInsightCount = 0
            guard !node.insights.isEmpty else { return }
            for count in 1...node.insights.count {
                do {
                    try await Task.sleep(for: .milliseconds(110))
                    try Task.checkCancellation()
                } catch {
                    return
                }
                withAnimation(.easeOut(duration: 0.28)) {
                    visibleInsightCount = count
                }
            }
        }
    }
}

/// A node's member links stop growing after three rows. Scroll geometry controls the
/// edge fades so the first and last links remain fully readable at either endpoint.
private struct DockedNodeInsightLinks: View {
    let insights: [InsightModel]
    let visibleInsightCount: Int
    let onSelectInsight: (InsightModel) -> Void

    @State private var rowHeight: CGFloat = 20
    @State private var scrollEdges = ScrollEdges()

    private struct ScrollEdges: Equatable {
        var hasContentAbove = false
        var hasContentBelow = false
    }

    private var viewportHeight: CGFloat {
        let count = min(3, visibleInsightCount)
        return CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * 12
    }

    var body: some View {
        if insights.count > 3 {
            ScrollView(.vertical, showsIndicators: false) {
                DockedNodeInsightLinkRows(
                    insights: insights,
                    visibleInsightCount: visibleInsightCount,
                    onSelectInsight: onSelectInsight,
                    onMeasureRow: { rowHeight = $0 }
                )
            }
            .frame(height: viewportHeight)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                let remaining = geometry.contentSize.height + geometry.contentInsets.top
                    + geometry.contentInsets.bottom - geometry.containerSize.height - offset
                return ScrollEdges(
                    hasContentAbove: offset > 1,
                    hasContentBelow: remaining > 1
                )
            } action: { _, edges in
                scrollEdges = edges
            }
            .mask {
                DockedNodeScrollMask(hasContentAbove: scrollEdges.hasContentAbove,
                                     hasContentBelow: scrollEdges.hasContentBelow,
                                     edgeHeight: min(20, viewportHeight / 2))
            }
        } else {
            DockedNodeInsightLinkRows(
                insights: insights,
                visibleInsightCount: visibleInsightCount,
                onSelectInsight: onSelectInsight,
                onMeasureRow: { rowHeight = $0 }
            )
        }
    }
}

private struct DockedNodeInsightLinkRows: View {
    let insights: [InsightModel]
    let visibleInsightCount: Int
    let onSelectInsight: (InsightModel) -> Void
    let onMeasureRow: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(insights.prefix(visibleInsightCount)) { insight in
                DockedInsightLinkRow(insight: insight, onTap: onSelectInsight)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if height > 0 { onMeasureRow(height) }
                    }
                    .transition(.opacity)
            }
        }
    }
}

/// Fade only the links, revealing the card's own surface in every appearance.
private struct DockedNodeScrollMask: View {
    let hasContentAbove: Bool
    let hasContentBelow: Bool
    let edgeHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [AngroveTheme.Colors.mask.opacity(hasContentAbove ? 0 : 1), AngroveTheme.Colors.mask],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: edgeHeight)
            Rectangle().fill(AngroveTheme.Colors.mask)
            LinearGradient(colors: [AngroveTheme.Colors.mask, AngroveTheme.Colors.mask.opacity(hasContentBelow ? 0 : 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: edgeHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One tappable Insight link row — shared under both the insight and node concept cards for
/// child/member insights (bubble icon + underlined title in the muted link color). Appears with a
/// fade/rise/scale insertion so links added mid-animation (Make Node) glide in one at a time.
private struct DockedInsightLinkRow: View {
    let insight: InsightModel
    var onTap: (InsightModel) -> Void

    var body: some View {
        Button {
            onTap(insight)
        } label: {
            HStack(spacing: 8) {
                DockedCardTextBubbleIcon(size: .medium, delay: 0, color: AngroveTheme.Colors.lightGreen)

                // No minimumScaleFactor: it interacts with the insertion transition below and
                // locks later-inserted rows at a slightly reduced scale. Fixed size + truncation
                // keeps every link identical.
                Text(insight.title)
                    .font(BrandTypography.font("Figtree-Bold", size: 14))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Glide in with a fade + gentle rise. No .scale here — scaling the row makes the text's
        // layout resolve at a smaller size and it stays shrunk after the transition settles.
        .transition(.opacity.combined(with: .offset(y: 10)))
    }
}

struct DockedConceptCard: View {
    let concept: ConceptDefinition
    let isSaved: Bool
    var onToggleSaved: () -> Void
    var onFork: () -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: .small, delay: 0.18, color: AngroveTheme.Colors.lightGreen)
                Text(concept.word.capitalized)
                    .font(BrandTypography.font("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: false,
                    copyText: concept.semanticDefinition,
                    speechText: CardSpeech.text(for: concept),
                    tintColor: AngroveTheme.Colors.placeholderText,
                    saveTintColor: AngroveTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork,
                    onClose: onClose
                )

            }
            InsightDefinitionsContent(
                definitions: concept.contextualDefinitions
            )
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}

/// Docked card shown during Midpoint Selection mode: lists the selected insights and the
/// blend percentage of the new insight. For two insights the percentage is editable
/// (tap to type, drag to scrub); for 3+ the weights are shown read-only.
struct MidpointPercentCard: View {
    let concepts: [ConceptDefinition]
    let weights: [Double]
    var onSetPercent: (Int, Int) -> Void

    private var percents: [Int] {
        guard weights.count == concepts.count, !weights.isEmpty else { return [] }
        return weights.map { Int(($0 * 100).rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Midpoint")
                .font(BrandTypography.font("Figtree-Bold", size: 18))
                .foregroundColor(AngroveTheme.Colors.headingText)

            ForEach(Array(concepts.enumerated()), id: \.offset) { index, concept in
                row(index: index, concept: concept)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(index: Int, concept: ConceptDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .angroveIcon(.medium)
                .foregroundColor(AngroveTheme.Colors.lightGreen)
            Text(concept.word.capitalized)
                .font(BrandTypography.font("Figtree-Bold", size: 14))
                .foregroundColor(AngroveTheme.Colors.lightGreen)
                .lineLimit(1)
                .layoutPriority(1)

            DottedConnector()

            if let percent = index < percents.count ? percents[index] : nil {
                PercentStepper(
                    percent: percent,
                    onChange: { newValue in onSetPercent(index, newValue) }
                )
            }
        }
    }
}

/// `‹ XX% ›` percentage control: chevrons step by 1%, the number itself can be tapped to type
/// or dragged to scrub. Fires a light haptic for every 1% change.
private struct PercentStepper: View {
    let percent: Int
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            chevron("chevron.left") { step(-1) }
            EditablePercent(percent: percent, onChange: onChange)
            chevron("chevron.right") { step(1) }
        }
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .angroveIcon(.medium)
                .foregroundColor(AngroveTheme.Colors.headingText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        let newValue = min(100, max(0, percent + delta))
        guard newValue != percent else { return }
        CanvasImpactFeedback(style: .light).impactOccurred(intensity: 0.55)
        onChange(newValue)
    }
}

/// A faint dotted line that fills the available horizontal space.
private struct DottedConnector: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(
                AngroveTheme.Colors.paragraphText.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [1.5, 4])
            )
        }
        .frame(height: 1)
        .frame(maxWidth: .infinity)
    }
}

/// A percentage value that can be tapped to type an exact number or dragged horizontally to
/// scrub. Fires a light haptic for every 1% change while scrubbing.
private struct EditablePercent: View {
    let percent: Int
    var onChange: (Int) -> Void

    @State private var isEditing = false
    @State private var text = ""
    @State private var dragStartPercent: Int? = nil
    @State private var lastHapticPercent: Int = 0
    @State private var flashOpacity: CGFloat = 1.0
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($focused)
                    .font(BrandTypography.font("Figtree-Bold", size: 16))
                    .foregroundColor(AngroveTheme.Colors.headingText)
                    .fixedSize()
                    .opacity(flashOpacity)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                    .onAppear {
                        flashOpacity = 1.0
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            flashOpacity = 0.5
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(action: commit) {
                                Image(systemName: "checkmark")
                                    .angroveIcon(.large)
                                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                            }
                        }
                    }
            } else {
                Text("\(percent)%")
                    .font(BrandTypography.font("Figtree-Bold", size: 16))
                    .foregroundColor(AngroveTheme.Colors.headingText)
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        text = "\(percent)"
                        isEditing = true
                        focused = true
                    }
                    .gesture(scrubGesture)
            }
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartPercent == nil {
                    dragStartPercent = percent
                    lastHapticPercent = percent
                }
                let base = dragStartPercent ?? percent
                let delta = Int((value.translation.width / 4).rounded())
                let newValue = min(100, max(0, base + delta))
                if newValue != lastHapticPercent {
                    let generator = CanvasImpactFeedback(style: .light)
                    generator.impactOccurred(intensity: 0.55)
                    lastHapticPercent = newValue
                }
                if newValue != percent { onChange(newValue) }
            }
            .onEnded { _ in dragStartPercent = nil }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        focused = false
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits) else { return }
        onChange(min(100, max(0, value)))
    }
}

private struct DockedCardTextBubbleIcon: View {
    let size: AngroveTheme.IconSize
    var delay: TimeInterval = 0
    var color: Color = AngroveTheme.Colors.lightGreen
    @State private var isVisible = false

    var body: some View {
        Image(systemName: "text.bubble.fill")
            .angroveIcon(size)
            .foregroundColor(color)
            .scaleEffect(isVisible ? 1 : 0.86)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                isVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.springLively) {
                        isVisible = true
                    }
                }
            }
    }
}
