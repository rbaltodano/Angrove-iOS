import SwiftUI

struct UserGuideSettingsView: View {
    var onSelectTopic: (UserGuideTopic.ID) -> Void
    var savedTerms: Binding<[String]> = .constant([])

    var body: some View {
        UserGuideWebsiteView(savedTerms: savedTerms, onSelectTopic: onSelectTopic)
            .ignoresSafeArea()
    }
}

/// One guide topic on its own page, pushed from `UserGuideSettingsView`.
struct UserGuideTopicView: View {
    let topic: UserGuideTopic
    @Binding var collectedDefinitions: [ConceptDefinition]
    var savedTerms: Binding<[String]> = .constant([])

    var body: some View {
        UserGuideWebsiteView(topicID: topic.id, savedTerms: savedTerms)
            .ignoresSafeArea()
    }
}

/// Guide pages use the Study Topic header: a large leading title, an optional description under
/// it, and the same spacing above, between, and below.
private struct UserGuidePageScaffold<Content: View>: View {
    let title: LocalizedStringResource
    /// Guide markup; see `UserGuideText`.
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(title)
                            .font(AngroveTheme.Typography.settingsGuideTitle)
                            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                            .lineSpacing(18)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        if let subtitle {
                            UserGuideText.text(subtitle)
                                .settingsText(.paragraph)
                                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                                .lineSpacing(FlowLayout.rowSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 48) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The intro is a paragraph of its own, so the first section gets the same
                    // 48pt of room as every section after it.
                    .padding(.top, subtitle == nil ? 20 : 48)

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 24)
                // Matches a Study Topic title: 24 + 72 above its text view, plus its 12pt inset.
                .padding(.top, 108)
            }
        }
    }
}

/// The collapsed "Show Technical Details" block under a topic.
private struct UserGuideTechnicalDetails: View {
    let sections: [UserGuideTechSection]
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button {
                SettingsHaptics.playSelection()
                withAnimation(.springStandard) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(isOpen ? "Hide Technical Details" : "Show Technical Details")
                        .settingsText(.label)
                    Image(systemName: "chevron.down")
                        .angroveIcon(.small)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sectionView(_ section: UserGuideTechSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)
            if let body = section.body { paragraph(body) }
            if !section.steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.custom("Figtree-Bold", size: 12))
                                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                                .frame(width: 24, height: 24)
                                .background(AngroveTheme.Colors.canvasSecondary, in: Circle())
                            paragraph("\(step.label). \(step.text)")
                        }
                    }
                }
            }
            if let formula = section.formula {
                Text(formula)
                    .font(AngroveTheme.Typography.formula)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AngroveTheme.Colors.canvasSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !section.table.isEmpty { tableView(section.table) }
            if let note = section.note { paragraph(note) }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .settingsText(.paragraph)
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .lineSpacing(FlowLayout.rowSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tableView(_ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        Text(verbatim: cell)
                            .font(.custom(index == 0 ? "Figtree-Bold" : "Figtree-Regular", size: 13))
                            .foregroundStyle(index == 0 ? AngroveTheme.Colors.headingText : AngroveTheme.Colors.paragraphText)
                            .frame(maxWidth: column == row.count - 1 ? .infinity : 64, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 10)
                if index < rows.count - 1 {
                    Divider().overlay(AngroveTheme.Colors.brownBorder)
                }
            }
        }
    }
}

private struct UserGuideTopicRow: View {
    let topic: UserGuideTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: topic.icon)
                    .angroveIcon(.medium, .navigation)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(topic.title)
                    .settingsText(.control)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .angroveIcon(.small)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this guide")
    }
}

private struct UserGuideParagraph: View {
    let title: LocalizedStringResource
    /// Guide markup; see `UserGuideText`.
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)
            UserGuideText.text(text)
                .settingsText(.paragraph)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .lineSpacing(FlowLayout.rowSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("User Guide · Light") {
    UserGuideSettingsView(onSelectTopic: { _ in })
        .preferredColorScheme(.light)
}

#Preview("User Guide Topic · Dark") {
    UserGuideTopicView(topic: UserGuideTopic.all[0], collectedDefinitions: .constant([]))
        .preferredColorScheme(.dark)
}
