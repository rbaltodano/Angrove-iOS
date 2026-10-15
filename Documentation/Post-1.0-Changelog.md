# Post-1.0 changelog

Everything added after the 1.0 build submitted to App Review on 2026-10-15. Add one entry per
change, newest first, under the date. Tag each entry by platform:

- **[iOS]** or **[Shared]**: touches the iPhone app. Write it so it can become patch notes: what
  changed for the person, why, and any model, storage, privacy, or performance effect.
- **[macOS]**: Mac-only. Keep it brief.
- **[Tooling]**: diagnostics, evaluation, conversion; ships in neither app.

1.0 baseline: repository `main` at `8ff5713` plus the working tree used for the submitted
archive. (Owner: record the 1.0 build number here.)

## Mobile patch notes (draft)

Collected from the [iOS] and [Shared] entries below.

- Updated the on-device AI runtime (Google LiteRT-LM 0.14 → 0.17.1). Answers, model and
  privacy are unchanged; this prepares for larger models on Mac. The app download grows by
  about 17 MB. *(Pending iPhone device validation before release.)*

## 2026-10-15

- **[macOS] Model tiers: Standard (E4B) and Large (Gemma 4 12B).** Settings › Model picks the
  tier, gated by installed memory (Large: 24 GiB placeholder). The choice applies at the next
  launch and falls back to Standard when the chosen tier isn't installed. Each tier has its own
  checksum, and inactive tiers' GPU caches are removed at launch. Large is unevaluated and opt-in;
  the default stays Standard. Details are in `Mac-Port.md` › Model tiers. Verified: 115 Mac tests
  pass. The opt-in live test ran 12B through the production model path: 15.6 s cold load,
  1.7 s warm, about 18 s per answer, and the John chapter count correct. One early cold-load run
  stalled with idle native threads and did not reproduce; watch for it.
- **[Shared] `LiteRTAngroveRuntime` takes its context size as an init parameter** (default
  4,096). No iPhone behavior change.

- **[Shared] Mac parity batch: shared Home, Library, Settings and Study Topics code.** Work
  from parallel agents, committed together. iPhone Home dashboard, Library, User Guide,
  Licenses and Settings components moved from `iOS/` into `Shared/` (for example
  `HomeDashboardSections`, `LibraryReaderComponents`, `BundledLicenses`, `UserGuideTopic`,
  `BugReportSubmission`, `SharedFormControls`). Mac Settings, page headings, shortcuts,
  Model Controls hover labels, image attachments and Study Topics were added. The details are
  in `Mac-Port.md` (October 14–15 sections). **Owner:** confirm whether any of this was already
  in the 1.0 archive. The iPhone parts are intended as moves; check them for visible changes
  before writing patch notes.

- **[Shared] LiteRT-LM runtime upgraded 0.14.0 → 0.17.1** (`Vendor/LiteRTLM`). Required for the
  Mac Large tier (Gemma 4 12B cannot load on 0.14).
  - **What changed:** the Swift wrapper is upstream 0.17.1. The binaries are the upstream
    v0.17.0 archives that 0.17.1 references: the iOS checksum matched, and the Mac binary is
    pinned by checksum. The Apple Foundation Models adapter target was dropped (unused).
  - **Patches carried forward**, same behavior as 1.0: F32 `activationDataType`;
    `NativeActivityMonitor`; engine and conversation creation off the cooperative thread pool;
    detached native deletes, with the conversation keeping its engine alive; native-stream
    begin/end tracking; Bazel `BUILD` naming. The full diff against upstream 0.17.1 is
    `Vendor/LiteRTLM/angrove-patches.diff`. Re-apply it for any future LiteRT-LM upgrade.
  - **iPhone effect:** no app source changes. Same model, prompts, F32 precision, 4,096 context
    and greedy decoding. The device framework grows from 43.2 to 60.5 MB. The privacy manifest
    is unchanged, and the re-audit found no new required-reason or network surface (see
    `LiteRT-Privacy-Crypto-Audit.md`). The framework now also embeds Google's `LICENSE` and
    `third_party_licenses.bundle`.
  - **Verified:** Mac and iOS-simulator builds pass. The Mac runtime/queue tests pass (23), as do
    the iOS `LiteRTProductionRuntimeTests`, `LiteRTProbeHarnessTests` and
    `ModelRuntimeLifecycleTests` (90). Mac smoke runs with the vendored package: E4B and 12B
    both answered "21 chapters" for John.
  - **Not yet verified:** physical iPhone (latency, memory, vision, lifecycle stress, F16
    regression set: John 14, Psalm 23, John 11), the full test suites, and an eval run.
    Required before this ships in an iOS update.

- **[Tooling] Gemma 4 12B Mac smoke test: `MAC-12B-GPU-1`.** Stock
  `litert-community/gemma-4-12B-it-litert-lm` package `gemma-4-12B-it.litertlm`
  (6,883,278,368 bytes, SHA-256 verified `58fd31b7…a8b6`), stored in
  `Aquinas_Backend/models/LiteRT-Stock/`, outside the app bundle. Host: M4 Pro, 24 GiB.
  Raw diagnostic only (`Tools/MacRuntimeSmoke.swift` plus memory reporting): GPU, 4,096 context,
  F32 activations, greedy, one question. Evidence: `output/mac-runtime/MAC-12B-GPU-1/`.
  - LiteRT-LM 0.14.0 (the app's version) **cannot load it**: `No KV cache inputs found`.
  - LiteRT-LM 0.17.1 loads and answers. The answer to "What is prudence?" was fuller than
    E4B's. Generation took 3.1–4.7 s, versus 1.3 s for E4B. Load took 19–21 s on a cold cache and
    2.0 s with the compiled cache, which uses **5.6 GB of disk**.
  - E4B on 0.17.1 gave the same answer as on 0.14 (6.1 s load, 1.3 s generation).
  - Memory is not settled. The process footprint peaked at 2.6 GB, and the system-wide sampled
    increase was 3.9 GB, while other agents were running. Neither number captures memory-mapped
    weights reliably, and the model card reports about 7.9 GB of GPU memory. A 16 GB Mac
    measurement is still needed.
  - 0.17.1 drops the app's local LiteRT-LM patch: the F32 `activationDataType` flag, the
    native-activity tracking in `Engine.swift`, and the teardown handling in `Conversation.swift`.
    A runtime upgrade must carry these patches forward and re-validate iPhone behavior.
  - No app code or app model selection changed.
