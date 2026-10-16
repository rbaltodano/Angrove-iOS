// swift-tools-version: 5.9
// PrismML's llama.cpp fork (release prism-b10777-e3de715), which adds the PQ2_0 and PTQ1_0
// ternary packs Bonsai 2 ships in. The archive's tvOS and visionOS slices and dSYMs are removed.
// Source: https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10777-e3de715
// Archive SHA-256: a44662fdc7e7b97838335e7df181ad62ce769f82167d249cacb4b24ef42a9653

import PackageDescription

let package = Package(
  name: "LlamaCpp",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "llama", targets: ["llama"]),
  ],
  targets: [
    .binaryTarget(name: "llama", path: "Binaries/llama.xcframework"),
  ]
)
