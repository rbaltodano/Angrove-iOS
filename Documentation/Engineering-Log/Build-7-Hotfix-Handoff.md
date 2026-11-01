# iPhone build 7 hotfix handoff — October 28, 2026

**Uploaded successfully at 19:25 EDT on October 28; Apple processing started.** Processing
completion and tester availability are not verified. No tester group assignment was performed.

Angrove 1.0 (7) contains the confirmed new-conversation persistence deadlock fix, based on
build 6's recorded release revision `fb128fc`. Source commit `60e0bdf` is retained on
`codex/ios27-chat-hotfix` in `~/Developer/Artifacts/ios27-chat-hotfix`.
The canonical checkout's unrelated pending work was preserved. Experimental boot-animation
changes and all temporary tracing were removed.

## Distribution artifacts

All paths below are relative to `~/Developer/Artifacts/ios27-chat-hotfix/`:

- Archive: `build/Angrove-1.0-build7-final.xcarchive`.
- Signed App Store Connect IPA: `build/export-final/Angrove-iOS.ipa`.
- IPA size: 289,773,773 bytes.
- IPA SHA-256: `56fdab1334f9542c1ea145e2a30a353fd78a7f47094c30c0e031aa818e8a31ca`.
- Provenance and final checks: `build/artifact-final.json`.
- Packaging audit: `build/packaging-report-final.json`, zero blockers.
- Resource parity: `build/resource-parity-final.json`, all 42 Library/retrieval resources
  match build 6 byte-for-byte. Native runtime UUID also matches build 6.
- Tester notes: `build/TestFlight-Notes.txt`.

## Verification

- Final source passed **579 tests in 104 suites**, zero failures, with a successful finalized
  Xcode result (`build/qa/Logs/Test/Test-Angrove-iOS-2026.10.28_15-12-26--0400.xcresult`).
- The Release simulator app rendered the new-chat composer on iPhone 16 Pro / iOS 27 in light
  and dark mode. Mounted message-submission and encrypted preference regression tests passed.
- Immediate simulator termination/relaunch sometimes produced a blank display. The identical
  symptom was reproduced in Apple's Settings app, and direct UIWindow drawing captured the
  complete chat and refreshed the simulator display. The simulator limitation and exact
  screenshots are retained in `build/ui-verification/`; not every restart was a visual pass.
- Release archive and App Store Connect distribution export succeeded with stable Xcode 27.0.
  The exported app and both extensions report 1.0 (7). Strict signature verification passed.
- No live model generation or physical-phone installation was performed. The essential model
  pack, runtime binary, encryption format, keys and storage locations are unchanged.

The required Library/retrieval inputs are excluded from Git. They were restored before final
testing and packaging; the packaging audit now rejects their absence. An unused developer
permissions settings file present in build 6 was not included.

## Next step

The owner subsequently authorized upload and tester delivery. Command-line Xcode upload succeeded
(exit 0), using `build/UploadOptions.plist`; receipt: `build/logs/testflight-upload.log`.
Wait for processing, then assign the processed build to the intended TestFlight tester group.
An App Store Connect API credential is not configured locally, so group assignment requires
API access or a manual owner action. Automatic internal availability is unverified.
Install through TestFlight without deleting the existing app, then
confirm a new conversation and first answer on the friend's phone.
