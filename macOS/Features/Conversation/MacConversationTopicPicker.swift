import SwiftUI

struct MacConversationTopicPicker: View {
    let selectedID: UUID?
    let onSelect: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var topics = StudyTopicStore.load()
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPageHeading(title: "Study Topic")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button("No Study Topic") { onSelect(nil) }
                    ForEach(topics) { topic in
                        Button { onSelect(topic.id) } label: {
                            HStack {
                                Text(topic.title)
                                if topic.id == selectedID { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if topics.isEmpty { Text("No Study Topics yet. Create one below.").paragraphFont().settingsTextReveal() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                TextField("New Study Topic", text: $newTitle)
                    .macPlainField()
                Button("Create") {
                    let topic = StudyTopic(title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                    topics.append(topic)
                    StudyTopicStore.save(topics)
                    onSelect(topic.id)
                }
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("Cancel", role: .cancel) { dismiss() }
        }
        .font(AngroveTheme.Typography.body)
        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
        .padding(28)
        .frame(width: 380, height: 420)
        .background(AngroveTheme.Colors.canvas)
    }
}
