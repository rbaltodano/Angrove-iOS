import SwiftUI

/// Explicit tap/hold routing avoids competing with Menu's own long-press presentation.
struct PhotoAttachmentControl: View {
    @Binding var isPressed: Bool
    /// While the recent photos card is open, a tap closes it instead of opening the menu.
    let isRecentPhotosOpen: Bool
    let onHold: () -> Void
    let onCloseRecentPhotos: () -> Void
    let onCamera: () -> Void
    let onPhoto: () -> Void
    let onFile: () -> Void
    let onInsights: () -> Void
    let onPassages: () -> Void
    @State private var isMenuOpen = false
    @State private var pendingAction: Task<Void, Never>?

    var body: some View {
        Button(action: handleTap) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(isRecentPhotosOpen ? 45 : 0))
                .animation(.springStandard, value: isRecentPhotosOpen)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: TapGesture())
                .onEnded { gesture in
                    switch gesture {
                    case .first:
                        isPressed = false
                        isMenuOpen = false
                        onHold()
                    case .second:
                        handleTap()
                    }
                }
        )
        .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
            AttachmentActionsMenu(
                onCamera: { select(onCamera) },
                onPhoto: { select(onPhoto) },
                onFile: { select(onFile) },
                onInsights: { select(onInsights) },
                onPassages: { select(onPassages) }
            )
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(isRecentPhotosOpen ? Text("Close recent photos") : Text("Add attachment"))
        .accessibilityHint(isRecentPhotosOpen
            ? Text("Tap to close the recent photos card.")
            : Text("Touch and hold to select a recent photo."))
        .accessibilityAction(named: Text("Select recent photo"), onHold)
        .onDisappear { pendingAction?.cancel() }
    }

    private func handleTap() {
        if isRecentPhotosOpen {
            onCloseRecentPhotos()
        } else {
            isMenuOpen.toggle()
        }
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
    let onCamera: () -> Void
    let onPhoto: () -> Void
    let onFile: () -> Void
    let onInsights: () -> Void
    let onPassages: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AttachmentActionRow(title: "Camera", icon: "camera", action: onCamera)
            AttachmentActionRow(title: "Photo", icon: "photo", action: onPhoto)
            AttachmentActionRow(title: "File", icon: "doc", action: onFile)
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
