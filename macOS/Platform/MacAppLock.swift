import AppKit
import SwiftUI

/// The iPhone's App Lock on the Mac: Touch ID or the account password after Angrove has been
/// in the background, hidden, or behind a sleeping or locked screen for the grace period.
/// Unlike iPhone, an inactive window is not blanked, since Mac windows stay visible beside others.
struct MacAppLockHost<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var controller = AppLockController()
    @AppStorage(SettingsStorageKey.appLock) private var isEnabled = false
    @AppStorage(SettingsStorageKey.appLockGracePeriod) private var gracePeriod: AppLockGracePeriodOption = .immediately
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .overlay {
                if isEnabled && controller.isLocked {
                    AppLockGate(isAuthenticating: controller.isAuthenticating, errorMessage: controller.errorMessage,
                                onUnlock: controller.lockAndAuthenticate)
                        .transition(.opacity)
                }
            }
            .onAppear { controller.prepare(isEnabled: isEnabled) }
            .onChange(of: isEnabled) { _, enabled in controller.settingDidChange(isEnabled: enabled) }
            .onChange(of: scenePhase) { _, phase in update(phase) }
            .onReceive(NSApplication.publisher(for: NSApplication.didResignActiveNotification)) { _ in update(.inactive) }
            .onReceive(NSApplication.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in update(.active) }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
                update(.background)
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
                if NSApp.isActive { update(.active) }
            }
    }

    private func update(_ phase: ScenePhase) {
        controller.scenePhaseDidChange(phase, isEnabled: isEnabled, gracePeriod: gracePeriod.duration)
    }
}

private extension NSApplication {
    static func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }
}
