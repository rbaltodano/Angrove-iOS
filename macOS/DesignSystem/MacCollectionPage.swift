import SwiftUI

/// The shared frame of the Mac collection pages (Conversations, Study Topics, Boards), in the
/// voice of the iPhone Home: an optional green eyebrow, the 40pt serif title, a short paragraph,
/// counts beneath it, then any actions. The space beside the heading stays open for artwork.
struct MacCollectionHeader<Actions: View>: View {
    var eyebrow: String? = nil
    let title: String
    let description: String
    var stats: [MacCollectionStat] = []
    /// A quiet line of counts set as paragraph text beneath the copy, in place of the stat row.
    var summary: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        text.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Only the title and the copy beneath it reveal; everything else on the page is still.
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
            }
            MacPageHeading(title: title, font: MacPageHeading.pageFont, color: AngroveTheme.Colors.primaryReadable)
                .lineSpacing(AngroveTheme.Typography.settingsGuideTitleLineSpacing)
            if !description.isEmpty {
                Text(description)
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .lineSpacing(7)
                    .settingsTextReveal()
                    .frame(maxWidth: 480, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if !stats.isEmpty {
                MacCollectionStats(stats: stats)
                    .padding(.top, 24)
            }
            if let summary {
                Text(summary)
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .monospacedDigit()
                    .padding(.top, 4)
            }
            if Actions.self != EmptyView.self {
                HStack(spacing: 12) { actions }
                    .padding(.top, 20)
            }
        }
    }
}

extension MacCollectionHeader where Actions == EmptyView {
    init(eyebrow: String? = nil, title: String, description: String, stats: [MacCollectionStat] = [], summary: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, description: description, stats: stats, summary: summary) { EmptyView() }
    }
}

struct MacCollectionStat: Identifiable {
    let value: String
    let label: String
    var id: String { label }

    init(_ value: Int, _ singular: String, _ plural: String) {
        self.value = value.formatted(.number)
        self.label = value == 1 ? singular : plural
    }
}

/// Counts set like the Home stats: a serif figure over a green label, divided by hairlines.
struct MacCollectionStats: View {
    let stats: [MacCollectionStat]

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(AngroveTheme.Colors.quietBorder)
                        .frame(width: 1, height: 52)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(stat.value)
                        .font(AngroveTheme.Typography.illustratedCardHeading)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(stat.label)
                        .font(AngroveTheme.Typography.uiLabel)
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.springStandard, value: stats.map(\.value))
    }
}

/// A serif section title with a quiet count, as the Library shelves set theirs.
struct MacCollectionSectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(AngroveTheme.Typography.title)
                .foregroundStyle(AngroveTheme.Colors.headingText)
            Spacer(minLength: 12)
            if let detail {
                Text(detail)
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Text tabs: the chosen one in green, the rest quiet.
struct MacCollectionTabs<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 24) {
            ForEach(tabs, id: \.0) { tab, label in
                Button {
                    withAnimation(.springQuick) { selection = tab }
                } label: {
                    Text(label)
                        .font(AngroveTheme.Typography.uiSubheading)
                        .foregroundStyle(selection == tab ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.placeholderText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
    }
}

/// The filled green capsule of the Home's “Tell me more…”.
struct MacPrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacCapsuleButtonBody(configuration: configuration, isPrimary: true)
    }
}

/// The quiet outlined capsule beside a primary action.
struct MacSecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacCapsuleButtonBody(configuration: configuration, isPrimary: false)
    }
}

private struct MacCapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .labelStyle(MacCapsuleLabelStyle())
            .font(AngroveTheme.Typography.uiSubheading)
            .foregroundStyle(isPrimary ? AngroveTheme.Colors.canvas : AngroveTheme.Colors.primaryReadable)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background {
                Capsule().fill(isPrimary ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.canvasSecondary)
                    .overlay {
                        if isPrimary {
                            Capsule().fill(AngroveTheme.Colors.canvas.opacity(isHovered ? 0.1 : 0))
                        } else {
                            Capsule().fill(AngroveTheme.Colors.systemSelection.opacity(isHovered ? 1 : 0))
                        }
                    }
            }
            .overlay {
                if !isPrimary { Capsule().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1) }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.springMicro, value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct MacCapsuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 12, weight: .bold))
            configuration.title
        }
    }
}

/// The ellipsis that opens a card's or page's options.
struct MacCollectionOptionsLabel: View {
    var size: CGFloat = 40
    /// Page actions sit in an outlined circle beside the capsules; cards show the bare ellipsis.
    var isOutlined = true

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .frame(width: size, height: size)
            .background(isOutlined ? AngroveTheme.Colors.canvasSecondary : .clear, in: Circle())
            .overlay(Circle().stroke(isOutlined ? AngroveTheme.Colors.controlBorder : .clear, lineWidth: 1))
            .contentShape(Circle())
    }
}

/// The resting card surface used across the collection pages.
struct MacCollectionCardSurface: ViewModifier {
    var radius: CGFloat = AngroveTheme.Spacing.cardRadius

    func body(content: Content) -> some View {
        content
            .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Cards lift slightly on hover, as the Home cards do.
struct MacCardHover: ViewModifier {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.008 : 1)
            .shadow(color: AngroveTheme.Colors.floatingShadow.opacity(isHovered ? 1 : 0), radius: 18, y: 6)
            .animation(.springQuick, value: isHovered)
            .onHover { isHovered = $0 }
            .pointerStyle(.link)
    }
}

extension View {
    func macCollectionCard(radius: CGFloat = AngroveTheme.Spacing.cardRadius) -> some View {
        modifier(MacCollectionCardSurface(radius: radius))
    }

    func macCardHover() -> some View { modifier(MacCardHover()) }
}

/// The scrolling page frame the collection pages share with Home and Library.
struct MacCollectionScrollPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) { content }
                .frame(maxWidth: MacCollectionLayout.contentMaxWidth, alignment: .leading)
                .padding(.top, MacConversationStyle.pageTopPadding)
                .padding(.bottom, 96)
                .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .background(AngroveTheme.Colors.canvas)
    }
}

enum MacCollectionLayout {
    /// Wider than reading pages so card grids reach three columns on a large window.
    static let contentMaxWidth: CGFloat = 1040
    static let gridSpacing: CGFloat = 20
}

enum MacCollectionDate {
    /// “Today”, “Yesterday”, a weekday this week, or a short date.
    static func short(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
