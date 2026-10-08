import SwiftUI

/// Launch attachment menu: saved Insights and Library passages only.
struct PhotoAttachmentControl: View {
    @Binding var isPressed: Bool
    let onInsights: () -> Void
    let onPassages: () -> Void
    @State private var isMenuOpen = false
    @State private var pendingAction: Task<Void, Never>?

    var body: some View {
        Button { isMenuOpen.toggle() } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
        .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
            AttachmentActionsMenu(
                onInsights: { select(onInsights) },
                onPassages: { select(onPassages) }
            )
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Add attachment")
        .accessibilityHint("Choose a saved Insight or Library passage.")
        .onDisappear { pendingAction?.cancel() }
    }

    private func select(_ action: @escaping () -> Void) {
        isMenuOpen = false
        pendingAction?.cancel()
        pendingAction = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

private struct AttachmentActionsMenu: View {
    let onInsights: () -> Void
    let onPassages: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AttachmentActionRow(title: "Insights", icon: "text.bubble", action: onInsights)
            AttachmentActionRow(title: "Passages", icon: "books.vertical", action: onPassages)
        }
        .padding(8)
        .frame(width: 200)
        .background(AngroveTheme.Colors.canvasSecondary)
    }
}

private struct AttachmentActionRow: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                Spacer()
                Image(systemName: icon)
                    .frame(width: 20)
            }
            .font(AngroveTheme.Typography.bodyLarge)
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .padding(.horizontal, 12)
            .frame(minHeight: AngroveTheme.Spacing.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
