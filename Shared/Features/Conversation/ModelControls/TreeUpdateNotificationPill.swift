import SwiftUI

/// The nonmodal tree-update question shared by iPhone and Mac docks.
struct TreeUpdateNotificationPill: View {
    let title: String
    let onUpdate: () -> Void
    let onKeepCurrent: () -> Void

    var body: some View {
        ConfirmationNotificationPill(
            title: title,
            iconName: "point.3.connected.trianglepath.dotted",
            width: ModelCompletionNotificationList.cardWidth,
            confirmLabel: String(localized: "Update Insight Tree"),
            declineLabel: String(localized: "Keep current Insight Tree"),
            onConfirm: onUpdate,
            onDecline: onKeepCurrent
        )
    }
}

/// Compact question with fixed side padding and flexible space before its actions.
struct ConfirmationNotificationPill: View {
    let title: String
    let iconName: String
    let width: CGFloat
    let confirmLabel: String
    let declineLabel: String
    let onConfirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .frame(width: 14, height: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(confirmLabel)
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(declineLabel)
            }
        }
        .font(AngroveTheme.Typography.uiLabel)
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(width: width, height: 50)
        .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
        .overlay { Capsule().stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}
