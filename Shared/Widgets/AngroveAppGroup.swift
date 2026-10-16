import Foundation

/// The App Group the iPhone app shares with its extensions (widget data and its Keychain key).
///
/// On iPhone the group follows the running bundle: the production app and its extensions resolve
/// to `group.com.ryanbaltodano.Aquinas-iOS`, while a disposable probe build with its own bundle
/// IDs (`…Aquinas-iOS.ModelProbe`, see `ANGROVE_BUNDLE_ID` in the project) resolves to its own
/// group, so it can never read or change production's shared data. The Mac keeps the literal.
nonisolated enum AngroveAppGroup {
    static let production = "group.com.ryanbaltodano.Aquinas-iOS"

    static let identifier: String = {
        #if os(iOS)
        identifier(forBundleIdentifier: Bundle.main.bundleIdentifier)
        #else
        production
        #endif
    }()

    /// Extensions append a suffix to the app's bundle ID; the group is named after the app.
    private static let extensionSuffixes = [".ModelDownloader", ".QuestionOfTheDay"]
    private static let productionAppID = "com.ryanbaltodano.Aquinas-iOS"

    static func identifier(forBundleIdentifier bundleID: String?) -> String {
        // Test runners and anything unexpected keep the production group, as before.
        guard let bundleID, bundleID.hasPrefix(productionAppID) else { return production }
        let suffix = extensionSuffixes.first { bundleID.hasSuffix($0) }
        let appID = suffix.map { String(bundleID.dropLast($0.count)) } ?? bundleID
        return "group." + appID
    }
}
