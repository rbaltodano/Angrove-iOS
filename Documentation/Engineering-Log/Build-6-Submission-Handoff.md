# iPhone build 6 submission handoff — October 17, 2026

## Upload status

Apple accepted the upload at 18:48 EDT on October 17. Xcode reported `Upload succeeded`,
`Uploaded package is processing`, and exit 0. Apple processing/availability has not yet been
verified in App Store Connect; no App Store review submission was made.

Upload produced non-blocking missing-dSYM warnings for `llama.framework` and the previously
documented zero-code ONNX compatibility framework. These affect native crash symbolication,
not the successful upload result. See `build/testflight-build6/logs/angrove-build6-upload.log`.
The recorded IPA hash identifies the retained local export; Xcode uploaded from the same final
archive through its own export pipeline.

## Candidate

- Angrove 1.0, build 6; production bundle ID `com.ryanbaltodano.Aquinas-iOS`.
- Stable Xcode 27.0 (27A266a); iPhone-only, minimum iOS 26.4, existing performance capability retained.
- Production model: Gemma 4 E4B, Apple-hosted essential pack `angrove-gemma4-e4b-0b2a8980`, version 2 (packaged with stable tooling).
- The model is absent from the distribution app bundle. The Debug-only Bonsai flag remains disabled in Release.
- Archive: `build/testflight-build6/Angrove-build6-final.xcarchive`.
- Distribution IPA: `build/testflight-build6/export-final/Angrove-iOS.ipa` (289,767,951 bytes).
- IPA SHA-256: `900210843f507d6b8e14551f9f31e955e5f4678f369473d46e42bcfe3855e235`.
- Packaging audit: `build/testflight-build6/packaging-report-final.json`, zero blockers.
- The installed development app on Ryan’s iPhone has not been replaced by this distribution build.

## Release preparation

The developer benchmark call is now compiled only in Debug, fixing the Release archive failure.
The iPhone app, widget and downloader version numbers are 6. Existing pending iPhone and Mac
interface work was checkpointed on main. The linked llama framework now includes its own elapsed-time
privacy declaration; see `Llama-Privacy-Packaging-Audit.md`. Framework binaries are unchanged.
The signed everyday Mac app was refreshed at `/Applications/Angrove.app` using the required installer.

## Verification

- Release archive and App Store distribution export succeeded using stable Xcode.
- Distribution inspection verifies app/extension provisioning, signatures, minimum OS, privacy
  manifests, managed-pack flags, and absence of bundled model weights, with zero blockers.
- Serial iPhone run: 577 of 578 tests passed. The sole failure was the historical visual expectation
  that dots remain visible at minimum tree zoom; current documented behavior hides them there.
  The corrected tree tests plus Insight navigation/notification/320-point light/dark layouts report
  15 tests passed in four suites. Xcode stalled while finalizing that focused result bundle after the Swift Testing completion
  message; the inactive runner was stopped. Its raw log is the evidence for the 15 passing tests,
  rather than a successful finalized `.xcresult`.
- Mac rerun: 260 of 261 tests passed after correcting test screenshot paths for App Sandbox and
  updating the disabled-snapshot fixture. The remaining fixed-delay reveal test was changed to
  await the first observed reveal update; its two-test suite then passed.
- Raw logs are `/tmp/angrove-build6-*.log`. Full serial iPhone results are under
  `build/workspace-layout-ios/Logs/Test/Test-Angrove-iOS-2026.10.17_18-36-55--0400.xcresult`.
- A final TestFlight install, Apple-managed model availability, offline generation and actual phone
  notification taps still require the owner’s check. Development/simulator success does not verify
  that distribution installation path.

## Owner walkthrough after Apple processing

1. In App Store Connect, open Angrove → TestFlight → iOS Builds and confirm 1.0 build 6
   completes processing. If Apple reports a warning or error, resolve it before review.
2. Install build 6 from TestFlight without deleting the existing app. Confirm model readiness,
   a normal answer, an Insight notification opening its card, and offline use after installation.
3. Open Distribution → iOS App Version 1.0 → Add Build. Select build 6 and save.
4. Verify App Information (including age rating), App Privacy, Pricing and Availability, and the
   screenshots. Existing copy, six screenshots, review contact information and manual release were
   already populated when inspected; those values were preserved. Confirm the approved essential
   Gemma asset-pack version is included for distribution/review as Apple requires.
5. Paste the reviewer notes below, review Apple’s outstanding-field messages, then Add for Review
   and perform the final submission when satisfied. Manual release remains the owner’s final launch
   control after approval.

## Suggested reviewer notes

No sign-in is required. Angrove runs its AI generation, source retrieval and Insight Tree locally
on supported iPhones. Version 1.0 build 6 uses an essential Apple-hosted Gemma model asset pack
(`angrove-gemma4-e4b-0b2a8980`; approximately 3.66 GB). Internet access is needed for
initial delivery. If interrupted, open Settings → On-device Model to check status and retry.

After installation, start a conversation and ask a philosophy, theology or history question.
Tap an underlined term to request its contextual definition. When the Insight completion
notification appears above Model Controls, tap it to open the completed card; saving adds it to
the Insight Library and conversation tree. Open source citations to inspect Library passages.
After model preparation, generation and retrieval work offline. AI output may contain mistakes.
Optional support reports are sent only by the person’s explicit action; conversations are not
sent to a remote inference service. Reviewer contact fields are already populated separately.

## Asset-pack review blocker and stable replacement — October 17, 19:23 EDT

The owner’s App Store Connect screenshot rejected asset-pack version 1 because it was created
with a beta Managed Background Assets tool. TestFlight readiness did not establish App Store
review eligibility. Build 6’s app binary was built with stable Xcode and is unaffected by this
packaging-only correction.

Repackaged the identical pinned Gemma file with stable Xcode’s `ba-package 2.0`:
`build/asset-packs/Gemma4-E4B-stable-20261017.aar` (3,129,706,547 bytes), SHA-256
`1fcb6b0730c1e80a5cc4f83e5c42a5b5bcb3f136e1bc9a113fac0c45ea3b9ce4`.
The embedded Manifest.json explicitly records `toolsVersion.isBeta: false`.
The pack ID, essential policy, destination path and model contents are unchanged. Corrected
its source path after the workspace move and made release packaging reject beta tool versions.
A negative check with `2.0-beta` exits before packaging and creates no archive.

Upload remains pending: the prior API key was not found in the conventional/local task credential
locations. Owner can add this `.aar` to Apple Transporter, select Angrove and click Deliver.
Apple will assign the replacement pack version on upload. Once processed, select that stable
version for App Review instead of version 1. No new app build is needed solely for this identical
model pack replacement. Actual Apple processing and review eligibility must still be verified.

[Apple: beta-packaged asset packs cannot be added for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-apple-hosted-asset-packs/).
