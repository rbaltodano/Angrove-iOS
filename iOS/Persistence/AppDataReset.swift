import BackgroundAssets
import Foundation
import UserNotifications
import WidgetKit

/// Removes app-owned data while leaving the installed app and its bundled resources intact.
@MainActor
enum AppDataReset {
    static func clear() async throws {
        let fileManager = FileManager.default
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw AppDataResetError.missingBundleIdentifier
        }

        // Drain queued writes before removing their backing stores, so pending work cannot
        // recreate data after the reset completes.
        SerializedPersonalStore.shared.invalidate()
        try InquiryPersistenceStore.eraseAll()

        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            try removeIfPresent(applicationSupport.appending(path: "Aquinas", directoryHint: .isDirectory))
            try removeIfPresent(applicationSupport.appending(path: "Models", directoryHint: .isDirectory))
            let recoveryArchives = try fileManager.contentsOfDirectory(
                at: applicationSupport,
                includingPropertiesForKeys: nil,
                options: []
            ).filter { $0.lastPathComponent.hasPrefix("Angrove Unreadable Data ") }
            for archive in recoveryArchives {
                try fileManager.removeItem(at: archive)
            }
        }

        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try removeContents(of: caches)
        }
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            try removeContents(of: documents)
        }

        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        DailyQuestionWidgetStore.discard()
        if let groupDefaults = UserDefaults(suiteName: DailyQuestionWidgetStore.appGroup) {
            groupDefaults.removePersistentDomain(forName: DailyQuestionWidgetStore.appGroup)
        }

        try LocalDataKeychain.remove(service: LocalDataCipher.personalService)
        try LocalDataKeychain.remove(
            service: "com.angrove.widget-data.v1",
            accessGroup: DailyQuestionWidgetStore.appGroup
        )

        if AppleHostedModelAssets.isAvailableLocally() {
            try await AssetPackManager.shared.remove(assetPackWithID: AngroveModelAssetPack.id)
        }

        URLCache.shared.removeAllCachedResponses()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        WidgetCenter.shared.reloadTimelines(ofKind: DailyQuestionWidgetStore.kind)
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func removeContents(of directory: URL) throws {
        for item in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try FileManager.default.removeItem(at: item)
        }
    }
}

private enum AppDataResetError: LocalizedError {
    case missingBundleIdentifier

    var errorDescription: String? {
        "Angrove couldn’t identify its local data container. Please restart the app and try again."
    }
}
