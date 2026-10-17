import SwiftUI

/// One tier's Apple-hosted model: download, progress, verification and recovery. Progress comes
/// from Apple's download, not an estimate; verification is a separate indeterminate stage.
struct MacModelDownloadRow: View {
    let tier: MacModelTier
    let delivery: ModelDeliveryState

    var body: some View {
        MacSettingsRow(title: "\(tier.title) model", description: explanation) {
            control
        }
        .task { await delivery.refreshAvailability() }
    }

    @ViewBuilder private var control: some View {
        if case let .downloading(completed, total) = delivery.phase, total > 0 {
            VStack(alignment: .trailing, spacing: 6) {
                ProgressView(value: delivery.phase.fractionCompleted ?? 0)
                    .tint(AngroveTheme.Colors.lightGreen)
                Text("\(Self.bytes(completed)) of \(Self.bytes(total))")
                    .font(AngroveTheme.Typography.settingsDetail)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .monospacedDigit()
            }
        } else if delivery.phase.isBusy {
            ProgressView().controlSize(.small).accessibilityLabel(Text(delivery.phase.title))
        } else if let actionTitle {
            Button(actionTitle) { delivery.retry() }
                .accessibilityIdentifier("mac-model-delivery-\(tier.rawValue)")
        } else {
            Text("Ready").foregroundStyle(AngroveTheme.Colors.placeholderText)
        }
    }

    private var actionTitle: String? {
        switch delivery.phase {
        case .notInstalled: String(localized: "Download \(Self.bytes(tier.downloadByteCount))")
        case .available: String(localized: "Verify")
        case .failed: String(localized: "Retry")
        default: nil
        }
    }

    private var explanation: String {
        switch delivery.phase {
        case .checking: String(localized: "Checking whether the model is on this Mac.")
        case .notInstalled:
            tier == .standard
                ? String(localized: "Download the model to answer on this Mac. No conversation data is sent with the download.")
                : String(localized: "Downloads through Apple. No conversation data is sent with the download.")
        case .available: String(localized: "The download is present. Verify it before Angrove uses it.")
        case .waiting: String(localized: "Apple is preparing the download. Keep a connection available.")
        case .downloading: String(localized: "You can keep using Angrove while the model downloads.")
        case .paused: String(localized: "macOS paused the download. Check your connection and free space; it resumes when the system allows.")
        case .verifying: String(localized: "Checking the model before it can be used. This may take a little time.")
        case .ready, .development: tier.detail
        case let .failed(reason): String(localized: reason.message)
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, count), countStyle: .file)
    }
}

/// Home's notice while Standard isn't ready; hidden once it is, as on iPhone.
struct MacHomeModelDownloadCard: View {
    private let delivery = ModelDeliveryState.shared

    var body: some View {
        Group {
            if delivery.phase.showsStatus {
                VStack(alignment: .leading, spacing: 0) {
                    MacModelDownloadRow(tier: .standard, delivery: delivery)
                }
                .padding(.horizontal, 20)
                .background(AngroveTheme.Colors.canvasSecondary,
                            in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius)
                        .stroke(AngroveTheme.Colors.border, lineWidth: 1)
                }
                .transition(.opacity)
            }
        }
        .task { await delivery.refreshAvailability() }
    }
}
