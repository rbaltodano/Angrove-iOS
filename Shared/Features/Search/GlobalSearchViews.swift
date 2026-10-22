//
//  GlobalSearchViews.swift
//  Angrove
//

import SwiftUI

/// The sidebar's Search row. It opens the global search overlay rather than editing in place.
struct SidebarSearchButton: View {
    /// Shows the ⌘K hint on the Mac.
    var showsShortcut = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GlobalSearchGlass()
                Text("Search")
                    .font(GlobalSearchBarStyle.font)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                Spacer(minLength: 8)
                if showsShortcut {
                    HStack(spacing: 4) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .bold))
                        Text(verbatim: "K")
                            .font(AngroveTheme.Typography.uiLabel)
                    }
                    .foregroundStyle(AngroveTheme.Colors.lightGreen.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AngroveTheme.Colors.lightGreen.opacity(0.15), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlobalSearchBarStyle())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityHint(showsShortcut ? Text("Command K") : Text(""))
    }
}

/// Full-window search over conversations, Insights, and Study Topics.
///
/// Opening grows the canvas veil from the top edge to the full height on the website's mobile
/// menu curve while the field fades in from a blur and settles from 105% to its normal scale.
/// Closing reverses both.
struct GlobalSearchOverlay: View {
    let isPresented: Bool
    let conversations: [InquiryConversation]
    /// The field's distance from the top of the overlay.
    var topInset: CGFloat = 48
    var horizontalInset: CGFloat = 48
    var maxContentWidth: CGFloat = 560
    /// Marks the keyboard-selected row, for arrow-key navigation on the Mac.
    var showsKeyboardSelection = false
    var onSelect: (GlobalSearchResult) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMounted = false
    @State private var isVeilRevealed = false
    @State private var isFieldRevealed = false
    @State private var query = ""
    @State private var scope: GlobalSearchScope = .all
    @State private var insights: [ConceptDefinition] = []
    @State private var studyTopics: [StudyTopic] = []
    @State private var selectedIndex = 0
    @FocusState private var isFieldFocused: Bool

    /// The website's mobile menu curve, `cubic-bezier(0.55, 0, 0.17, 1)`, run 50% faster.
    private static let veilAnimation = Animation.timingCurve(0.55, 0, 0.17, 1, duration: 0.47)
    private static let veilDismissAnimation = Animation.timingCurve(0.55, 0, 0.17, 1, duration: 0.33)
    private static let fieldDuration: TimeInterval = 0.17

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [GlobalSearchResult] {
        GlobalSearch.results(
            for: query,
            scope: scope,
            conversations: conversations,
            insights: insights,
            studyTopics: studyTopics
        )
    }

    var body: some View {
        // Measured with the keyboard ignored, so raising it never resizes the veil.
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if isMounted {
                    veil
                        .frame(height: isVeilRevealed ? geometry.size.height : 0)
                        .opacity(isVeilRevealed ? 1 : 0)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    // One scroll view over the whole overlay, so a downward swipe anywhere
                    // lowers the keyboard as it does on the conversation page.
                    ScrollView {
                        content
                            .padding(.horizontal, horizontalInset)
                            .padding(.top, topInset)
                            .padding(.bottom, 24)
                            .frame(maxWidth: maxContentWidth + horizontalInset * 2)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                            // Behind the rows and controls: only a tap on empty space closes search.
                            .background {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture(perform: onDismiss)
                            }
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(isPresented)
        .onChange(of: isPresented, initial: true) { _, presented in
            presented ? present() : dismiss()
        }
    }

    private var veil: some View {
        // Canvas at 98% through the upper page, easing to 75% at the bottom (Figma 1154:1325, flipped).
        let canvas = AngroveTheme.Colors.canvas
        return LinearGradient(
            stops: [
                .init(color: canvas.opacity(0.98), location: 0),
                .init(color: canvas.opacity(0.98), location: 0.445),
                .init(color: canvas.opacity(0.75), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                field
                    .blur(radius: isFieldRevealed || reduceMotion ? 0 : 8)
                    .scaleEffect(isFieldRevealed || reduceMotion ? 1 : 1.05)
                GlobalSearchScopePicker(selection: $scope)
            }

            // Like the Conversations page's search: rows that stop matching blur and fade away
            // while the rest slide into their new ranked order.
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    GlobalSearchResultRow(
                        result: result,
                        isSelected: showsKeyboardSelection && index == selectedIndex
                    ) {
                        onSelect(result)
                    }
                    .transition(.blurFadeShrink)
                    #if os(macOS)
                    .onHover { if $0 { selectedIndex = index } }
                    #endif
                }
            }
            .animation(.springQuick, value: results.map(\.id))

            if results.isEmpty, !trimmedQuery.isEmpty {
                AngroveEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No Matches Found",
                    message: scope.emptyMessage(for: trimmedQuery)
                )
                .padding(.top, 24)
                .transition(.blurFade)
            }
        }
        .animation(.springQuick, value: results.isEmpty && !trimmedQuery.isEmpty)
        .opacity(isFieldRevealed ? 1 : 0)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onChange(of: scope) { _, _ in selectedIndex = 0 }
    }

    private var field: some View {
        HStack(spacing: 8) {
            GlobalSearchGlass()
            TextField("", text: $query, prompt: Text("Search").foregroundStyle(AngroveTheme.Colors.placeholderText))
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .font(GlobalSearchBarStyle.font)
                .tint(AngroveTheme.Colors.secondaryMuted)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFieldFocused)
                .onSubmit(openSelection)
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
        }
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .modifier(GlobalSearchBarStyle())
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let count = results.count
        guard count > 0 else { return .ignored }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
        return .handled
    }

    private func openSelection() {
        let results = results
        guard results.indices.contains(selectedIndex) else { return }
        onSelect(results[selectedIndex])
    }

    private func present() {
        insights = InsightLibraryStore.load()
        studyTopics = StudyTopicStore.load()
        query = ""
        scope = .all
        selectedIndex = 0
        isMounted = true
        withAnimation(Self.veilAnimation) {
            isVeilRevealed = true
        }
        withAnimation(.easeOut(duration: Self.fieldDuration)) {
            isFieldRevealed = true
        }
        isFieldFocused = true
        // The field is inserted in this same update; focus once it exists.
        DispatchQueue.main.async { isFieldFocused = true }
    }

    private func dismiss() {
        guard isMounted else { return }
        isFieldFocused = false
        withAnimation(.easeIn(duration: Self.fieldDuration)) {
            isFieldRevealed = false
        }
        withAnimation(Self.veilDismissAnimation) {
            isVeilRevealed = false
        } completion: {
            guard !isPresented else { return }
            isMounted = false
        }
    }
}

/// The search bar's capsule, shared by the sidebar row and the open field (Figma 1154:1358 /
/// 1154:1404): Canvas Secondary with the Model Controls border.
struct GlobalSearchBarStyle: ViewModifier {
    static let font = BrandTypography.font("Figtree-SemiBold", size: 14)

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 24)
            .frame(height: 53)
            .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
            .overlay(Capsule().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
    }
}

struct GlobalSearchGlass: View {
    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AngroveTheme.Colors.searchIcon)
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

struct GlobalSearchScopePicker: View {
    @Binding var selection: GlobalSearchScope

    var body: some View {
        HStack(spacing: 24) {
            ForEach(GlobalSearchScope.allCases) { scope in
                Button {
                    selection = scope
                } label: {
                    Text(scope.title)
                        .font(AngroveTheme.Typography.uiLabel)
                        .foregroundStyle(
                            selection == scope
                                ? AngroveTheme.Colors.lightGreen
                                : AngroveTheme.Colors.placeholderText
                        )
                        .lineLimit(1)
                        .fixedSize()
                        // A taller target than the 12 pt label, without moving the row.
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == scope ? .isSelected : [])
            }
        }
        .padding(.vertical, -10)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

struct GlobalSearchResultRow: View {
    let result: GlobalSearchResult
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: result.iconName)
                    .font(.system(size: result.kind == .studyTopic ? 11 : 14, weight: .medium))
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .frame(width: 16, height: 16)
                Text(GlobalSearchHighlight.attributed(result))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .background(
                AngroveTheme.Colors.canvasSecondary,
                in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous)
                    .stroke(
                        isSelected ? AngroveTheme.Colors.lightGreen.opacity(0.5) : AngroveTheme.Colors.brownBorder,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Renders a result with each matching span in bold accent green.
enum GlobalSearchHighlight {
    static func attributed(_ result: GlobalSearchResult) -> AttributedString {
        let regular = AngroveTheme.Typography.body
        let bold = AngroveTheme.Typography.uiSubheading
        let baseFont = result.isPassage ? regular.italic() : regular
        let matchFont = result.isPassage ? bold.italic() : bold

        var output = AttributedString()
        var cursor = result.text.startIndex
        for match in result.matches where match.lowerBound >= cursor {
            output += segment(result.text[cursor..<match.lowerBound], font: baseFont,
                              color: AngroveTheme.Colors.paragraphText)
            output += segment(result.text[match], font: matchFont,
                              color: AngroveTheme.Colors.lightGreen)
            cursor = match.upperBound
        }
        output += segment(result.text[cursor...], font: baseFont, color: AngroveTheme.Colors.paragraphText)
        return output
    }

    private static func segment(_ text: Substring, font: Font, color: Color) -> AttributedString {
        var segment = AttributedString(String(text))
        segment.font = font
        segment.foregroundColor = color
        return segment
    }
}
