# Model delivery: Apple-hosted asset pack

The on-device model is too large to ship inside the app: stock E4B is 3.66 GB, and a fine-tuned
export about 4.1 GB, against the App Store's 4 GB app limit. TestFlight and App Store builds instead
get it from an **Apple-hosted Background Assets** pack (iOS 26+, owner decision 2026-09-30).

- **Essential download policy.** The system downloads the pack while it installs the app, so the
  model is on the device before first launch. The same applies to app updates.
- **No network code in the app.** The system downloads the pack; the app only reads it (AGENTS.md
  forbids an app-side HTTP model client).
- **Updates without a new app build.** A new pack version goes through App Store Connect and
  replaces the old one for every installed app version, so each pack must stay compatible with
  every app version in use.
- **Limits:** 200 GB total and 200 packs per app. See Apple's [size limits](https://developer.apple.com/help/app-store-connect/reference/app-uploads/apple-hosted-asset-pack-size-limits/)
  and the WWDC25 session [Discover Apple-Hosted Background Assets](https://developer.apple.com/videos/play/wwdc2025/325).

## In code

- `ModelAssetPack` (pack ID `AquinasModel`, model at `Models/<fileName>`) resolves the model
  through `AssetPackManager.url(for:)`. It is active only when `Info.plist` has
  `BAHasManagedAssetPacks`, so development builds are unaffected.
- `LiteRTModelStore.installedModelURL()` checks, in order: development override → asset pack →
  verified Application Support download → the bundled `LocalModels/` seed.
- `LiteRTAquinasRuntime.initializeEngine()` calls `ModelAssetPack.ensureAvailable()` before
  loading. This is a no-op when the pack is local, and re-downloads it if the system offloaded it.

## Building the pack

```sh
Tools/ModelAssetPack/package.sh
```

This writes `build/AssetPacks/AquinasModel.aar`. For stock E4B it is 3.13 GB. The model named in
`Tools/ModelAssetPack/manifest.json` must match `LiteRTModelManifest.aquinas`: the script checks
the size and prints the SHA-256 to compare.

## Remaining steps (need Xcode and App Store Connect)

1. **Downloader extension target.** In Xcode: File → New → Target → *Background Download*,
   choosing the Apple-hosted, managed option. Keep the generated `StoreDownloaderExtension` code.
2. **App group.** Add the same App Group (for example
   `group.com.ryanbaltodano.Aquinas-iOS.assets`) to both the app and the extension.
3. **App `Info.plist`:** `BAAppGroupID` = that group, `BAHasManagedAssetPacks` = YES,
   `BAUsesAppleHosting` = YES.
4. **Keep the model out of distribution builds.** Exclude `LocalModels/*.litertlm` from the
   archive used for TestFlight and the App Store, or the app is over 4 GB. Development builds keep
   bundling it.
5. **Upload.** Drop `AquinasModel.aar` into Transporter and deliver it to the app. It appears
   under TestFlight → asset packs. Then upload the app build.
6. **Test** with an internal TestFlight build. Delete the development app first, so the bundled
   seed can't mask a missing pack.

When the fine-tuned model replaces stock E4B, update `LiteRTModelManifest.aquinas` and the
manifest's `fileSource`/`fileDestination` together, then rebuild and upload a new pack version.
