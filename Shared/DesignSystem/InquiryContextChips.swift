import SwiftUI

// MARK: - Context Chips

/// Small locked/removable pill above a question. Used for insights and response forks.
struct BranchContextChip: View {
    let title: String
    let icon: String
    var animationKey: String = "static"
    var isFilled: Bool = false
    var fillColor: Color = AngroveTheme.Colors.canvasSecondary
    var appearDelay: TimeInterval = 0
    var animatesAppearance: Bool = true
    var showRemove: Bool = false
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    /// When true: no padding, no background, no border — just icon + text.
    var isMinimal: Bool = false
    @State private var borderDrawProgress: CGFloat = 0
    @State private var isVisible: Bool = false
    @AppStorage("aquinas.settings.conversationFontSize") private var fontSize: ConversationFontSizeOption = .small

    /// Insight and Library quote titles follow the paragraph text size, as paragraphs do:
    /// the 14pt design size at Medium, moving with each step.
    private var quoteTitleFont: Font {
        BrandTypography.font(
            "Figtree-Bold",
            fixedSize: 14 + fontSize.pointSize - ConversationFontSizeOption.medium.pointSize
        )
    }

    private var isInsightChip: Bool {
        icon == "text.bubble" || icon == "text.bubble.fill"
    }
    private var isLibraryChip: Bool { icon == "books.vertical" }
    private var openLabel: String { "Open \(title) \(isLibraryChip ? "Library quote" : "Insight")" }
    private var removeLabel: String { "Remove \(title)" }

    private var labelContents: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .angroveIcon((isInsightChip || isLibraryChip) ? .medium : .small, .strong)
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .rotationEffect(icon == "arrow.triangle.branch" ? .degrees(90) : .degrees(0))
                .id(icon)
                .sfSymbolDrawOn(delay: appearDelay + 0.25)
            Text(title)
                .font((isInsightChip || isLibraryChip) ? quoteTitleFont : .figtreeChipLabel)
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var mainRegion: some View {
        if let onTap {
            Button(action: onTap) {
                paddedLabelContents
                    // Named on the content, as on the Mac a plain button's own label went unannounced.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(openLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(openLabel)
        } else {
            paddedLabelContents
        }
    }

    private var paddedLabelContents: some View {
        labelContents
            .padding(.leading, isMinimal ? 0 : 20)
            .padding(.trailing, showRemove ? 10 : (isMinimal ? 0 : 20))
            .padding(.vertical, isMinimal ? 0 : 16)
            .contentShape(Rectangle())
    }

    var body: some View {
        HStack(spacing: 0) {
            mainRegion

            if showRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .angroveIcon(.small, .strong)
                        .foregroundColor(AngroveTheme.Colors.darkGreen)
                        .sfSymbolDrawOn()
                        .padding(.trailing, isMinimal ? 0 : 20)
                        .padding(.vertical, isMinimal ? 0 : 16)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(removeLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(removeLabel)
            }
        }
        .background(isFilled && !isMinimal ? fillColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .inset(by: 0.5)
                .trim(from: 0, to: isMinimal ? 0 : borderDrawProgress)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear(perform: revealChip)
        .onChange(of: animationKey) { oldValue, newValue in
            if !isMinimal { drawBorder() }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func revealChip() {
        guard animatesAppearance else {
            isVisible = true
            borderDrawProgress = isMinimal ? 0 : 1
            return
        }

        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + appearDelay) {
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = true
            }
            if !isMinimal { drawBorder() }
        }
    }

    private func drawBorder() {
        borderDrawProgress = 0
        withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
            borderDrawProgress = 1
        }
    }
}

// MARK: - Connection Context Chip

struct ConnectionContextChip: View {
    let concepts: [ConceptDefinition]
    var onRemove: (() -> Void)? = nil
    @State private var borderDrawProgress: CGFloat = 0
    @State private var isVisible: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .angroveIcon(.xSmall)
                .foregroundColor(AngroveTheme.Colors.darkGreen)

            Text(concepts.map { $0.word.capitalized }.formatted())
                .font(.figtreeHeading2)
                .foregroundColor(AngroveTheme.Colors.darkGreen)
                .lineLimit(2)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .angroveIcon(.small, .strong)
                        .foregroundColor(AngroveTheme.Colors.darkGreen)
                        .sfSymbolDrawOn()
                }
                .padding(.leading, 4)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .inset(by: 0.5)
                .trim(from: 0, to: borderDrawProgress)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { isVisible = true }
            withAnimation(.easeOut(duration: 0.55).delay(0.05)) { borderDrawProgress = 1 }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Uploaded File Thumbnails
