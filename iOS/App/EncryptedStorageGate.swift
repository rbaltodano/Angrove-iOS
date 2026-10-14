import Combine
import SwiftUI
import UIKit

/// Personal data migration and key validation finish before any feature reads or writes data.
struct EncryptedStorageGate<Content: View>: View {
    @State private var ready = false
    @State private var failure: Error?
    @State private var isConfirmingFreshStart = false
    let content: () -> Content

    var body: some View {
        ZStack {
            if let failure {
                failureView(failure)
            } else if ready {
                content()
            } else {
                ProgressView("Protecting your saved data…")
            }
        }
        .task { if !ready { await prepare() } }
        .onReceive(NotificationCenter.default.publisher(for: PersonalDataProtection.failureNotification).receive(on: RunLoop.main)) { notification in
            failure = notification.object as? Error ?? LocalDataEncryptionError.keychain(errSecInteractionNotAllowed)
            ready = false
        }
        // A locked phone makes the key temporarily unavailable. Retry once it unlocks rather than
        // waiting for a tap; integrity failures still need the person's decision.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            BackgroundPersistenceFlush.retryDeferredWrites()
            if let failure, !PersonalDataProtection.isIntegrityFailure(failure) {
                Task { await prepare() }
            }
        }
    }

    private func failureView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Text("Couldn’t Open Encrypted Data").font(AngroveTheme.Typography.body)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Try Again") { Task { await prepare() } }
            if PersonalDataProtection.offersFreshStart(error) {
                Button("Start Fresh…") { isConfirmingFreshStart = true }
            }
        }
        .padding(24)
        .foregroundStyle(AngroveTheme.Colors.primaryBrown)
        .confirmationDialog(
            "Start fresh?",
            isPresented: $isConfirmingFreshStart,
            titleVisibility: .visible
        ) {
            Button("Set Aside and Start Fresh", role: .destructive) { Task { await startFresh(after: error) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Angrove will move the data it can’t open into a separate folder on this iPhone and start with empty conversations and Insights. Nothing is deleted, but Angrove can only read that data again if its original key returns.")
        }
    }

    private func prepare() async {
        do {
            try await Task.detached(priority: .userInitiated) {
                try PersonalDataProtection.prepare()
            }.value
            failure = nil
            ready = true
        } catch {
            PersonalDataProtection.block()
            failure = error
            ready = false
        }
    }

    private func startFresh(after error: Error) async {
        var removesKey = false
        if case .invalidKey = error as? LocalDataEncryptionError { removesKey = true }
        do {
            try await Task.detached(priority: .userInitiated) {
                try PersonalDataProtection.startFresh(removeUnusableKey: removesKey)
            }.value
        } catch {
            failure = error
            return
        }
        await prepare()
    }
}
