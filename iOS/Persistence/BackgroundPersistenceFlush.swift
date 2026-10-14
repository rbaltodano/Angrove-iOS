import UIKit

/// An asynchronous barrier keeps the main actor responsive while iOS grants time for durability.
@MainActor enum BackgroundPersistenceFlush {
    static func begin() {
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save Angrove Data") {
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
                identifier = .invalid
            }
        }
        Task {
            await InquiryPersistenceStore.flushAsync()
            await SerializedPersonalStore.shared.flush()
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
    }

    /// Writes refused while the phone was locked are retried once protected data returns.
    static func retryDeferredWrites() {
        SerializedPersonalStore.shared.retryDeferredWrites()
        InquiryPersistenceStore.retryDeferredSave()
    }
}
