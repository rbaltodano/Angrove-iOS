# TestFlight handoff — October 5, 2026

The local code and artifacts are prepared for the next upload step. This is not a submitted or
processed beta. Personal device data has not been touched.

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
| App Store IPA | `build/release-audit/app-store-export/Angrove-iOS.ipa` | 223,017,617 |
| Essential model pack | `build/asset-packs/Gemma4-E4B.aar` | 3,129,706,564 |
| Distribution audit | `build/release-audit/distribution-packaging-report.json` | JSON report |
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
