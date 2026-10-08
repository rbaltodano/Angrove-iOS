# TestFlight handoff — October 5, 2026

App version **1.0, build 2** uploaded successfully on October 5 at 16:34 EDT. Apple reported
that processing had started; completion has not yet been verified. The essential model pack
has not been uploaded, and internal TestFlight access has not yet been configured. Personal
device data has not been touched. Earlier sections below preserve the preparation history.

See the [pre-TestFlight check](Preflight-Check.md) for the fresh full-suite run, normal-launch
proof, corrected Settings checks and the remaining hands-on verification.

## Prepared and verified

- Settings/Model Tasks download state, progress, verification and recovery UI; 23 targeted cases
  passed, plus six fixture layouts in light/dark mode. UI taps and actual hosted progress still
  require checking.
- Integration-reviewed LiteRT API-reason manifests embedded in the exported SDK framework.
- Signed Release archive and App Store distribution export (version 1.0, build 1).
- App/widget/downloader strict signatures and App Store profiles, App Group, debugging-disabled
  entitlement, and absence of the debugging-memory entitlement verified.
- Essential Apple-hosted E4B `.aar` pack created from the pinned model, with the exact versioned
  path inspected through Apple's archive tool. Model source size and digest were verified first.

| Artifact | Local path | File bytes |
| --- | --- | --- |
| Stable App Store IPA | `build/stable-release/app-store-export/Angrove-iOS.ipa` | 222,891,319 |
| Essential model pack | `build/asset-packs/Gemma4-E4B.aar` | 3,129,706,564 |
| Stable distribution audit | `build/stable-release/packaging-report.json` | JSON report |
| Artifact hashes | `build/release-audit/ready-artifacts.json` | JSON record |

All paths are gitignored generated outputs. Byte counts describe local artifacts, not Apple's
processed delivery size or installed storage requirement. Any source/declaration change requires
rebuilding/re-exporting and updating the hashes before upload.

## App record created

Ryan created Angrove and supplied [App Store Connect record 6819392752](https://appstoreconnect.apple.com/apps/6819392752/distribution/ios/version/inflight).
The earlier zero-record lookup below is historical. A new authenticated validation run is
checking the record against the signed archive. Authenticated lookup now finds the supplied
Apple ID and expected bundle ID; build validation/acceptance remains separate.

Ryan supplied **Sine Viridian** as the developer name for release drafts; the app remains **Angrove**.
This records the owner's identity; it does not independently confirm Apple's account-display setting.

Ryan selected **United States only** for the initial public launch. This direction is recorded
locally; it has not yet been applied to App Store Connect availability. France-specific paperwork
is outside this launch scope; the full artifact still needs a justified encryption answer.

## Next check-offs

1. **Codex: validate the new app record; Ryan: select launch territories.**
   The command-line validation workflow authenticated successfully and its app lookup returned
   zero matching records for `com.ryanbaltodano.Aquinas-iOS`. This is a record blocker, not proof
   of a failed login. See the exact fields below. If an existing Angrove record uses a different
   bundle ID, reconcile that first instead of creating a duplicate.
2. **Codex: finish the encryption submission answer from the recorded inventory.** Apple OS
   encryption covers app storage; native ChaCha code serves RNG dependencies. The plist answer
   remains unset pending a justified classification. See [SDK audit](LiteRT-Privacy-Crypto-Audit.md).
   Account-side answers must reflect the entire distributed artifact and selected territories.
3. **Codex: reconcile the app record/build number, rebuild if needed, validate and upload the app
   and `.aar` pack using Apple tools, then verify processing.** Select the matching pack for the
   beta. Upload processing also establishes whether this installed Xcode build is accepted.
4. **Ryan with Codex assistance: verify a fresh supported-phone TestFlight install.** Preserve and
   verify a backup of existing Angrove data before any replacement/fresh-install procedure. The
   phone is currently unavailable to device tools. Confirm actual file resolution, checksum,
   first local generation, offline generation and download/error recovery.
5. **Ryan with Codex assistance: run lock/Keychain/backup restore, sustained memory/thermal and
   quality acceptance.** Complete model/corpus rights and device-support decisions before App
   Review submission. Those are separate from producing a valid IPA.

Source changes remain in the existing local working tree alongside unrelated work. No broad
commit, public-source publication, invitation, App Review submission or production release was
performed by this handoff.

## App record fields

In App Store Connect → Apps → + → New App:

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | Angrove (subject to Apple's availability check) |
| Primary language | English (U.S.) |
| Bundle ID | `com.ryanbaltodano.Aquinas-iOS` |
| SKU | `angrove-ios` (internal identifier; must be unused in this account) |

The exported binary supports iPhone and iPad (`UIDeviceFamily` 1,2), with minimum iOS 26.4.
Confirm intended device support before completing store screenshots and submission.
If Apple asks for an initial public developer name, Ryan chooses that account identity.
Once the record exists, copy its numeric Apple ID from App Information or send the app-page URL.
Do not select the `.Main`, `.ModelProbe`, `.QuestionOfTheDay` or `.ModelDownloader` identifier.

## Command-line validation attempt

The installed Xcode validation method requires destination `upload` even for its validation
workflow. The corrected run stopped during App Information lookup before artifact delivery.
The service response was successful (HTTP 200) with zero records for the exact bundle ID;
Xcode surfaced `Error Downloading App Information`. Nothing was uploaded, processed or installed.
Log: `/tmp/angrove-apple-validation.log`; private Xcode distribution logs are not public artifacts.
After the matching record exists, rerun validation before claiming Apple accepted the SDK/toolchain.

## Validation after record creation

The October 5 follow-up authenticated and found the matching record **6819392752** for
`com.ryanbaltodano.Aquinas-iOS`. Apple validation then rejected the archive with
**Unsupported SDK or Xcode version**. The installed toolchain is Xcode 27.0 beta
(`27A5194q`); no other Xcode installation was found. Log: `/tmp/angrove-record-validation.log`.

Rebuild with an Apple-supported release/RC toolchain, recheck packaging and refresh artifact
hashes before retrying validation. Only approximately 2 GiB of disk space is available, so a
second Xcode installation requires more space first. No build was made available to TestFlight
and no App Review submission was made. The existing IPA remains locally signed/packaged; it is
not an Apple-accepted candidate. US-only availability and the developer name were recorded
locally, not changed in App Store Connect.

## Stable Xcode installation follow-up

Installed from the Mac App Store: `/Applications/Xcode.app`, Xcode 27.0 build **27A266a**.
The installed binary reports this version and `xcodebuild -checkFirstLaunchStatus` succeeds.
The prior beta `/Applications/Xcode-beta.app` was preserved. Global `xcode-select` still points
to the beta, so release commands must explicitly select the stable installation:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

The previously rejected archive remains a beta-built artifact. Rebuild/export, refresh its
hashes and retry Apple validation before claiming that the new toolchain/build is accepted.
Approximately 19 GiB remained free after installation.

## Stable release rebuild

Rebuilt committed main **21ac6a6** using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
Signed Release archive: `build/stable-release/Angrove.xcarchive`. The app reports Xcode build
**27A266a**, SDK build **24A430**, version **1.0**, build **1**, minimum iOS **26.4**. Archive and
App Store distribution export both succeeded. No app code changed during this rebuild.

IPA: `build/stable-release/app-store-export/Angrove-iOS.ipa`, **222,891,319 bytes**, SHA-256
`fd1e75ff35e1a9f6e839b82ea844ab7eb75dff2268c9ab194ed2f9b8fec0b888`. The older beta-built IPA
is superseded. The model pack was preserved and not repackaged.

Local audit verifies strict signatures and unexpired App Store profiles for the app/widget/
downloader, shared App Group, debugging disabled, no debugging-memory entitlement, all privacy
manifests present and the model excluded from the IPA. The sole local packaging gate is the
unset encryption export declaration. Audit: `build/stable-release/packaging-report.json`.

Apple validation **passed**: `Validated Angrove-iOS`, `EXPORT SUCCEEDED`, process exit **0**.
Log: `/tmp/angrove-stable-validation.log`. This resolves the prior rejected-beta-toolchain gate
for this validation run. This validation workflow is separate from
publishing a TestFlight beta. Physical-device and hosted-service checks remain pending.

The device archive succeeded despite a simulator-service version mismatch warning. The
full unit suite was not rerun in this rebuild-only pass; previous preflight results are retained.
No owner device data was changed.

Next: finish the recorded encryption submission answer, upload the app and essential model pack,
verify Apple processing, and enable internal TestFlight testing. Validation success does not mean
the build is installed, a tester group has access, or encryption paperwork is complete.

## Build 2 upload — current status

Added `ITSAppUsesNonExemptEncryption = NO` using the integration assessment in
[LiteRT privacy/crypto audit](LiteRT-Privacy-Crypto-Audit.md), and incremented project build
numbers to 2. The candidate includes these local changes on top of main commit `21ac6a6`.
The app still encrypts stored data; this plist value classifies export compliance.

Stable Xcode archive/export succeeded. IPA: `build/stable-release/build2-export/Angrove-iOS.ipa`,
222,891,361 bytes, SHA-256
`52490cff304c8b32a0eb28e58807eebd0b156d00316740fc532c5e771d723e03`.
Local packaging audit reports zero blockers: `build/stable-release/build2-packaging-report.json`.
Actual app upload succeeded (exit 0, `Uploaded Angrove-iOS`, `EXPORT SUCCEEDED`) at 16:34 EDT.
Log: `/tmp/angrove-build2-upload.log`. Apple reported processing had started; this does not
confirm a processed or installable TestFlight build. Upload warned that the vendor
`CLiteRTLM.framework` dSYM was absent, which limits native SDK crash symbolication.

The unchanged essential model pack remains locally verified and **not uploaded**. Transporter
installation is waiting for the owner's Mac authentication. App Store Connect browser sign-in
is also pending. Signing into App Store Connect from a phone does not authenticate these Mac
sessions, but the owner can use the phone browser to inspect processing and configure an
internal group for their own account. Full AI testing still requires the hosted model pack.
No internal invitations, App Review submission or public release have been performed.

## Build 3 release candidate — October 8, 2026

Branch `claude/audit-fixes` (main `002bfd5` plus RC hardening). Changes since build 2: locked-phone
saves are retried instead of dropped; conversation backups no longer churn after idle periods or
collide within one second; import asks for confirmation and always backs up what it replaces;
conversations saved without newer fields still decode; photo/camera/file attachments are hidden
until after launch (`AttachmentAvailability.isEnabled`); the app is iPhone-only; archives include
a generated `CLiteRTLM.framework.dSYM` (function names only; the vendor ships no debug info).

Full serial suite: 424 tests in 70 suites passed. Stable Xcode 27A266a archive and App Store
export succeeded, version 1.0 build 3, `UIDeviceFamily` [1], no model in the bundle, LiteRT dSYM
UUID matches the shipped binary. Packaging audit of the exported app: zero blockers.
IPA (gitignored): `../build-output/rc-audit-release/export/Angrove-iOS.ipa`, SHA-256 `c8340a8362d71b9d4e2c25d9b83efc71fc2a8d29e6324192a8d34a3b34c51a51`.
Nothing was uploaded. Still required: upload the app and the essential model pack, verify
processing, then a fresh TestFlight install with model download on a supported iPhone.
