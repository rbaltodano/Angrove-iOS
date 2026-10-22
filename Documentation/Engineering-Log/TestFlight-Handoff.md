# TestFlight handoff — October 12, 2026

**Build 4 was rejected during Apple processing (ITMS-90208).** Successful upload did not mean
successful processing. The copied ONNX compatibility framework declared iOS 15.1 despite having
a binary minimum of 26.4. This was a missing check in the local packaging audit.

**Build 5 corrects this mismatch and uploaded successfully at 12:47 EDT on October 12.**
Apple reported that processing started. App Store Connect API now confirms build 5 is
`VALID`, its internal state is `IN_BETA_TESTING`, and it belongs to Personal Testing.
Its external state is `READY_FOR_BETA_SUBMISSION`; the Beta Testers external group has no builds. Its simulator build, Release archive,
and distribution export succeeded. The exact exported IPA now passes minimum-OS checks for the
app, both extensions, and both frameworks, with strict framework signature verification. The
updated audit also rejects the old build 4 package for the exact mismatch Apple reported.

Build 5 artifacts are in `build/testflight-build5/`. The automatic final build phase corrects the
copied ONNX plist to its actual binary target, then re-signs the framework. It does not change the
runtime binary, app deployment target, or Insight Tree fixes. See the
[packaging correction evidence](ONNX-Release-Packaging-Audit.md).

**Internal TestFlight delivery is complete.** The essential model pack uploaded successfully
through altool (exit 0). Apple confirms version 1 of `angrove-gemma4-e4b-0b2a8980` has
import state COMPLETE and internal beta release state READY_FOR_TESTING. Build 5 is VALID,
IN_BETA_TESTING, and assigned to Personal Testing. Actual phone download and first AI generation
remain to be checked; external beta submission/approval is separate.
Personal phone data has not been touched.

## Model-pack follow-up — October 12

The owner reported the ready-to-test notification and requested finishing model delivery.
Reverified the existing 3,129,706,564-byte archive SHA-256 as
`cee085f9b7229191d73d0cd81b8a076d8de9458035321b2c889abf28f5947040`.
Apple Archive listing confirms the model at
`Contents/Models/angrove-gemma4-e4b-0b2a8980/gemma-4-E4B-it.litertlm`, matching the
production delivery code and essential manifest. No app/model source changes were needed.

Transporter accepted and examined the archive, and the signed-in app lookup exposes
**Angrove, 6819392752**. Its chooser still does not apply the selection through accessibility or
keyboard controls, including after centering the window. The pack is **not delivered**.
After renewed owner authorization, computer-use retries included a Transporter restart,
re-adding the archive, direct mouse input, accessibility selection, keyboard navigation, and
list scrolling. The picker still did not apply Angrove; Add remains disabled.
The app picker is left open for the owner to select Angrove and click Add; delivery and
processing verification still remain afterward. Command-line alternatives require a separately
available app-specific password or App Store Connect API credential; none is configured for this
workflow. Do not expose or extract existing account tokens to bypass this blocker.

Apple documents that internal testing automatically uses the latest processed pack; another app
build is not required solely to deliver this unchanged pack. External testers require the pack's
TestFlight App Review approval as well as the app build's approval:
[Apple-hosted asset pack testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-apple-hosted-asset-packs).

## Build 4 changes and evidence

- Global Insights opens at normal zoom with its saved content visible immediately. Only exact
  additions accepted by pressing Yes receive the update tour. Automatic concept bookmarks and
  completed Make Node branches do not start a tour on reopening.
- Child Insight card selections issue an explicit camera request, including reselection of the
  same ID; stale search focus is cleared and any active entrance tour is cancelled.
- Home accessibility corrections retain readable history headings, a usable New Conversation
  dock label, and stacked statistics on accessibility text sizes.
- Empty former source concepts are hidden after Midpoint transfer while explicitly selected
  source nodes remain available. Global label-queue tests isolate persistent state per case.
- Complete regression: 539 tests in 91 suites passed. After the final camera gate adjustment,
  55 focused tests in 6 suites passed. Small-phone global canvas fixtures were visually checked
  in light/dark. Actual child-card taps and owner-phone model/lifecycle checks remain unverified.
- Stable Xcode 27.0 (27A266a), version 1.0 build 4, production bundle ID, iPhone-only device
  family, strict distribution signatures, profiles, App Group and Apple-hosted pack flags verified.
  Final exported packaging audit has no blockers. The model is absent from the application bundle.
- Apple warned that `onnxruntime.framework` has no dSYM for UUID
  `995FD603-42C9-3FED-8414-90E7DFE3A106`. This exported framework is the zero-code static-link
  compatibility stub, with no symbols; the real runtime is linked into the app. See the
  [ONNX packaging evidence](ONNX-Release-Packaging-Audit.md). Upload still succeeded.

Artifacts and logs are under `build/testflight-build4/`: `Angrove-build4-final.xcarchive`,
`export-final/Angrove-iOS.ipa`, `artifact-final.json`, `source-record.json`, `source.patch`,
`regression-final.log`, `camera-final.log`, `packaging-report-final.json`, and `upload-final.log`.
The prepared export is 280,352,760 bytes, SHA-256
`a94d2b7be24f4ab4823afbc3a0b75b3a1f285b8d674e83727364775243db6c96`.
Xcode uploads from the final archive through its own distribution pipeline.

## Remaining TestFlight steps

1. Install/update build 5 through TestFlight on a supported iPhone, preserving existing app data.
   Verify the hosted model download and first local generation, normal Insights opening,
   Yes-update focus, and child-card camera pan in global and conversation trees. No fresh
   uninstall or container reset was performed or is required by this handoff.
2. For people outside the App Store Connect team, submit the app build and model pack to
   TestFlight App Review before external invitations. Build 5 is READY_FOR_BETA_SUBMISSION;
   the Beta Testers external group has no builds. No external review or invitations were sent.

Verified delivery evidence:
- `build/testflight-build5/processing-status-api-20261012.json`: build 5 VALID,
  internal IN_BETA_TESTING, assigned to Personal Testing.
- `build/asset-packs/upload-20261012.log`: complete pack upload succeeded, exit 0.
- `build/asset-packs/version1-status-20261012.json`: model pack version 1 import COMPLETE,
  state READY_FOR_TESTING, internalBetaReleaseState READY_FOR_TESTING, platform IOS.
- `build/asset-packs/delivery-20261012.json`: archive size/hash and Apple pack/version IDs.

The Transporter picker, Safari key-download failure, and iCloud access issue were resolved by
using Chrome on the owner's phone, retrieving the key through Finder, and uploading through
altool with a permission-restricted local credential copy outside the repository. No private
key contents or tokens were printed. App source and the accepted build 5 binary were unchanged.

# October 5 preparation and subsequent history

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
   remains unset pending a justified classification. See [SDK audit](../LiteRT-Privacy-Crypto-Audit.md).
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
[LiteRT privacy/crypto audit](../LiteRT-Privacy-Crypto-Audit.md), and incremented project build
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

**`main` is the release candidate.** It combines the complete Library reader and pending polish
(`39e1cd5`) with the RC hardening branch (merge `a807a0a`). Changes since build 2: locked-phone
saves are retried instead of dropped; conversation backups no longer churn after idle periods or
collide within one second; import asks for confirmation and always backs up what it replaces;
conversations saved without newer fields still decode; photo, camera, and file attachments are
removed until after launch; the app is iPhone-only; archives include a generated
`CLiteRTLM.framework.dSYM` (function names only; the vendor ships no debug info).

Full serial suite on `main`: 433 tests in 72 suites passed. Stable Xcode 27A266a archive and App
Store export succeeded: version 1.0 build 3, `UIDeviceFamily` [1], no model in the bundle, all 38
Library reader documents bundled, LiteRT dSYM UUID matches the shipped binary. Packaging audit of
the exported app: zero blockers.

- Archive: `../build-output/main-rc-release/Angrove-RC.xcarchive`
- IPA: `../build-output/main-rc-release/export/Angrove-iOS.ipa`, SHA-256
  `f4ea6db762548f694f65b7550aaa1949c3161c4e53025d2b1279cab852eca3dd`

The reader documents (`Shared/LibraryDocuments/`) and grounding corpus are generated,
gitignored inputs. A clean checkout must regenerate them before archiving
([Complete Library reader](../Complete-Library-Reader.md), [setup](../Development-Setup.md)).

Nothing was uploaded. Still required: upload the app and the essential model pack, verify
processing, then a fresh TestFlight install with model download on a supported iPhone.

## API delivery resumed — October 12

Chrome on the owner’s phone successfully downloaded the API key after Safari failed. Finder
retrieved it from iCloud Downloads and made a permission-restricted local copy outside the
repository so altool could read it. Private key contents and authentication tokens are not
printed or recorded in app artifacts. `--list-asset-packs` authenticated successfully and
returned no existing packs before this first upload.

Build readiness evidence: `build/testflight-build5/processing-status-api-20261012.json`.
Build 5 ID `a5093feb-9d20-4b74-904c-27e09129efe2` is VALID, internally IN_BETA_TESTING,
and assigned to Personal Testing. External testing is READY_FOR_BETA_SUBMISSION; Beta Testers
has no builds. No invitations or beta review submission were made.

Model upload is running through `altool --upload-asset-pack` to app 6819392752; log:
`build/asset-packs/upload-20261012.log`. Manifest upload succeeded. Archive upload and
subsequent Apple processing still need verification before claiming working TestFlight AI.

### Model upload completed

The complete archive upload succeeded (altool exit 0). Apple version 1:
`ffb0493b-9dab-4921-85d8-58a78302788e`; background asset ID
`a624687e-be06-4b10-8f3a-3b0bb3018cd9`. Initial status is PROCESSING, with no internal beta
version assigned yet. Delivery record: `build/asset-packs/delivery-20261012.json`; initial
processing evidence: `build/asset-packs/processing-20261012.json`.

### Model processing verified complete

Apple now reports version 1 importState COMPLETE, state READY_FOR_TESTING, and
internalBetaReleaseState READY_FOR_TESTING for IOS. Final evidence:
`build/asset-packs/version1-status-20261012.json`; the delivery and build source records
were updated. Internal TestFlight model delivery is complete. Actual owner-phone AI generation
remains unverified; external beta review and invitations were not submitted.
