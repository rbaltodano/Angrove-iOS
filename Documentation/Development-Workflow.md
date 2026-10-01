# iOS development workflow

## Build and test

Run commands from the repository root:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Use an installed concrete arm64 simulator. `generic/platform=iOS Simulator` cannot link the
bundled LiteRT framework. When working from a worktree, verify that the project path passed to
`xcodebuild` belongs to that worktree rather than another local checkout.

## UI work

Use the Figma source of truth when a design node is available; do not approximate it from a
screenshot. Use `AngroveTheme` from `DesignSystem/SharedTypography.swift` for typography and
color. Before handing off UI work, check small phone widths, light and dark modes, navigation,
and empty states.

## Device work

Simulator checks are not final validation for model behavior. Run sustained model, thermal,
memory, and lifecycle checks on the base supported iPhone. Preserve user data: create and verify
an app-data backup before installing experimental local models or running device probes.

## Names for special iPhone builds

Every agent installing a build from a worktree other than the canonical
`~/Developer/Aquinas-iOS-main` checkout on `main` must name it
`<current main app name> – <work name>` using an en dash with spaces. This includes detached
worktrees and all installation methods.

Read the unsuffixed main app's `CFBundleDisplayName`, falling back to `CFBundleName`, to obtain
the base name. Use the owner's work name when provided; otherwise use a short readable task or
branch name, such as `Photo Selector` or `Friend Voice`. Do not infer the task from a stale
worktree directory name or append a second suffix to a previously named special build.

Set `INFOPLIST_KEY_CFBundleDisplayName` for the build, with the entire assignment passed as a
single shell argument. For example, when the base name is `Angrove`:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS,id=<device-id>' \
  -derivedDataPath '<worktree-specific-build-directory>' \
  'INFOPLIST_KEY_CFBundleDisplayName=Angrove – Photo Selector' build
```

Before installing, inspect the exact signed app being installed:

```sh
plutil -extract CFBundleDisplayName raw '<built-app-path>/Info.plist'
```

The value must match the required display name. If it is missing or different, rebuild with
the correct name before installing. Report the installed display name in the handoff.
Keep the main checkout's default name unchanged, and do not rename the target, executable, or
bundle identifier just to label a build. The suffix does not create a separate app/data
container; existing device-data preservation rules still apply.
