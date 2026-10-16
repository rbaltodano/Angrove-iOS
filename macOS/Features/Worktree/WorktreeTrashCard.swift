import SwiftUI

struct WorktreeTrashCard: View {
    let board: WorktreeBoard
    @State private var confirmsEmpty = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Trash")
                    .font(BrandTypography.font("Figtree-Bold", size: 18))
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                Spacer()
                Button("Empty") { confirmsEmpty = true }
                    .font(BrandTypography.font("Figtree-SemiBold", size: 14))
                    .foregroundStyle(AngroveTheme.Colors.accentRed)
                    .buttonStyle(.plain)
                    .disabled(board.recentlyDeleted.isEmpty)
            }
            if board.recentlyDeleted.isEmpty {
                Text("Trash is empty.")
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(board.recentlyDeleted, id: \.id) { item in
                            WorktreeTrashRow(item: item)
                                .draggable(WorktreeTrashDrop.payload(item.id, boardID: board.documentID))
                        }
                    }
                }
                .frame(height: min(CGFloat(board.recentlyDeleted.count) * 64 - 4, 360))
            }
        }
        .padding(28)
        .frame(maxWidth: 500)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1))
        .cardGlow()
        .alert("Empty Trash?", isPresented: $confirmsEmpty) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                withAnimation(reduceMotion ? nil : .springStandard) { board.emptyTrash() }
            }
        } message: {
            Text("All items in this Board’s Trash will be permanently deleted. This cannot be undone.")
        }
    }
}

private struct WorktreeTrashRow: View {
    let item: WorktreeStoredItem
    @State private var isHovered = false

    private var kind: LocalizedStringKey {
        if item.image != nil { return "Image" }
        if item.isHeading { return "Heading" }
        if item.branches != nil { return "Conversation" }
        if item.insight != nil { return "Insight" }
        if item.isHelp == true { return "Commands" }
        return "Note"
    }

    private var symbol: String {
        if item.image != nil { return "photo" }
        if item.isHeading { return "textformat.size" }
        if item.branches != nil { return MacIcon.conversations.symbol }
        if item.insight != nil { return "text.bubble" }
        if item.isHelp == true { return "command" }
        return "note.text"
    }

    private var preview: String {
        if item.isHeading { return item.text.capitalized }
        if let insight = item.insight { return insight.word }
        if let branches = item.branches { return item.label ?? item.sourceTitle ?? branches.first?.topQuestionText ?? "" }
        if item.isHelp == true { return String(localized: "Slash commands") }
        return item.text
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(0, (geometry.size.width - 24) / 2)
            HStack(spacing: 24) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityLabel(Text(kind))
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .frame(width: columnWidth, alignment: .leading)
                Group {
                    if let file = item.image {
                        WorktreeTrashImage(file: file)
                    } else {
                        Text(verbatim: preview)
                            .font(BrandTypography.font("Figtree-Regular", size: 14))
                            .foregroundStyle(AngroveTheme.Colors.paragraphText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
            }
            .frame(height: 44)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AngroveTheme.Colors.canvas.opacity(isHovered ? 0.5 : 0),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Drag onto the canvas to restore")
    }
}

private struct WorktreeTrashImage: View {
    let file: UploadedFile
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image, image.size.height > 0 {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 44 * image.size.width / image.size.height, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                AngroveTheme.Colors.canvas.frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .task(id: file.id) {
            guard let data = file.imageData else { return }
            image = await Task.detached(priority: .userInitiated) { NSImage(data: data) }.value
        }
        .accessibilityLabel("Image preview")
    }
}
