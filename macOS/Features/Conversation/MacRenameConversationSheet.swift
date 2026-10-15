import SwiftUI

struct MacRenameConversationSheet: View {
    let initialTitle: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPageHeading(title: "Rename Conversation")
            TextField("Conversation name", text: $title)
                .macPlainField()
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(AngroveTheme.Colors.canvas)
        .onAppear {
            title = initialTitle
            focused = true
        }
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
        dismiss()
    }
}
