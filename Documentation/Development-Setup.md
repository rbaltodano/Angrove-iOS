# Build and run Angrove

Angrove is in development. A source checkout can build the interface and run asset-independent
regression tests, but it does not contain the large model or full Library export. There is no
server to configure, account to create, or API key to supply.

## Prerequisites

- A Mac with Apple silicon and an Xcode installation containing an iOS SDK compatible with the
  project's iOS 26.4 deployment target. Current development uses Xcode's iOS 27.0 simulator.
- An installed **arm64** iPhone simulator. The vendored LiteRT-LM framework has no Intel simulator
  slice; a generic simulator destination cannot link it.
- For live inference, the exact model and grounding assets described below. Simulator results
  are useful for development; the supported physical-device matrix is still being established.

```sh
git clone https://github.com/rbaltodano/Angrove-iOS.git
cd Angrove-iOS
xcodebuild -version
xcrun simctl list devices available
open Angrove-iOS.xcodeproj
```

Use scheme **Angrove-iOS**. In Signing & Capabilities, select your development team for a phone
build, including the widget target and shared App Group/Keychain capabilities. Simulator builds
do not need a physical-device provisioning profile. The app still uses historical `Aquinas`
identifiers internally; do not rename them as a setup step.

## Build the source checkout

Use a concrete destination that appears in `simctl list`; substitute your installed OS version:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build
```

The local Swift package in `Vendor/LiteRTLM` includes the iOS framework and Swift wrapper.
Xcode may download package dependencies during the build. That development traffic is separate
from the app's on-device generation and retrieval boundary.

Without a verified model package, the app uses `UnavailableAngroveModel`: generation fails
explicitly. It does not silently substitute mock answers or call a cloud service. Without the
full grounding assets, the app can use a small built-in reference set and degraded semantic
clustering; that is not the full Library experience shown in the screenshots.

## Enable the full local experience

These directories are gitignored. Obtain the current development artifacts from the maintainer
or reproduce them using the offline corpus/export tooling in
[Angrove Backend](https://github.com/rbaltodano/Angrove-Backend). A self-service, versioned release
asset download is still a launch requirement; a clean clone is not a one-step inference demo.
Respect the model's terms and each corpus source's distribution terms.

| Resource path | Purpose |
| --- | --- |
| `Angrove-iOS/LocalModels/gemma-4-E4B-it.litertlm` | Stock instruction-tuned LiteRT Community model; not an Angrove fine-tune |
| `Angrove-iOS/LocalGrounding/MiniLM.mlpackage` | Core ML export of all-MiniLM-L6-v2; Xcode compiles it to `MiniLM.mlmodelc` |
| `Angrove-iOS/LocalGrounding/vocab.txt` | Matching WordPiece vocabulary |
| `Angrove-iOS/LocalGrounding/passages.json` | Library passages and source metadata |
| `Angrove-iOS/LocalGrounding/embeddings.bin` | Parallel normalized 384-dimensional float32 passage embeddings |

The current model manifest requires **3,659,530,240 bytes** and SHA-256
`0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
Verify the artifact before building:

```sh
stat -f '%z' Angrove-iOS/LocalModels/gemma-4-E4B-it.litertlm
shasum -a 256 Angrove-iOS/LocalModels/gemma-4-E4B-it.litertlm
```

Compare both values with `LiteRTModelManifest.angrove` in
[`LiteRTModelStore.swift`](../Angrove-iOS/Services/LiteRTModelStore.swift), which is authoritative
if the model changes. Keep the embedding model, vocabulary, passage metadata and vector export
from the same corpus build. `OnDeviceGroundingStore` rejects a vector-byte-count mismatch.

After building, inspect the actual `.app` resources to confirm the model, compiled MiniLM,
vocabulary, passages and embeddings were bundled. Launch on the selected simulator or phone
from Xcode. Live inference can require substantial disk, memory and time; the website's
interactive examples are illustrations rather than browser inference.

## Verify behavior

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:Angrove-iOSTests/ModelRuntimeLifecycleTests \
  -only-testing:Angrove-iOSTests/ModelActionAvailabilityTests test

python3 -m unittest discover -s scripts/tests -v
```

The Swift command checks lifecycle ownership and explicit action failure; it is not a model
quality benchmark. Some suites require real bundled grounding assets and explicitly skip when
those assets are absent. Report skips along with passes.

See [evaluation methodology and evidence](Evaluation.md) for quality checks and
[the development workflow](Development-Workflow.md) for physical-device safety, special-build
names and sustained validation. Preserve existing app data before device experiments.
