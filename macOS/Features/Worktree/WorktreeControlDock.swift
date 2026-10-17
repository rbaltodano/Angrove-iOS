import SwiftUI

/// The Worktree's model controls: Add, Tools, Model Tasks and Trash. Tools lists every command.
struct WorktreeControlDock: View {
    let board: WorktreeBoard
    let modelTasks: ModelTaskQueue
    let addEntries: () -> [MacMenuEntry]
    let toggleTools: () -> Void
    let toggleModelTasks: () -> Void
    let toggleTrash: () -> Void
    @State private var isPressed = false
    private var isTrashTargeted: Bool { board.trashTargetID != nil }

    var body: some View {
        HStack(spacing: 24) {
            MacActionMenu(entries: addEntries) {
                icon("WorktreePlus", width: 10, height: 10)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .frame(width: 21, height: 21)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
            .accessibilityLabel("Add")
            .modelControlHoverLabel("Add")

            Button(action: toggleTools) {
                label("Tools", icon: Image(systemName: "command")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true))
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
            }
            .accessibilityHint("Show every tool, command and shortcut")
            .modelControlHoverLabel("Tools")

            ModelStatusButton(modelTasks: modelTasks, action: toggleModelTasks, controlIsPressed: $isPressed)

            Button(action: toggleTrash) {
                label("Trash", icon: icon("WorktreeTrash", width: 10, height: 12))
                    .foregroundStyle(isTrashTargeted ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.paragraphText)
                    .scaleEffect(isTrashTargeted ? 1.12 : 1)
                    .animation(.springLively, value: isTrashTargeted)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { board.trashFrame = $0 }
            .accessibilityHint("Open recently deleted items, or drag an item here to delete it")
            .modelControlHoverLabel("Trash")
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1))
        .modelControlHoverPill()
        .modifier(FloatingControlPressFeedback(isButtonPressed: isPressed))
        .modelControlHoverOverlay(isVisible: true)
    }

    private func icon(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private func label(_ title: LocalizedStringKey, icon: some View) -> some View {
        HStack(spacing: 8) {
            icon
            Text(title)
                .font(BrandTypography.font("Figtree-SemiBold", size: 14))
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 21)
        .contentShape(Rectangle())
    }
}
