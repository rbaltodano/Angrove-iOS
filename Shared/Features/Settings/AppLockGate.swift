//
//  AppLockGate.swift
//  Angrove-iOS
//

import LocalAuthentication
import Observation
import SwiftUI

@MainActor
@Observable
final class AppLockController {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var authenticationTask: Task<Void, Never>?
    @ObservationIgnored private var leftActiveAt: Date?
    @ObservationIgnored private var hasPrepared = false

    func prepare(isEnabled: Bool) {
        guard !hasPrepared else { return }
        hasPrepared = true
        guard isEnabled else { return }
        lockAndAuthenticate()
    }

    func settingDidChange(isEnabled: Bool) {
        if isEnabled {
            lockAndAuthenticate()
        } else {
            authenticationTask?.cancel()
            authenticationTask = nil
            isAuthenticating = false
            isLocked = false
            errorMessage = nil
            leftActiveAt = nil
        }
    }

    func scenePhaseDidChange(
        _ phase: ScenePhase,
        isEnabled: Bool,
        gracePeriod: TimeInterval
    ) {
        guard isEnabled else {
            settingDidChange(isEnabled: false)
            return
        }

        switch phase {
        case .active:
            guard !isAuthenticating else { return }
            if let leftActiveAt,
               Date().timeIntervalSince(leftActiveAt) >= gracePeriod {
                lockAndAuthenticate()
            } else if !isLocked {
                errorMessage = nil
            }
            self.leftActiveAt = nil
        case .inactive, .background:
            // The LocalAuthentication sheet temporarily makes the app inactive. Recording that
            // transition would immediately re-lock an app that just authenticated.
            guard !isAuthenticating else { return }
            leftActiveAt = leftActiveAt ?? Date()
        @unknown default:
            leftActiveAt = leftActiveAt ?? Date()
        }
    }

    func lockAndAuthenticate() {
        isLocked = true
        errorMessage = nil
        authenticate()
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        authenticationTask?.cancel()
        isAuthenticating = true

        authenticationTask = Task { [weak self] in
            let context = LAContext()
            context.localizedCancelTitle = String(localized: "Cancel")
            var authorizationError: NSError?
            guard context.canEvaluatePolicy(
                .deviceOwnerAuthentication,
                error: &authorizationError
            ) else {
                self?.finishAuthentication(
                    errorMessage: String(
                        localized: "Set a device passcode before using App Lock."
                    )
                )
                return
            }

            do {
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: String(
                        localized: "Unlock your Angrove conversations."
                    )
                )
                guard !Task.isCancelled else { return }
                self?.isAuthenticating = false
                self?.isLocked = false
                self?.errorMessage = nil
                self?.leftActiveAt = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishAuthentication(
                    errorMessage: String(localized: "Angrove is still locked.")
                )
            }
        }
    }

    private func finishAuthentication(errorMessage: String) {
        isAuthenticating = false
        isLocked = true
        self.errorMessage = errorMessage
    }
}

struct AppLockGate: View {
    let isAuthenticating: Bool
    let errorMessage: String?
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvas
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AngroveTheme.Colors.darkGreen)

                Text("Angrove is Locked")
                    .font(AngroveTheme.Typography.uiHeading)
                    .foregroundStyle(AngroveTheme.Colors.headingText)

                Text(errorMessage ?? "Authenticate to continue your conversation.")
                    .font(AngroveTheme.Typography.body)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .multilineTextAlignment(.center)

                Button(action: onUnlock) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(AngroveTheme.Colors.canvas)
                    } else {
                        Label("Unlock Angrove", systemImage: "lock.open.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AngroveTheme.Colors.darkGreen)
                .disabled(isAuthenticating)
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
        .accessibilityAddTraits(.isModal)
    }
}
