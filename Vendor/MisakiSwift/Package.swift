// swift-tools-version: 6.0
// Vendored from https://github.com/mlalma/MisakiSwift (Apache-2.0). See ANGROVE.md for local changes.

import PackageDescription

let package = Package(
  name: "MisakiSwift",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    .library(name: "MisakiSwift", targets: ["MisakiSwift"])
  ],
  targets: [
    .target(
      name: "MisakiSwift",
      resources: [.process("Resources")]
    ),
    .testTarget(name: "MisakiSwiftTests", dependencies: ["MisakiSwift"]),
  ],
  swiftLanguageModes: [.v5]
)
