# October 17 codebase improvement checkpoint

This records the implementation following the whole-repository audit. The owner approved the
remaining improvements, requested an explanation of finding 15, and requested a zoom fade for
finding 21. This is an implementation checkpoint, not a claim that every audit opportunity has
been exhausted or that runtime speedups have been measured. Existing unrelated Mac redesign
changes remain outside the audit commit in the checkout.

## Finding 15: why inline images make saves expensive

Uploaded image bytes currently live inside Codable conversation/topic/Board values. JSON encodes
those bytes as base64, increasing their size by roughly one third before envelope overhead.
Changing a small piece of conversation text can therefore encode, encrypt and replace a snapshot
that includes every attached image again. Backups repeat those bytes too. Larger histories make
this disproportionately expensive in CPU, transient memory, disk writes and retained backups.

The owner subsequently approved this migration. It is now implemented: immutable originals are
stored as encrypted blobs within each owner's directory; local snapshots carry versioned content
references. Startup migration verifies blobs before replacing parent JSON and retains encrypted
originals. Backups, Topics, nested Board windows and trash are included in reference tracking;
portable exports still carry exact image bytes. Conservative cleanup preserves all retained
references and cancels on any unreadable inventory. See
[Attachment storage migration](../Attachment-Storage-Migration.md) for the complete contract and
release-validation limits. Conversion has only been exercised on isolated fixtures; the owner's
Mac installation remains pending by request.

## Implemented

| Area | Change | Evidence / qualification |
| --- | --- | --- |
| Deferred personal writes | A newer save supersedes an older extracted retry by revision; transient failures retry with bounded backoff. | Fault-injection tests cover failed A, successful B, then retry. This is an in-process retry, not a durable journal. |
| Encrypted preferences | Topics, listening position, glosses, flagged quotes and daily question values use the ordered serialization worker and immediate cache. | Existing preference keys and encrypted encoding preserved; rapid-edit and round-trip tests pass. Initial cache misses can still synchronously read. |
| Shared decoding | Conversation/branch compatibility decoding now compiles into both targets; old topics without a creation date have a stable fallback. | Minimal legacy fixtures and populated round trips pass on both apps. |
| Shared storage recovery | Both apps validate/migrate protected personal stores before opening features. Mac includes Boards; preview/test hosts stay isolated. | Shared startup logic compiles on both targets; recovery/encryption tests pass on iOS. |
| Fresh-start recovery | Diagnostic ciphertext is archived along with unreadable personal data. | Regression verifies bytes survive and subsequent preparation succeeds. No owner data or keys were reset. |
| Mac normal Quit | Publish final Board state, cancel tasks and stop speech, drain the two protected write queues, then reply to AppKit. | Compiles in both Debug and Release; real unsaved-work lifecycle still deserves device/manual coverage. |
| Native cancellation / stalls | Cancellation and watchdog expiry release the Swift waiter. Actual outstanding native initialization/conversation/stream/deletion work still blocks competing native operations. Late cancelled creation cannot publish runtime state. | Fake blocked-native tests exercise cancellation, timeout, late completion and pre-cancelled admission. No live model probes were run. |
| Model loading | All native initialization paths use the load watchdog; bounded teardown waits fail rather than admitting a competing native request. | Both targets compile; live recovery/thermal/memory behavior needs supported hardware. |
| Failed answers | Shared explicit response outcome survives adapters and is persisted optionally. Failures do not publish successful answer completion or run response seeding/title analysis. | Queue failure/next-job and unavailable-model adapter tests pass. Historical missing outcome remains compatible. |
| Response analysis | Cancelled/deleted conversation checks precede seed persistence. Mac evidence eligibility and duplicate-subject checks are aligned with shared policy. | Conversation/queue/tree regression suites pass; extraction quality was not rebenchmarked. |
| Mac context growth | Compact older context before answering when the shared budget requires it; preserve the latest turn and checkpoint only for the current live request. | Mac conversation tests pass. Live long-conversation token/memory tests remain. |
| Speech ownership | One in-flight speech-engine load; run identity/cancellation checks bracket asynchronous preparation and synthesis; preparation publishes its arrays together. | Both targets compile; replacement/stop-during-preparation deserves an injected speech-engine regression and physical audio checks. |
| Graph growth | Retain each unattached node's best parent frontier and precompute root centrality; live growth runs on the graph worker with revision checks. | Original exhaustive parent-selection oracle agrees for sizes 2/8/24/80 across ties, vectors, fixed-parent cycles and affinities. Algorithmic reduction is not a measured latency claim. |
| Graph preparation | Build a seed-ID lookup once instead of repeated linear scans during merging/budding. | Existing growth/canvas/lifecycle regressions pass. |
| Board dragging | Build sibling snap frames in one pass instead of nesting linear item searches. | Board geometry/history suite passes. |
| Dot field (21) | Smoothly fade from full opacity at 60% zoom to zero at 40%, remove renderer below the cutoff, pause inactive/Reduce Motion/idle timelines as appropriate. | Fade boundaries/monotonicity tests pass on both targets; six 375×667 light/dark snapshots per platform rendered and inspected. |
| Conversation list | Use a lazy stack for iPhone conversation cards. | Both apps build. Derived filtering/search work is still a separate opportunity. |
| Response rendering | Memoize parsed streaming-response blocks and clear revealed-source keys when their response is cleared. | Streaming/pipeline tests pass. Word wrapping/layout traversal is not fully cached. |
| Attachment storage (15) | Owner-scoped encrypted blobs, resumable startup migration with preserved originals, portable inline exports, backup-aware cleanup and reference validation. | Comprehensive temporary-file/injected-key suites run on both targets; see the migration document for results and physical-validation limits. |
| Attachment reads | Background detached import retains security-scoped access throughout each read; bounded autorelease pools; cancellation suppresses obsolete work. | Both apps compile. Provider/iCloud error UX and export work remain separate. |
| Vision preparation | Normalize live request image inputs on a serial background worker, cache by immutable attachment identity with a 64 MiB cost limit. | Both apps compile. Cache eviction/direct helper calls can still use synchronous fallback normalization. |
| Experimental model flag | Bonsai activation is Debug-only. | Release still links the legacy framework; removing its binary/link/build footprint is separate. No shelved model work resumed. |
| Model packaging | Reusing an asset-pack ID verifies staged size/digest rather than silently packaging stale bytes. | Portable tiny-file staging regression passes. |
| Model promotion | Verified staged replacement atomically replaces an existing file rather than deleting it first. | New-file, replacement, and failed-promotion preservation fixtures pass on both targets. No model downloads. |
| Instrumentation / CI | Add a model-task execution signpost and explicit core-package testing; Mac CI uses the unsigned configuration verified locally. | Core tests pass; CI workflow was inspected but hosted CI was not dispatched. |

## Remaining work and measurement gates

- Physical-device interrupted attachment upgrade, low-space, lock/unlock and complete owner-directory/Keychain backup restoration. The coded migration and portable import/export contract are implemented.
- Supported base-iPhone sustained generation, thermal, memory, cancellation, background/foreground,
  native-stall recovery and image-heavy history profiling. No simulator result establishes these.
- Byte budgets for other process caches and library materialization, plus before/after allocations.
- Search/filter memoization, word/flow-layout measurement caching, additional canvas culling, and
  large-fixture graph/layout benchmarks. Prioritize with Instruments traces rather than guessed thresholds.
- Further decomposition of shell/conversation/tree owners, and expanding the extracted core package.
  Shared recovery/decoding are the completed first pieces, not a repository-wide architecture rewrite.
- A visible persistent write-failure/retry state and a durable retry journal if required. Backoff
  cannot guarantee persistence through process termination while a disk/key remains unavailable.
- Speech replacement regression with controlled suspended dependencies; physical playback verification.
- Release-only packaging/skip-report CI and eliminating unused experiment frameworks from Release.
- Remaining Swift concurrency/isolation warnings, including vendor boundaries, before a Swift 6 switch.

## Verification

- iPhone 17 / iOS 27.0, arm64 simulator: 113 selected tests in 16 suites passed. Final recovery,
  native ownership, file-promotion and appearance pass: 18 tests in 4 suites passed.
- Mac arm64: initial combined run had 64/65 pass; the keyboard-driven Board test timed out.
  The entire 20-test Board suite subsequently passed without concurrent simulator tests.
  Final native ownership/promotion/appearance run: 5 tests in 4 suites passed. The updated canvas
  background fixture was rendered again successfully.
- AngroveCore: 12 tests in 5 suites passed.
- Packaging/evidence Python fixtures: 10 tests passed. Library tooling: 6 tests passed after
  installing declared dependencies into a temporary virtual environment.
- Documentation checker: 120 local links in 44 documents passed, including this ledger.
- Both app test commands compile their complete app/test targets. No live native inference, model
  download, shelved-research probe, production data reset, or phone installation was performed.
- `git diff --check` passed. Build/test output is under `/tmp/angrove-audit-*.log`;
  xcresult paths are printed at the end of each app test log.

## Signed normal Mac installation

**Pending at the owner's explicit request.** `Tools/install-local-mac.sh` stopped before
building/replacing the installed app because both the legacy Application Support data and a
sandbox container exist. The installer protects against opening with an apparently empty
conversation store in this state. Neither original location was moved or deleted.

The separate signed Release build succeeded at
`build/mac-local/Build/Products/Release/Angrove-macOS.app`; `codesign --verify --deep --strict`
passed. Sandbox and App Group entitlements are present. It was not launched against personal
stores and did not replace `/Applications/Angrove.app`.

156 legacy personal files (excluding models) were backed up and hash-verified, with the legacy
preferences copied, under `build/mac-data-backups/20261017-145142-audit-preinstall/`.
The attempted sandbox-container backup was incomplete: macOS privacy protection denied access
to its Data directory and container metadata, so its contents cannot be judged empty or safely
replaced. `BACKUP-STATUS.txt` explicitly records that limitation. Preserve the partial backup;
it is not a sandbox-container backup. The owner selected **Leave installation pending**.
Resolve the data-location conflict before the next normal installation. Do not bypass the
safeguard or launch the DerivedData copy against personal stores.

## Approved attachment-migration follow-up

The owner subsequently approved finding 15's migration. It is implemented and documented in
[Attachment storage migration](../Attachment-Storage-Migration.md): encrypted owner-scoped blobs,
versioned local references, verified blob writes before parent replacement, retained encrypted
originals, portable inline exports, safe backup/Topic/Board/trash reference tracking and cleanup.
Final focused tests: **48 iPhone tests and 33 Mac tests passed**, including injected interrupted
and failed migration, image corruption/missing-key cases, legacy preferences, portability, exact
original-byte preservation and avoiding image crypto on repeated schema validation. No owner
content was migrated by development tools. Physical upgrade/backup restoration checks remain.
Normal Mac installation is still pending at the owner's request.

## Normal Mac installation completed — October 17, 2026

The owner confirmed all existing data is test data and explicitly authorized installation without
migration or launch. The obsolete pre-sandbox Application Support folder was moved intact to
`build/mac-data-backups/20261017-152126-retired-test-data/Legacy Application Support`, with its
legacy preferences copied alongside it. The protected sandbox container was not touched.
`ANGROVE_MAC_LAUNCH_AFTER_INSTALL=0 bash Tools/install-local-mac.sh` succeeded and installed the
current signed Release at `/Applications/Angrove.app`. The old app remains recoverable under
`build/mac-installed-backups/`. Installed signature verification passed, its executable matches
the freshly built executable, and no Angrove app process is running. No app data migration ran.
This resolves the earlier installation-pending status. Output is recorded in
`/tmp/angrove-final-install-no-launch.log`.
