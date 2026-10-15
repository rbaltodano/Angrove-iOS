import SwiftUI

/// A sidebar conversation dragged onto the Worktree travels as a tagged string, so dropping it
/// elsewhere is harmless text.
enum WorktreeConversationDrop {
    private static let prefix = "angrove-conversation:"

    static func payload(_ id: UUID) -> String { prefix + id.uuidString }

    static func conversationID(in payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

/// The sidebar row's own chip: title on the selection fill with 12pt corners. It is the drag
/// preview, and what lands on the canvas before it opens into a window.
struct MacConversationChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AngroveTheme.Typography.body)
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(AngroveTheme.Colors.systemSelection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The chip that follows the pointer while a Worktree window is dragged over the sidebar. Drawn
/// above the whole workspace, since the canvas is clipped and sits beneath the sidebar.
struct WorktreeSidebarDragChip: View {
    let drag: WorktreeBoard.SidebarDrag?

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            if let drag {
                // Long titles truncate, as in the sidebar.
                MacConversationChip(title: drag.title)
                    .frame(maxWidth: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: drag.location.x - origin.x - 24, y: drag.location.y - origin.y - 22)
                    .transition(.blurFade)
            }
        }
        .allowsHitTesting(false)
    }
}
