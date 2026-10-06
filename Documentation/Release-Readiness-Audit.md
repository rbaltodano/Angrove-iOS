# Local release-readiness audit

October 5, 2026. Audits the **local working tree**, not a frozen/pushed release candidate. Existing
uncommitted encryption, widget and other app work was preserved. This report is not an App Store
approval. Distribution-signing evidence and the later [pre-TestFlight check](Preflight-Check.md)
are recorded separately below.

## Stable-Xcode validation passed

The stable Xcode 27.0 build **27A266a** archive and App Store export succeeded from committed
main **21ac6a6**. Apple validation then passed (`Validated Angrove-iOS`, `EXPORT SUCCEEDED`,
exit 0), resolving the earlier beta-toolchain rejection for this run. Local distribution
signatures/profiles/manifests passed; encryption declaration and TestFlight upload/processing
remain separate gates. Current paths/hash are in [the handoff](TestFlight-Handoff.md).

## Earlier Apple validation follow-up

App record **6819392752** now exists and authenticated lookup matches the bundle ID. The next
validation attempt failed with **Unsupported SDK or Xcode version** for Xcode 27.0 beta
(`27A5194q`). Rebuild using an Apple-supported release/RC before retrying. Only Xcode-beta is
installed, and disk space is about 2 GiB. Local signatures do not establish Apple acceptance.
See [updated handoff](TestFlight-Handoff.md).

## Latest distribution follow-up

A signed Release archive and **App Store distribution export** now succeeded. The exported app,
widget and downloader passed strict signature checks and have unexpired App Store profiles with
the shared App Group and debugging disabled. All four bundles, including LiteRT, contain privacy
manifests. The SDK manifest declares the reviewed file-metadata and elapsed-time uses; it is an
Angrove integration declaration, not a Google attestation of every native component.

The essential model is packaged as `build/asset-packs/Gemma4-E4B.aar` (3,129,706,564 bytes).
The IPA is `build/release-audit/app-store-export/Angrove-iOS.ipa` (223,017,617 bytes), version
1.0/build 1. See [delivery artifacts and gates](Apple-Hosted-Model-Delivery.md). Nothing has been
uploaded, installed on the owner's phone or validated through TestFlight in this follow-up.

`build/release-audit/distribution-packaging-report.json` verifies each app/extension signature,
provisioning expiry, App Group and debugging status. It still flags the unset encryption-export
answer. App Store record/build-number checks, launch territories and account-side declarations
remain pending. Command-line validation authenticated but found zero matching app records. The initial unsigned findings below are dated baseline evidence.

## Initial local implementation

- Added the managed Apple-hosted downloader target and essential E4B pack manifest.
- Verified the actual pinned model size and SHA-256 with bounded reads, and validated its manifest
  using the installed `ba-package` tool. No weights were downloaded and no model experiment ran.
- Built the simulator app and an **unsigned Release device archive** with Xcode 27.0
  (`27A5194q`, installed under Xcode-beta). Confirm the toolchain is accepted for App Store
  uploads before preparing the signed submission candidate.
- Inspected the actual Release app: no `.litertlm` file is bundled. The widget is in `PlugIns`
  and the downloader is in `Extensions`, with its managed extension point configured.
- Added and verified bundled privacy manifests for the app, widget and downloader.
- Added a separate Release entitlement file without `increased-debugging-memory-limit`; Debug
  retains its existing file. Distribution provisioning for the other memory entitlements and
  App Groups still requires verification against a signed archive.
- Passed 76 selected simulator cases across delivery, runtime lifecycle and production-runtime
  regression suites, including all five new small-fixture model-delivery checks. This did not
  run a new model-quality experiment or test the hosted service.
- Prepared [store copy and reviewer notes](App-Store-Submission-Draft.md).

The initial unsigned app contained about **316 MB** of uncompressed file content, compared with
its separate 3.66 GB model asset. This is a local file-byte sum, not Apple's processed download
size or the total installation/storage requirement.

## Delivery UI and SDK follow-up

The On-device Model page is linked from Settings, and the Model Tasks popup observes the same
process-scoped delivery state. It shows actual Apple progress, an indeterminate integrity check,
and connection/storage/integrity recovery guidance. Retry coalesces preparation rather than
creating another inference engine. Late observer updates are ignored after preparation completes.
The empty queue only calls the model idle after model readiness is established.

Passed 23 cases across presentation/recovery, asset-integrity and runtime-lifecycle suites after this change.
A fresh unsigned Release device archive also succeeded, and the packaging audit was repeated.
Six DEBUG fixture states were visually checked in both light and dark mode on an isolated iPhone
17e simulator (12 captures). The fixture never starts native inference or downloads a model.
Screenshot proof: `build/release-readiness/ui-proof/verification.md`. UI taps, regular Settings
navigation, Dynamic Type and genuine hosted-service failures still need verification; the
available UI tooling could not perform touch/hierarchy checks. Unit checks verify retry recovery
and repeated retry coalescing, not the full touch path.

The [native SDK audit](LiteRT-Privacy-Crypto-Audit.md) now pins the binary, traces native
file/timing/network/RNG callers and supplies a repeatable inventory script. It found bundled
ChaCha random-generator code and confirmed the device minizip entry rejects passwords. The SDK
API-reason manifest has since been added and verified in the distribution IPA; export classification
and runtime network observation remain gates.

## App-owned privacy API review

| Bundle | Category / reason | Actual app use |
| --- | --- | --- |
| App | UserDefaults: `CA92.1` | Private settings and migration of legacy personal preferences |
| App and widget | UserDefaults: `1C8F.1` | The app-owned shared widget record in the same App Group |
| App | FileTimestamp: `C617.1` | In-container backup rotation/migration and model metadata checks |
| App | SystemBootTime: `35F9.1` | Local DEBUG lifecycle/probe timing; no automatic upload |
| Downloader | No app-authored required-reason API declared | Apple's default managed downloader implementation |

Manifests describe reviewed app-owned behavior. Their empty collected-data arrays do not certify
unknown behavior inside a native SDK or replace App Store Connect's privacy questionnaire.
Reasons were checked against Apple's [API/reason documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Blocking findings

1. **Export-compliance declaration is pending.** App-owned storage encryption uses CryptoKit/
   Keychain. The native audit found bundled ChaCha PRNG code, distinct from message encryption.
   Its submission classification/account-side answer remains open; `ITSAppUsesNonExemptEncryption`
   was not guessed. See the [SDK evidence](LiteRT-Privacy-Crypto-Audit.md).
2. **Upload/account validation is pending.** The Apple app lookup returned zero matching records for
   `com.ryanbaltodano.Aquinas-iOS`. Create/reconcile that record and check its build number,
   launch territories and agreements. Distribution export succeeded, but acceptance
   of this Xcode toolchain by upload processing is not yet proven.
3. **Hosted delivery is not service-tested.** The app/pack are locally prepared. Actual UI taps,
   fresh TestFlight installation, interruption/storage/cancellation and update testing remain.
4. **Physical release checks and rights are pending.** Lock/Keychain/backup restore, sustained
   memory/thermal behavior without the debugging entitlement, native networking observation,
   independent quality acceptance, minimum devices, and model/corpus rights remain release gates.

The initially absent SDK manifest and unsigned archive findings were addressed in the local
follow-up; the current blockers above refer to the actual distribution export. No upstream privacy
attestation or blanket encryption exemption was invented.

Apple's [debugging-memory documentation](https://developer.apple.com/help/glossary/increased-debugging-memory-limit/)
requires removing that entitlement before rebuilding a distribution release candidate.

## Repeat the packaging audit

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/release-audit \
  -archivePath build/release-audit/Angrove.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
python3 scripts/audit_release_bundle.py build/release-audit/Angrove.xcarchive \
  --output build/release-audit/packaging-report.json
```

This local command intentionally makes an unsigned archive. Use the final signed archive for
provisioning/entitlement checks. The report preserves blockers rather than presenting successful
compilation as a compliance pass. Signing verification and service/device checks remain separate.

Build log: `/tmp/angrove-release-archive.log`. Simulator/test log:
`/tmp/angrove-readiness-tests.log`. These paths are local diagnostics, not public evidence or
portable replication artifacts. The generated archive and JSON report live under gitignored
`build/release-audit/`.

Latest follow-up test log: `/tmp/angrove-delivery-ui-tests.log`. The Release archive still emits
existing grounding actor-isolation warnings and an ExtensionKit copy-path warning; its inspected
downloader is present in the correct app `Extensions` directory. Compilation success does not
close the signing or SDK evidence gates above.
