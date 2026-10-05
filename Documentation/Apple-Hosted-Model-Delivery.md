# Apple-hosted model delivery implementation

October 5, 2026. Implemented in the local working tree and verified with an unsigned Release
archive and simulator regression tests. A follow-up produced a signed archive, App Store
distribution IPA and essential `.aar` pack. Apple-hosted service behavior is **not yet validated**:
no pack has been uploaded or installed through TestFlight in this work.

## What is implemented

- `AngroveModelDownloader` is an ExtensionKit downloader using Apple's `StoreDownloaderExtension`
  default scheduling. It shares the app's configured App Group and is embedded under `Extensions`.
- App plist enables managed asset packs and Apple hosting.
- `AssetPacks/Gemma4-E4B.json` selects the pinned E4B model with an essential first-install/update
  policy, a versioned pack ID and a versioned relative model path.
- Release excludes `LocalModels` and `*.litertlm`; Debug retains the existing development seed
  and diagnostic override. The actual Release archive contained no `.litertlm` file.
- The runtime checks managed availability, resolves a process-local URL and verifies size and
  SHA-256 before initializing LiteRT. It does not make an Application Support model copy or read
  the entire model into a single buffer. Availability failure and corruption fail explicitly;
  a subsequent load can retry.
- The app constructs the local runtime even if an essential pack is not yet available, so a
  delayed download does not permanently select the unavailable-model implementation for that process.
- Download/verification stays outside the 60-second native-engine stall watchdog. SHA verification
  uses bounded chunks on a worker task and observes cancellation.

The initial implementation rechecks the digest on each managed cold load. Measure that cost on
phones before selecting a safe optimization. The old self-hosted installer remains an unused
primitive; Release preparation selects managed assets instead of its Application Support files.
There is no automatic deletion of old development/download artifacts or personal data.

## Prepare the artifact

From the repository root:

```sh
python3 scripts/package_model_asset.py
python3 scripts/package_model_asset.py --output build/asset-packs/Gemma4-E4B.aar
```

The first command checks the actual 3,659,530,240-byte file, its pinned SHA and the manifest with
Apple's packaging tool. The second additionally packages it at a new output path. Packaging,
uploading and hosted installation are separate operations; local packaging has now succeeded.
The script does not download weights, run inference or touch shelved research.

Upload and select the app/pack using the current App Store Connect workflow. Keep an immutable
pack ID/path per model hash. Do not replace the content of the current ID or call asset-manager
update/removal APIs while a native engine is using its file. A future model change needs new
constants/manifest, compatibility checks and update testing. URLs must never be persisted across
processes. See Apple's [URL contract](https://developer.apple.com/documentation/backgroundassets/assetpackmanager/url(for:))
and [download guide](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs).

## Remaining delivery gates

- [x] Implement dedicated readiness/progress/retry and low-storage messaging; fixture layouts
  and retry state logic are verified locally. Real UI taps and managed-service recovery remain pending.
- [ ] Exercise local managed-pack testing tools on first install, interruption, cancellation,
  low storage and app updates. The unit tests use small file fixtures, not the hosted service.
- [x] Provision the downloader and App Group; produce and inspect an App Store distribution IPA.
- [x] Package the verified model as `build/asset-packs/Gemma4-E4B.aar` (3,129,706,564 bytes).
- [ ] Upload the model and app; select the intended pack version for TestFlight.
- [ ] Verify a fresh TestFlight install, actual file resolution and first local generation.
- [ ] Measure hashing/install disk behavior and run sustained/offline/lifecycle tests on the minimum phone.
- [ ] Validate that pack/version updates cannot replace a live model and preserve personal data.

Essential policy participates in installation but does not eliminate interrupted-download recovery.
Do not check off the overall delivery gate until the real TestFlight evidence exists.

## Local distribution artifacts

- Archive: `build/release-audit/Angrove-signed.xcarchive` (development-signed archive input).
- App Store export: `build/release-audit/app-store-export/Angrove-iOS.ipa` (223,017,617 bytes).
- Pack: `build/asset-packs/Gemma4-E4B.aar`. Apple's archive tool lists the exact versioned model path.
- Inspection: `build/release-audit/distribution-packaging-report.json`.
- Artifact hashes: `build/release-audit/ready-artifacts.json`.

The exported app/widget/downloader have valid strict signatures, unexpired App Store profiles,
the same App Group and debugging disabled. The debug-only memory entitlement is absent. Build
1, version 1.0 is a local candidate; check App Store Connect for version/build conflicts before
uploading. The encryption declaration is still unset and upload toolchain acceptance is not yet proven.
Command-line validation authenticated but found no matching App Store Connect app record. Export success is not Apple processing or
TestFlight delivery success. Re-export after any declaration or source change.
