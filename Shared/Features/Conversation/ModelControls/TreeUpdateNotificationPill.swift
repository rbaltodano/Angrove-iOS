import SwiftUI

/// The nonmodal tree-update question shared by iPhone and Mac docks.
struct TreeUpdateNotificationPill: View {
    let title: String
    let onUpdate: () -> Void
    let onKeepCurrent: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button(action: onUpdate) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Update Insight Tree")
                Button(action: onKeepCurrent) {
                    Image(systemName: "xmark")
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Keep current Insight Tree")
            }
        }
        .font(AngroveTheme.Typography.uiLabel)
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .frame(width: 240, height: 50)
        .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
        .overlay { Capsule().stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}
