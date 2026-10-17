import Testing
@testable import AngroveCore

/// The iPhone app's App Group follows its bundle ID, so a probe build can't share production's
/// widget data or Keychain key. Production must resolve exactly as before.
struct AngroveAppGroupTests {
    @Test(arguments: [
        "com.ryanbaltodano.Aquinas-iOS",
        "com.ryanbaltodano.Aquinas-iOS.ModelDownloader",
        "com.ryanbaltodano.Aquinas-iOS.QuestionOfTheDay",
    ])
    func productionAppAndExtensionsShareTheProductionGroup(bundleID: String) {
        #expect(AngroveAppGroup.identifier(forBundleIdentifier: bundleID) == "group.com.ryanbaltodano.Aquinas-iOS")
    }

    @Test(arguments: [
        "com.ryanbaltodano.Aquinas-iOS.ModelProbe",
        "com.ryanbaltodano.Aquinas-iOS.ModelProbe.ModelDownloader",
        "com.ryanbaltodano.Aquinas-iOS.ModelProbe.QuestionOfTheDay",
    ])
    func probeBuildsGetTheirOwnGroup(bundleID: String) {
        #expect(AngroveAppGroup.identifier(forBundleIdentifier: bundleID) == "group.com.ryanbaltodano.Aquinas-iOS.ModelProbe")
    }

    @Test(arguments: [nil, "", "com.apple.dt.xctest.tool", "com.ryanbaltodano.Angrove.macOS"] as [String?])
    func anythingElseKeepsTheProductionGroup(bundleID: String?) {
        #expect(AngroveAppGroup.identifier(forBundleIdentifier: bundleID) == AngroveAppGroup.production)
    }
}
