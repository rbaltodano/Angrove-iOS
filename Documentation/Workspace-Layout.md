# One checkout, three Codex projects

The canonical repository remains `~/Developer/Aquinas-iOS-main` on `main`. Both native app targets are configured in the existing `Angrove-iOS.xcodeproj`; target names, bundle IDs, app data locations, and model configuration are unchanged by this layout.

```text
Aquinas-iOS-main/
  iOS/                    iPhone-only source and resources
  macOS/                  Mac-only source and resources
  Packages/AngroveCore/   Swift package linked by both apps and both widgets:
                          encryption, App Group, widget store, model manifests
  Shared/                 source and resources compiled by both apps
    DesignSystem/
    Features/
    Models/
    Navigation/
    Persistence/
    Services/
    Widgets/              also compiled by both widget extensions
  Angrove-iOS.xcodeproj/
  Angrove-iOSTests/
  Angrove-macOSTests/
  AngroveWidgets/          widget source (iPhone and Mac widget targets)
  AngroveModelDownloader/ download extension source (iPhone and Mac)
  AssetPacks/             Apple-hosted model pack manifests
  Vendor/
  Documentation/
```

## Codex setup

Use three local Codex projects with these primary folders:

| Project | Primary folder |
| --- | --- |
| Angrove iPhone | `~/Developer/Aquinas-iOS-main/iOS` |
| Angrove Mac | `~/Developer/Aquinas-iOS-main/macOS` |
| Angrove Shared | `~/Developer/Aquinas-iOS-main/Shared` |

Attach `~/Developer/Aquinas-iOS-main` as a secondary folder to each project when folder access is scoped. This provides the Xcode project, tests, dependencies and cross-platform source for verification. Keep the area folder primary so its AGENTS.md defines the task's focus. Separate projects organize conversations; their ownership rules are conventions, not filesystem access barriers. Existing conversations keep their recorded working directory, so start new conversations from the updated projects.

## Automatic sharing

Both native targets include the same Xcode synchronized `Shared` group. A common source edit is read by both targets on their next build, and newly added Swift files in this group are discovered automatically. There is no mirror script, branch merge or file copying between these three folders. Platform edits stay in `iOS` or `macOS`. Shared changes can affect both apps; use a platform adapter for behavior that should differ.

## AngroveCore package (October 17, 2026)

`Packages/AngroveCore` holds the lowest, platform-neutral layer: `LocalDataCipher` and
`LocalDataKeychain`, `AngroveAppGroup`, `DailyQuestionWidgetStore` and its link, and the
`LiteRTModelManifest` / `AngroveModelAssetPack` data types. It may not import UIKit, AppKit or
SwiftUI, and only `public` declarations are visible to the apps, so the compiler enforces the
boundary. `Shared/Widgets/AngroveCoreExport.swift` re-exports it, so app and widget code uses
these types without imports. Its tests run without an app or simulator:

```sh
cd Packages/AngroveCore && swift test
```

More of `Shared` (models, persistence, the model runtime) can move in later steps once no other
work has uncommitted edits in those files. Move leaf types first; anything moved must become
`public` where the apps use it.

## Platform differences

Prefer a small policy value over `#if os(…)` in Shared code. `ModelPlatformPolicy`
(`Shared/Services`) describes how on-device models differ; each app defines
`ModelPlatformPolicy.current` in its own folder (`iOS/Services/ModelPlatformPolicy+iOS.swift`,
`macOS/Platform/ModelPlatformPolicy+Mac.swift`). The Mac's extra model packs, its
`Angrove-macOS` storage folder and its Background Assets guard live there. A one-line `#if` is
still fine; reach for a policy when a file gathers several.

## Build and test

Run from `~/Developer/Aquinas-iOS-main`, or `cd ..` from any area folder:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath build/workspace-layout-ios build

xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/workspace-layout-mac CODE_SIGNING_ALLOWED=NO build
```

Use the same schemes and destinations with `test` for behavior changes. Keep platform build outputs separate. A source-folder reorganization does not authorize running model probes or changing personal app data.

## Migration and recovery — October 14, 2026

The Mac port's committed and uncommitted source was integrated with the current iPhone checkout. The iPhone's pending tree return and conversation changes were retained. The existing `~/Developer/Archive/Worktrees/Aquinas-iOS-mac` worktree remains untouched as a historical recovery copy; it is not part of automatic sharing and should no longer be used for new work in this layout. Other existing task worktrees remain independent.

Pre-migration diffs, snapshots of changed files, the path mapping, and verification logs are saved locally under `build-output/workspace-migration-20261014/` (ignored by Git). Older research and build notes contain historical paths; use this document and the current Xcode project for current paths. Local model files were relocated with the iPhone source tree to `iOS/LocalModels`; no weights were downloaded, modified, or probed.

## Verification

- Both native targets build from the reorganized checkout.
- All 162 Shared Swift files are included exactly once in each app's compiler inputs.
- All 54 existing Mac tests pass. The Mac test host now uses an empty UI, matching iOS, so it does not open the owner's personal workspace or request its Keychain while testing.
- The signed simulator run reports all 35 selected iPhone tests passed: Insight Tree return, canvas persistence, and slash commands. Direct canvas-method tests now supply the stable camera reference exposed by the shared canvas API. Use normal simulator signing for Keychain tests; unsigned tests lack the required entitlement (`errSecMissingEntitlement`, -34018). Xcode report finalization stalled during a disk-space incident after the test library reported success; that reporting process was stopped, and its full `ios-test-signed.log` is preserved. The `.xcresult` for this run is incomplete.
- `plutil` validates the Xcode project and `git diff --check` passes. The historical Mac worktree's status and changed-file contents were preserved.

These checks validate integration and the folder migration, not new model performance or distribution readiness. No physical iPhone installation was performed.

The normal signed Mac release was rebuilt and installed as **Angrove** at `/Applications/Angrove.app`. The prior app bundle was archived in `build/mac-installed-backups/`. The initial install stopped before replacement when disk space ran out; session-created build caches and the partial backup were removed, and the retry completed.

The library document tooling test could not start because the available Python environments lack PyYAML (`yaml`). Its updated resource paths were checked against the relocated tree; the import failure is recorded in `library-tools-test.log`. All migration changes remain uncommitted so the owner can review them together with the preserved pending work.

## Developer directory cleanup

Historical worktrees are preserved under `~/Developer/Archive/Worktrees`, including the former Mac port. Backups, diagnostics, shelved standalone runtimes and the old showcase are grouped under `Archive/`. Artwork is under `Assets/`, and the previous workspace-level build/output folders are under `Artifacts/`. Active app, Foundations, Backend and evaluation repository paths are unchanged. See `~/Developer/Archive/README.md` for restoration instructions and the full relocation manifest. Other feature branches were preserved without merging them into the current app.
