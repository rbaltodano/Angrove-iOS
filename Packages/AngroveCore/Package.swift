// swift-tools-version: 6.0
import PackageDescription

/// Angrove's platform-neutral core, linked by both apps and both Question of the Day widgets.
/// Nothing here may import UIKit, AppKit or SwiftUI; the compiler enforces that, so platform code
/// can't leak into what the iPhone and Mac share. Tests run with `swift test`, without an app host.
let package = Package(
    name: "AngroveCore",
    platforms: [.iOS("26.4"), .macOS("27.0")],
    products: [.library(name: "AngroveCore", targets: ["AngroveCore"])],
    targets: [
        .target(name: "AngroveCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AngroveCoreTests", dependencies: ["AngroveCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
