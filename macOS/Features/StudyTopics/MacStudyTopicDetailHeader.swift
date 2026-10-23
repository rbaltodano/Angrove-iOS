import SwiftUI

/// Inline fields occupy the title and description's normal positions, as on iPhone.
struct MacStudyTopicDetailHeader<Actions: View>: View {
    @Binding var title: String
    @Binding var description: String
    let titleFocusRequest: Int
    let conversationCount: Int
    let imageCount: Int
    @ViewBuilder var actions: Actions
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Study Topic".uppercased())
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
            TextField("", text: $title,
                prompt: Text("New Study Topic").foregroundStyle(AngroveTheme.Colors.primaryReadable), axis: .vertical)
                .macPlainField()
                .font(MacPageHeading.pageFont)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .lineSpacing(AngroveTheme.Typography.settingsGuideTitleLineSpacing)
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
                .focused($titleIsFocused)
                .opacity(title.isEmpty ? 0.5 : 1)
                .accessibilityLabel("Study Topic title")
            TextField("", text: $description,
                prompt: Text("Briefly describe the topic of this study").foregroundStyle(AngroveTheme.Colors.paragraphText), axis: .vertical)
                .macPlainField()
                .paragraphFont()
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .lineSpacing(7)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 8)
                .opacity(description.isEmpty ? 0.5 : 1)
                .accessibilityLabel("Study Topic description")
            MacCollectionStats(stats: [
                MacCollectionStat(conversationCount, "Conversation", "Conversations"),
                MacCollectionStat(imageCount, "Image", "Images")
            ])
            .padding(.top, 24)
            HStack(spacing: 12) { actions }
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: titleFocusRequest) {
            guard titleFocusRequest > 0 else { return }
            await Task.yield()
            titleIsFocused = true
        }
    }
}
