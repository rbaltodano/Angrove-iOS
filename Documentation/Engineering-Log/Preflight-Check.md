# Pre-TestFlight check — October 5, 2026

This pass checks the current local working tree. Nothing was uploaded or submitted to App Review,
and the owner's phone and data were untouched. The goal is a private internal beta candidate;
real TestFlight installation is part of the remaining verification.

## Results

- Normal startup passed on a fresh iPhone 17e / iOS 27 simulator in light and dark mode. The
  encrypted-storage gate completed and Home displayed the empty state without visible clipping
  or overlap at standard text size. Proof: `build/preflight/ui/launch-verification.md` and PNGs.
- The full unit suite ran: **360 tests across 59 suites**, with 358 passing and two tests failing
  on stale Settings layout assumptions. All seven personal-data encryption tests passed,
  including ciphertext authentication, legacy migration, missing-key preservation, encrypted
  conversation backups, readable explicit exports and simulator App Group Keychain access.
  Persistence, conversation state, home, library, study/tree, citations, hosted-model recovery
  and production-runtime contract tests also passed. These are fixture/contract tests, not a
  fresh native model quality or performance run.
- Updated the two Settings tests to cover the current design: background cards precede the
  icon card in the scrollable page, and controls follow the explicit in-app font-size preference
  while accessibility sizes change their arrangement. Pixel checks still require the actual
  bundled icon previews, alignment, separation and horizontal containment. Text/layout checks
  still require system text growth, vertical reflow and no overlapping controls.
- The focused rerun of both Settings suites **passed all five tests**, including compact/standard
  widths and light/dark parameter cases. Combined with the full run, all 360 test definitions
  now have passing evidence; the entire suite was not rerun after the test-only corrections.
- Rechecked the distribution app and both extensions: strict signatures, unexpired App Store
  profiles, shared App Group, debugging disabled, no debugging-memory entitlement, privacy
  manifests present and model excluded from the IPA. Report:
  `build/release-audit/preflight-packaging-report.json`.
- IPA digest remains `8cabf4c58b9ca4ad1a1a3fd81c8ae9e6954f488d224d9077b6d87b5840080296`.
  This pass changed tests and documentation only; no app behavior or release binary changed.

Initial test evidence: `build/release-audit/preflight-tests-summary.json` and
`/tmp/angrove-preflight-tests.log`. Focused Settings rerun: `/tmp/angrove-preflight-settings-tests.log` and
`build/release-audit/preflight-settings-summary.json`. Rendered Settings PNGs are preserved in
`build/preflight/settings/`.

## Before uploading

1. Supply the matching App Store Connect app link/Apple ID. The earlier authenticated app lookup
   found no record for `com.ryanbaltodano.Aquinas-iOS`. Reconcile its version/build and territories.
2. Finish the encryption-export classification and account answer from the recorded SDK inventory.
   `ITSAppUsesNonExemptEncryption` remains unset; a valid signature does not resolve that answer.
3. Rebuild/export if declarations or app code change, then validate/upload the IPA and essential
   model pack and inspect Apple's processing. Existing hashes identify the current local artifacts.

## Test through the private beta

- Back up existing phone data before replacement/restore checks. Verify encrypted migration with
  real existing data, lock/unlock and backup restoration; simulator Keychain success does not
  establish physical-device recovery.
- Verify Apple-hosted essential-pack install/update, actual progress, interrupted downloads,
  low-storage recovery, Settings/Retry taps and offline first generation on supported hardware.
- Check sustained memory/thermals and response quality using the distribution build. Native
  networking observation and final privacy/rights answers remain outstanding.
- Complete hands-on navigation and accessibility checks. The available screenshot tools could
  not tap controls or inspect an accessibility hierarchy. Current Settings labels follow app
  text-size preferences; the rendering tests do not certify full Dynamic Type/VoiceOver support.

No observed app crash or encryption regression requires delaying local beta preparation. These
remaining gates mean the app is not yet verified for public release. See
[TestFlight handoff](TestFlight-Handoff.md) for artifact paths and the upload sequence.
