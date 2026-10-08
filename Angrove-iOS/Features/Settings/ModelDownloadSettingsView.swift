import SwiftUI

struct ModelDownloadSettingsView: View {
    var delivery: ModelDeliveryState = .shared

    var body: some View {
        SettingsDetailScaffold(title: "On-device Model") {
            VStack(alignment: .leading, spacing: AngroveTheme.Spacing.screenPadding) {
                if delivery.phase != .development {
                    SettingsControlCard {
                        ModelDownloadStatusView(delivery: delivery)
                    }
                }
                Text("The 3.66 GB model downloads through Apple during installation. If installation is interrupted, you can finish preparing it here. Once the model is ready, generation runs on your device without a connection.")
                    .font(AngroveTheme.Typography.settingsBody)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                Text("Downloading the model doesn’t upload your conversations. Keep enough free space for installation; the download and unpacking can need more room than the model file itself.")
                    .font(AngroveTheme.Typography.settingsDetail)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
            }
        }
        .task { await delivery.refreshAvailability() }
    }
}

/// Shared with the conversation's Model Tasks popup. Progress is supplied by Apple's download,
/// not by a timer estimating completion. Verification is a separate indeterminate stage.
struct ModelDownloadStatusView: View {
    let delivery: ModelDeliveryState

    @ViewBuilder
    var body: some View {
        if delivery.phase != .development {
            VStack(alignment: .leading, spacing: 12) {
                Text(delivery.phase.title)
                    .font(AngroveTheme.Typography.settingsHeading)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .accessibilityIdentifier("model-delivery-title")

                if case let .downloading(completed, total) = delivery.phase, total > 0 {
                    ProgressView(value: delivery.phase.fractionCompleted ?? 0)
                        .tint(AngroveTheme.Colors.headingText)
                    Text("\(ByteCountFormatter.string(fromByteCount: max(0, completed), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                        .font(AngroveTheme.Typography.settingsDetail)
                        .monospacedDigit()
                } else if delivery.phase.isBusy {
                    ProgressView().tint(AngroveTheme.Colors.headingText)
                        .accessibilityLabel(delivery.phase.title)
                }

                Text(explanation)
                    .font(AngroveTheme.Typography.settingsDetail)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)

                if canRetry {
                    Button(action: delivery.retry) {
                        Text(retryTitle)
                            .font(AngroveTheme.Typography.settingsLabel)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .accessibilityIdentifier("model-delivery-retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var canRetry: Bool {
        switch delivery.phase {
        case .notInstalled, .available, .failed: true
        default: false
        }
    }

    private var retryTitle: LocalizedStringResource {
        switch delivery.phase {
        case .available: "Verify model"
        case .notInstalled: "Download model"
        default: "Retry"
        }
    }

    private var explanation: LocalizedStringResource {
        switch delivery.phase {
        case .checking: "Checking whether the model is on this device."
        case .notInstalled: "Download the model to use local AI. No conversation data is sent with the download."
        case .available: "The download is present. Verify it before using local AI."
        case .waiting: "Apple is preparing the download. Keep a connection available."
        case .downloading: "You can leave this page while the model downloads."
        case .paused: "iOS paused the download. Check your connection and available storage; it resumes when the system allows."
        case .verifying: "Checking the model before it can be used. This may take a little time."
        case .ready: "The model passed its integrity check. It’s ready for on-device generation."
        case .development: ""
        case let .failed(reason): reason.message
        }
    }
}

#if DEBUG
/// Explicit development fixture for layout/recovery checks, never used by the release app.
struct ModelDownloadPreviewView: View {
    @State private var delivery = ModelDeliveryState(prepare: {
        try await Task.sleep(for: .milliseconds(200))
    })
    var body: some View {
        ModelDownloadSettingsView(delivery: delivery)
            .task {
                let args = ProcessInfo.processInfo.arguments
                let value = args.firstIndex(of: "--model-download-preview").flatMap { index in
                    args.indices.contains(index + 1) ? args[index + 1] : nil
                }
                switch value {
                case "storage": delivery.update(.failed(.storage))
                case "network": delivery.update(.failed(.network))
                case "integrity": delivery.update(.failed(.integrity))
                case "downloading": delivery.update(.downloading(completed: 1_830_000_000, total: 3_660_000_000))
                case "verifying": delivery.update(.verifying)
                case "ready": delivery.update(.ready)
                default: delivery.update(.notInstalled)
                }
            }
    }
}
#endif
