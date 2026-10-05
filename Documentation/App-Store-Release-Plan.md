# Angrove App Store release plan

Decision recorded October 5, 2026. This is a release checklist, not a declaration that the app
is ready to submit. Mark a task complete only when its evidence is recorded below.

## Selected model delivery

- [x] Choose **Apple-hosted Managed Background Assets**, with the model pack marked **essential**.
- [ ] Implement, upload and validate that delivery in a real TestFlight installation.

Essential packs participate in app installation; the customer should not need to find or install
a separate add-on. Apple schedules the transfers, so simultaneous downloads are not a promise.
The app must still check availability and provide recovery for interrupted delivery before it
opens the native runtime. Our iOS 26.4 deployment target meets the iOS 26+ requirement for managed
asset packs. Asset-pack uploads and testing are separate from uploading the app binary.
See Apple's [hosting overview](https://developer.apple.com/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs/)
and [essential-pack policies](https://developer.apple.com/documentation/backgroundassets/creating-managed-asset-packs).

The initial pack is the current stock Gemma 4 E4B LiteRT Community model: 3,659,530,240 bytes,
SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
Keep the model version and runtime compatibility pinned together. No historical 12B or Qwen
research is being resumed. Generation and personal data remain on-device; downloading model
assets requires a network connection.

## Schedule and ownership

These are planning estimates, not a booked schedule or an Apple review-time guarantee. Day 1
means the next implementation session with signing/account access available. Allow roughly
**one to two weeks to reach a submission candidate**, including several days of beta use,
assuming no device-memory, recovery, licensing or account blockers. Apple processing and review
add separate waiting time. Steps 5 and 6 can proceed while delivery work is underway.

| Step | Owner | Estimated effort | When to check back / check off |
| --- | --- | --- | --- |
| 1. Confirm launch scope and account | Ryan, with Codex preparing the checklist | 30–60 minutes plus account waits | First session: decisions and access recorded |
| 2. Audit and freeze release source | Codex | Half a working day | Day 1: reproducible archive and audit report |
| 3. Implement essential model delivery | Codex; Ryan supplies account access | 1–3 working days | End of first day: local delivery states; days 2–4: real TestFlight installation |
| 4. Validate on physical devices | Codex prepares/runs accessible checks; Ryan handles hands-on phone checks | 1–2 working days, plus fixes | After TestFlight build: signed device checklist and logs |
| 5. Complete privacy and distribution records | Codex drafts/audits; Ryan confirms declarations and rights | Half to one working day plus unresolved rights | Before beta invitation / submission: declarations match the actual archive |
| 6. Prepare store materials | Codex drafts; Ryan supplies final demo and approves product choices | Half to one working day | Before candidate freeze: metadata, screenshots and review notes complete |
| 7. Use the beta and close regressions | Ryan/testers; Codex fixes and verifies | 3–7 calendar days suggested | Daily feedback; final check after fixes and repeat validation |
| 8. Submit the frozen candidate | Ryan/account holder; Codex prepares the package | 1–2 hours plus processing/review | Submit only after all blocking gates below pass |
| 9. Release and verify download | Ryan chooses release timing; Codex assists validation | 1–2 hours after approval | Approved release: real Store install, model availability and offline use verified |

## 1. Launch scope and account

- [ ] Ryan confirms active Developer Program membership, App Store Connect access and agreements.
- [ ] Record bundle/app record, signing team, version/build numbering and contact/support address.
- [ ] Ryan chooses launch countries, pricing, minimum supported phone and whether iPad ships at launch.
  The current project targets iPhone and iPad; shipping both requires validating both.
- [ ] Confirm Apple-hosted asset-pack controls are available for this app/account and the selected
  toolchain supports the workflow. Record any account-side prerequisite before coding around it.
- [ ] Ryan identifies the physical devices available for minimum-device and upgrade testing.

Check off with: a written scope decision and working account/signing access. Passwords or private
keys do not belong in this repository.

## 2. Release source and build audit

- [ ] Review and integrate the intended pending app changes, including encryption and widgets,
  without sweeping unrelated working-tree changes into a release commit.
- [ ] Produce a reproducible Release archive; record commit, Xcode/SDK, model hash, signing team,
  archive size, device support and enabled capabilities.
- [ ] Audit the signed app and every extension: provisioning, App Groups/Keychain access,
  frameworks, deployment targets and entitlements. Check whether debugging-only memory
  entitlements are present in Release and resolve their distribution eligibility.
- [ ] Confirm the large model is excluded from the production app bundle once asset delivery is
  integrated; inspect the actual archive rather than relying on Xcode group membership.
- [ ] Run focused regression checks and inspect startup, empty/unavailable states, settings,
  permissions, navigation, light/dark appearance and small-device layouts.

Check off with: archive/audit report and test results for the exact candidate. Existing simulator
passes do not replace physical-device evidence.

## 3. Apple-hosted essential model pack

- [ ] Add the managed Background Assets downloader extension and required capabilities using
  the installed Xcode templates and current Apple packaging tools.
- [ ] Create a versioned model pack and manifest with the essential policy for first installation
  and applicable updates; pin its content hash and compatible runtime version.
- [ ] Adapt the model store to verified asset-pack content. Resolve how LiteRT obtains a stable
  file path; do not assume a file descriptor is accepted by its existing API. Avoid reading the
  entire model into RAM or accidentally retaining a second full-size disk copy.
- [ ] Call the managed availability API before runtime initialization. Show accurate readiness,
  progress, retry and actionable storage/network errors; never substitute fabricated answers.
- [ ] Keep a loaded engine's model stable during updates. Validate new content, close the engine
  safely, then switch versions without destroying a working model or personal data.
- [ ] Test missing/interrupted assets, poor connectivity, insufficient storage, corruption,
  reinstall and upgrades with local asset-pack testing tools.
- [ ] Upload the pack and matching app build, select the correct pack version for TestFlight,
  and confirm a fresh installation obtains the real model through Apple hosting.
- [ ] Verify first usable generation and subsequent launch/generation in airplane mode. Record
  installation time and peak disk use on the supported device/network combination.

Apple's [download integration guide](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs)
provides `AssetPackManager`, `ensureLocalAvailability(of:)` and status updates. Essential policy
alone is not sufficient error recovery. Check off with: a recorded fresh TestFlight installation,
verified model hash, failure-state checks and successful offline generation.

## 4. Physical-device release gates

- [ ] Back up existing personal data before migration or recovery experiments.
- [ ] Verify plaintext-to-encrypted migration, existing saves, new saves and startup failure
  recovery on a phone; inspect stored data to confirm expected encrypted coverage.
- [ ] Exercise lock/unlock, relaunch, widget access and key availability. Validate backup/restore
  with its actual Keychain behavior and document recoverable versus unrecoverable scenarios.
- [ ] Verify export/import and deletion. User-requested JSON exports are readable files; privacy
  copy must distinguish them from encrypted app storage.
- [ ] Run sustained generation on the minimum supported device: multiple turns, long context,
  background/foreground, cancellation and memory pressure. Capture crashes, memory, heat,
  latency and battery observations using a defined protocol and acceptance criteria.
- [ ] Evaluate fresh representative questions and citation/source use after freezing the candidate.
  Keep development-reused eval sets separate from independent acceptance evidence.
- [ ] Verify supported iPad/device layouts, accessibility, permission denial and low-storage states.

Check off with: dated device/OS/build records, results and resolved blocking failures. Ryan's
hands-on lock and backup/restore checks cannot be inferred from simulator tests.

## 5. Privacy, encryption and rights

- [ ] Inventory app, widget and bundled SDK required-reason APIs and privacy manifests; add
  accurate `PrivacyInfo.xcprivacy` files with applicable approved reasons based on actual use.
- [ ] Audit the archive's network/data behavior and prepare matching App Privacy answers.
  Confirm any SDK telemetry before selecting a no-data-collected declaration.
- [ ] Align app/site privacy policy with encrypted local storage, readable exports, Keychain
  recovery, model downloads and any actual collection. Link the policy inside the app.
- [ ] Audit all linked crypto, answer export-compliance questions and set the applicable plist
  declaration only after that audit. Ryan confirms account-side declarations/documentation.
- [ ] Verify model redistribution terms, attribution/notices and corpus distribution rights for
  the chosen territories; resolve uncertain sources before shipping them.
- [ ] Keep public encryption wording consistent with the verified release build and documented
  exceptions. Development-source implementation alone does not establish shipped coverage.

Reference: [App Privacy](https://developer.apple.com/app-store/user-privacy-and-data-use/),
[encryption declarations](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/).
Check off with: archived manifest/privacy report, final policy, declarations and rights record.

## 6. Store materials and reviewer instructions

- [ ] Prepare description, subtitle, keywords, support/privacy URLs, category and age-rating answers.
- [ ] Capture real screenshots from the final candidate for the supported device families.
- [ ] Explain AI limitations and source checking accurately, without unsupported quality claims.
- [ ] Draft reviewer notes: install/model delivery expectations, how to ask a question, inspect a
  source, save an Insight and use Study; include model/build versions and offline behavior.
- [ ] Ryan records the portfolio walkthrough using [Demo-Outline.md](Demo-Outline.md). This is
  useful for hiring and optional store preview work, not itself a mandatory submission gate.
- [ ] Ryan confirms final pricing, countries, contact details and release timing.

Check off with: reviewed store copy, valid links, actual screenshots and usable reviewer steps.

## 7–9. Beta, submission and release

- [ ] Invite testers after required TestFlight processing/review; collect install failures,
  citation errors, crashes and confusing flows over several days. The suggested beta duration
  above is our planning choice, not an Apple requirement.
- [ ] Resolve blockers, freeze the candidate and rerun checks affected by fixes. Record the exact
  app build and asset-pack versions; do not change assets silently after final validation.
- [ ] Prepare the submission with the correct app and asset pack, compliance answers, metadata
  and reviewer contact. Ryan authorizes the actual submission and release when ready.
- [ ] Respond to review issues against the same documented candidate; validate any replacement.
- [ ] After approval, verify a real Store install, source-linked response, save/relaunch and offline
  operation. Update website/repo release claims to match what customers can download.

## Completion record

| Gate | Date | App commit / build | Asset pack version | Evidence link | Checked by |
| --- | --- | --- | --- | --- | --- |
| Release audit | Pending | — | — | — | — |
| Fresh TestFlight delivery | Pending | — | — | — | — |
| Phone encryption / restore | Pending | — | — | — | — |
| Sustained device / quality checks | Pending | — | — | — | — |
| Privacy / compliance / rights | Pending | — | — | — | — |
| Final beta candidate | Pending | — | — | — | — |
| Submission / approval | Pending | — | — | — | — |
| Store installation | Pending | — | — | — | — |

Codex can implement delivery, recovery UI, manifests, release configuration fixes and regression
checks, and prepare store/reviewer/policy drafts. Account-holder agreements and declarations,
product scope decisions, owner-only phone interactions and the demo recording need Ryan.
Access-dependent uploads can be assisted once access is available. No hosting account or
self-hosting budget is planned for the selected Apple-hosted route.
