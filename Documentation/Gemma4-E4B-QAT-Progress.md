# Gemma 4 E4B QAT migration — progress ledger

> This is the **mutable** record for [`Gemma4-E4B-QAT-Plan.md`](Gemma4-E4B-QAT-Plan.md) (plan v2).
> Update it at the start and end of every checkpoint and commit each update on
> `feature/gemma4-e4b-qat`. Never delete earlier entries; if evidence is superseded, strike it
> through (`~~old~~`) and add the new value with a date and run ID.
>
> Status values: `todo` · `in-progress` · `done` · `failed` · `blocked` · `skipped` (with reason)
> Selection and invalidation rules: plan §0.

## Status board

| ID | Checkpoint | Depends on | Status | Owner / session | Last updated | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| C0 | Baseline identity and workspace | — | done | Claude Code (Opus 5.5) session | 2026-09-25 | Run C0-B0-1; B0 hash matches |
| C1 | Acquire and verify candidates | C0 | done | Claude Code (Opus 5.5) session | 2026-09-25 | M4-L hash matches (C1-M4L-2); M2-L and M4-Ls not downloaded |
| C2 | Provenance classification | C1 | done | Claude Code (Opus 5.5) session | 2026-09-25 | **unconfirmed**; package is a GPU-only "artisan" text decoder (C2-M4L-1) |
| C3 | Harness hardening (code) | C0 | blocked | Claude Code (Opus 5.5) session | 2026-09-25 | All C3 work done (`fa88428`). Gate not literally met: 175/176 tests pass; the 1 failure is pre-existing on base `31aa476`. See *Open questions* |
| C4 | Simulator compatibility (informational) | C1, C3 | todo | | | |
| C5 | Early phone memory/compat screen | C4 | todo | | | Freezes `operating_cap` |
| C6 | Integration diagnostics | C5 | todo | | | |
| C7 | Full-app functional + lifecycle stress | C6 | todo | | | |
| C8 | Quality A/B (40 dev + 40 held-out) | C7 | todo | | | Needs owner review time |
| C9 | Physical-device sustained gate | C8 | todo | | | |
| C10 | Promotion | C9 + owner approval | todo | | | |
| C11 | Optional: M2-L control analysis | C8 | todo | | | |
| C12 | Optional: vision probe | C10 | todo | | | |

**Next action:** Owner resolves the C3 gate question in *Open questions* (recommended: accept the pre-existing test failure as baseline and mark C3 `done`). Then run C4, which is fully prepared.

## Candidate registry

Add a row for every distinct artifact and configuration. A changed hash, runtime, or config means
a new row (plan §0, rule 5).

| ID | Artifact | HF repo @ revision | Bytes | Published SHA-256 | Computed SHA-256 | Runtime / config | Provenance | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B0 | `gemma-4-E2B-it.litertlm` (wi8 E2B fine-tune, bundled) | local export | 3,862,121,696 | `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282` (manifest) | `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282` (match, C0-B0-1) | LiteRT-LM 0.14.0, GPU, 4,096, deterministic | fine-tuned PTQ | baseline |
| M4-L | `gemma-4-E4B-it-gpu.litertlm` | `litert-community/gemma-4-E4B-it-litert-lm` @ `2eee7ac325f20eb8c9ac1d0e972f7c84663062da` | 2,969,059,328 | `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff` || `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff` (match, C1-M4L-2) | LiteRT-LM 0.14.0, GPU, 4,096, deterministic | unconfirmed (C2) | candidate |
| M4-Ls | `gemma-4-E4B-it.litertlm` | same @ same | 3,659,530,240 | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` | | only if M4-L can't load | unconfirmed | fallback |
| M2-L | `gemma-4-E2B-it.litertlm` (stock) | `litert-community/gemma-4-E2B-it-litert-lm` @ `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1` | 2,588,147,712 | `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c` | | control arm (D9) | confirmed QAT (E2B discussion #30) | optional |

## Frozen values

Record these **before** the candidate numbers they govern are seen.

| Name | Value | Frozen on / run ID | Notes |
| --- | --- | --- | --- |
| `operating_cap` (C5) | | | `os_proc_available_memory()` at launch, base iPhone 17 |
| Eval set dev SHA-256 (C8) | | | |
| Eval set held-out SHA-256 (C8) | | | |
| C8 config hash | | | |
| C9 timing protocol | | | Link the frozen protocol file |

## Open questions for the user

_Add a dated entry for anything that blocks progress. Say what the question is, why it blocks,
and what options you recommend._

- **2026-09-25: C3 gate: pre-existing test failure. BLOCKS C3 → C4.** The C3 gate requires
  "the build and all tests pass". 175/176 pass. The failure,
  `MiniLMGroundingRetrievalTests.namedPassagesUseSourceTextAnchors` (resurrection case), fails
  identically on untouched base `31aa476` (`C3-basecheck-1`) and is unrelated to C3's code. The
  plan has no On-failure branch for C3.
  - **Recommended:** accept this as a known baseline failure for the C3 gate. Record that here and
    set C3 to `done`; C4 can then run immediately.
  - **Alternative:** fix the grounding test or corpus mismatch first in a separate change on
    `main`, then rerun the suite.
  - Either way, C8's grounding is identical for B0 and M4-L, so it doesn't bias the A/B.
- **2026-09-25: C5 harness prerequisites. Not blocking yet.** C5 asks for "~2,000-token prefill
  with a 256-token decode" and a 4K equivalent.
  - The raw probe accepts any prefill text through `--litert-probe-raw-question`.
  - It has **no decode cap**: LiteRT-LM v0.14.0's Swift API has no max-output setting, and
    breaking out of a stream without `Conversation.cancel()` leaves native decoding running
    (see `LiteRTAquinasRuntime`'s notes on the cancel wedge).
  - Before C5, decide whether "256-token decode" means (a) a prompt that asks for about 256
    tokens, measured with `--litert-probe-benchmark`, or (b) a new capped-decode option, which
    would be harness code and would need its own check.
- **2026-09-25: E4B GPU package provenance (C2). Needs owner approval to post; not blocking.**
  Nothing definitive exists, so M4-L stays **unconfirmed** (D8). Recommended: approve posting
  this on the E4B discussion board (`litert-community/gemma-4-E4B-it-litert-lm`), or decline and
  keep the unconfirmed label. Draft:
  > Hi, could a maintainer say how `gemma-4-E4B-it-gpu.litertlm` (added in #19, SHA-256
  > `4912bb5a…2bb7ff`) was produced? (1) Are its weights derived from the Gemma 4 QAT mobile
  > checkpoint (`google/gemma-4-E4B-it-qat-mobile-transformers`), or post-training quantized from
  > `google/gemma-4-E4B-it`? (2) Its decoder is a `tf_lite_artisan_text_decoder` with
  > `backend_constraint: gpu_artisan`. Is it supported by the LiteRT-LM iOS Metal backend
  > (v0.14.0)? (3) What activation precision does the artisan path use, and what is the
  > package's maximum context (we run 4,096 tokens)? The model card covers the 3.66 GB and web
  > packages but not this one. Thanks!
- ~~**2026-09-25: two E4B plans exist.**~~ **Resolved 2026-09-25:** plan v2 carries over the older
  plan's memory headroom rule, eval categories, dev/held-out split, timing boundaries, and
  blocked-conversion finding. Where the two plans conflict, this plan wins.

## Decisions log

| Date | Decision | Made by | Reason |
| --- | --- | --- | --- |
| 2026-09-25 | Adopt plan D1–D6 (prebuilt package first, GPU, single engine, no fine-tune, 4,096 tokens, reversible promotion) | User + planning session | See plan §3 |
| 2026-09-25 | Shelve all Gemma 4 12B research (rotated-ternary and llama.cpp IQ2_M) and remove its weights; E4B QAT becomes the model path | User | The 12B's modeled size exceeds what the base iPhone 17 survived; see `Aquinas-Foundations/research/rotated-ternary/STATUS.md`, "Shelving record" |
| 2026-09-25 | Remove all Qwen weights except `Qwen3-4B-Aquinas-v3-Q4_K_M.gguf` in `Aquinas_Backend-llama-cpp-12b` | User | Disk space. Qwen is no longer a re-exportable fallback. |
| 2026-09-25 | Adopt plan v2 after independent review: conversion route blocked (D7); provenance labels but doesn't gate (D8); M2-L optional control (D9); early phone screen before quality; numeric memory cap; eval set 40 dev + 40 held-out with cross-model first-pass scoring and owner spot checks | User + planning session | [`Gemma4-E4B-QAT-Plan-Review.md`](Gemma4-E4B-QAT-Plan-Review.md), "Disposition" |

## Evidence

### C0 — Baseline identity and workspace
Run ID `C0-B0-1` (2026-09-25); evidence in `LocalModels/e4b-eval/C0-B0-1/`.
- Worktree path / branch / base commit: `/Users/ryanbaltodano/Developer/Aquinas-iOS-e4b-qat` ·
  `feature/gemma4-e4b-qat` · `31aa4763f0930d0e25d72c83d5494a33bdfe5a51` (local `main`)
- Excluded dirty files (main checkout): `Aquinas-iOS/Features/InsightTree/InsightTreeCanvasView.swift`
  (modified). Never staged.
- Provisioned ignored assets (source path → SHA-256): APFS clones (`cp -c`) from
  `/Users/ryanbaltodano/Developer/Aquinas-iOS-main/`; worktree hashes identical to source.
  - `Aquinas-iOS/LocalModels/gemma-4-E2B-it.litertlm` → `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282`
  - `Aquinas-iOS/LocalGrounding/embeddings.bin` → `6b481153d2b456033cde2503a414a5a5292bbc0c0aa26cf7e148650f08e6316a`
  - `Aquinas-iOS/LocalGrounding/passages.json` → `75fc02b45b4f458e60637a2bc41d08c68656e9b486d3458c1ca4f013ed5257e0`
  - `Aquinas-iOS/LocalGrounding/vocab.txt` → `07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3`
  - `Aquinas-iOS/LocalGrounding/MiniLM.mlpackage/Data/com.apple.CoreML/model.mlmodel` → `62bdbf45e70e5f66640fe65849207008adf86aa329e895d43895aabd171eeb27`
  - `…/MiniLM.mlpackage/Data/com.apple.CoreML/weights/weight.bin` → `2761ce1e94d0146e207a4f8802b8f15c8744bdaf5e81e8bc71775cc163d06d0f`
  - `…/MiniLM.mlpackage/Manifest.json` → `cff0a4d99898f58855e84b56610035775d67f63cd67d4e67fb8e649871b66fa8`
- LiteRT-LM iOS framework binary SHA-256: `ios-arm64/CLiteRTLM.framework/CLiteRTLM` →
  `32c2576cddd50542934289b850ce2061115f90f63de2857ff6f7c5f8f2425607`; simulator slice →
  `12aba062062d7dc3d027ded18452c58f90445a5d7b18e4114f17af34d0cb153a`
- Xcode / simulator runtime / free disk: Xcode 27.0 (27A5194q) · iPhone 17 simulator
  (`08720B72-C963-4711-94D4-3CCA9987B878`), iOS 27.0 (24A5355p) · host M4 Pro 24 GB, macOS 27.0 ·
  26 GiB free before build, 22 GiB after
- B0 computed SHA-256 (matches manifest?): `9a6345f1…65282`, 3,862,121,696 bytes. **Matches**
  `LiteRTModelManifest.aquinas`.
- Build result: **BUILD SUCCEEDED** (`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17'
  -derivedDataPath build/DerivedData build`). The built bundle contains the B0 package (same hash),
  `MiniLM.mlmodelc`, and grounding files with matching hashes, so no `NLEmbedding` fallback.

### C1 — Acquire and verify candidates
- One line per candidate: computed SHA-256 = published? · download date · run ID
- **M4-L:** computed `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff` =
  published, 2,969,059,328 bytes · downloaded 2026-09-25 (23:01–23:07 UTC) · run `C1-M4L-2`.
  File: `LocalModels/gemma-4-E4B-it-gpu.litertlm` (worktree root). Command:
  `HF_HUB_DISABLE_TELEMETRY=1 ../Aquinas_Backend/aquinas_env/bin/hf download
  litert-community/gemma-4-E4B-it-litert-lm gemma-4-E4B-it-gpu.litertlm --revision
  2eee7ac325f20eb8c9ac1d0e972f7c84663062da --local-dir LocalModels` (hf 1.9.0, unauthenticated).
  Free disk 22 GiB before, 19 GiB after.
- `C1-M4L-1` is a void attempt: the command was stored in a zsh variable that didn't word-split,
  so `hf` never ran (exit 127, nothing downloaded). Its folder is kept unchanged.
- **M2-L:** not downloaded. C8's optional control arm (D9) isn't planned yet; download it in C1
  style if the owner schedules it.
- **M4-Ls:** not downloaded. Only needed if C4/C5 send us back here.

### C2 — Provenance classification
Run ID `C2-M4L-1` (checked 2026-09-25); raw API responses in `LocalModels/e4b-eval/C2-M4L-1/sources/`,
package inspection in `peek.txt`, `tflite-histogram.json`, `tflite-metadata.txt` (commands in
`command.txt`). B0 comparison peek: `C2-B0-1`.
- Classification (confirmed-QAT + citation / unconfirmed): **unconfirmed.** Label M4-L "Gemma 4 E4B
  (LiteRT Community GPU package)" and never "QAT" (D8).
  - The E4B model card at the pinned revision (repo head is still `2eee7ac`) never says QAT. It
    describes the 3.66 GB standard package and a text-only web package, but not the GPU package.
  - The GPU package arrived in discussion #19 ("Upload gemma-4-E4B-it-gpu.litertlm", tylermullen,
    org member, merged 2026-08-07) with an **empty description**.
  - It is byte-for-byte the same **size** as `gemma-4-E4B-it-web.litertlm` (2,969,059,328 bytes),
    but its SHA-256 differs (web: `3904d826…4f57a0`). The card's Web row lists a 2,969 MB model
    as "specially optimized … text-only".
  - None of the 22 E4B discussions carries a maintainer statement on QAT.
- Discussions #16 and #18 findings:
  - **#16 "strange loops and errors"** (user JNK333, 2026-07-03, open, no reply): reasoning is right,
    but the visible answer degrades into loops, stray words, and duplicated digits
    (for example "455 spaces", "6.6.6 m"). This predates the GPU package, and the file used isn't
    named. It's a direct risk to our repetition guard and to named-entity fidelity; add a looping
    case to C8.
  - **#18 "context window size 4096？"** (open): the Android runtime threw "Input token ids are too
    long … 5173 >= 4096". Org member TobiasLogic says the `.litertlm` was exported with a fixed
    `kv_cache_max_len=4096`. Org member marissaw says `maxNumTokens` can raise it. Our production
    value (D5) is exactly 4,096, so any prompt plus history above that is a **hard error, not a
    truncation**; C6 must check how the adapter trims. Whether the GPU package's limit is 4,096
    wasn't determinable from its metadata.
- #2497 / E2B #30 / blog status when checked:
  - **LiteRT-LM #2497:** open. Three comments, all non-maintainers; the last is 2026-07-01. No
    official answer.
  - **E2B #30:** marissaw (org member, 2026-06-12) says the E2B card's `.litertlm` files "already use
    the QAT", "mixture of int2, int4 and int8". That's scoped to E2B. Follow-ups questioning it
    (gungorbasa 2026-07-01, on upload timing; zst50 2026-08-14, asking for clarification) are
    unanswered.
  - **Google QAT blog:** mentions LiteRT-LM only generically ("Use Google's lightweight LiteRT-LM
    runtime…"), with no artifact-specific statement.
- Supporting: decoder dtype histogram, `prefer_activation_type`:
  - `litert-lm-peek` (0.14.0): 3 sections, LiteRT-LM file version 1.6.0, created
    2026-08-06T00:40:13Z, author "The ODML Authors".
    - LlmMetadata: Gemma 4 template, `thought` channel, stop tokens 1/50/106.
    - SP tokenizer.
    - One TFLiteModel: `model_type: tf_lite_artisan_text_decoder`, `backend_constraint:
      gpu_artisan`, `gpu_artisan_weights_version: 0.0`.
    - **No** embedder, per-layer-embedder, vision, or audio section; it is **text-only**.
  - **`prefer_activation_type`: absent.** B0's decoder declares `prefer_activation_type: fp16`
    (`tf_lite_prefill_decode`, plus embedder/vision/per-layer-embedder sections).
  - TFLite section: 1 subgraph `GEMMA4_4P5B`, **0 operators** (a weights container for the GPU
    "artisan" path, not an executable op graph).
  - Constant bytes by dtype: INT4 1,945,108,480 (258 tensors); UINT8 748,683,264 (84); INT8
    250,347,520 (86); FLOAT32 8,625,184; INT32 6,381,568. **No INT2.** That differs from the
    int2/int4/int8 mix stated for the E2B QAT package. The dtypes alone can't tell QAT from PTQ.
  - Model metadata `backend = "gpu"`; `LlmParameters` decodes to 42 layers and hidden size 2,560,
    but has no nameable activation field without its schema.
  - **Consequence for C4:** a GPU-only artisan package probably **cannot run on the CPU backend**,
    so C4's `sim-gpu-fail` branch ("confirm coherent output with `--litert-probe-cpu`") may be
    impossible for M4-L. C4 records what actually happens.
- Draft owner-approval question (if any): see *Open questions*, 2026-09-25 "E4B GPU package
  provenance". **Not posted.**

### C3 — Harness hardening
- Commit: `fa88428` "Harden the LiteRT probe harness for the E4B evaluation (plan C3)".
  - New files: `Services/LiteRTModelOverride.swift` (the one shared resolver),
    `Features/Developer/LiteRTProbeFixture.swift`, and `Features/Developer/LiteRTProbeReport.swift`
    (report, `task_vm_info` memory sampling, stderr tee for native log lines).
  - Changed: `LiteRTDeviceProbe.swift`, `AquinasApplicationRuntime.swift` (DEBUG override),
    `LiteRTAquinasRuntime.swift` (`maxNumTokens` constant, once-per-process loaded-model log), and
    `Aquinas_iOSApp.swift` (lazy shared runtime).
- Flags as built:
  - Raw mode: `--litert-probe-context <n>` (default 2048); `--litert-probe-greedy` (the default:
    production conversation sampler, topK 1 / topP 1 / temperature 0 / seed 0);
    `--litert-probe-sampled` (topK 40, topP 0.95, temperature 0.2, seed 7; conflicts with
    greedy); `--litert-probe-raw-question "<q>"` (default "What is prudence?");
    `--litert-probe-cpu`.
  - Opt-in `--litert-probe-benchmark`: prefill/decode token counts and rates from LiteRT-LM
    `BenchmarkInfo`.
  - Quality mode: `--litert-probe-fixture <abs path | Documents name>` (JSON `turns` of
    user/assistant, `question`, optional `personality`, `compactedContext`) and
    `--litert-probe-question`.
  - Both modes: `--litert-model-path <abs>` or `--litert-model-document <name>` (the same
    resolver as the app); `--litert-probe-run-id <id>` is embedded in the report.
- **Deviations and decisions, all recorded here:**
  1. **Benchmark mode is opt-in, not always on.** Enabling it changes native engine settings
     (`is_benchmark: true`, `disable_delegate_clustering: true`,
     `wait_for_weights_conversion_complete_in_benchmark: true`; seen in `C3-B0-raw-1`), so a
     default gate run would not match production. B0's greedy output was identical with and
     without it (`C3-B0-raw-3` vs `C3-B0-raw-4`). C5 must opt in to get prefill/decode rates and
     should record that it did.
  2. **`--litert-probe-cpu` now also works in quality mode**, DEBUG only, through the runtime's
     existing `configureEvidenceExperimentCPU()` hook. It's needed because the simulator's Metal
     delegate caps single allocations at 268,435,456 bytes and B0 requests 402,653,184
     (`C3-B0-raw-1/2`: "Failed to initialize kernel … Max allocation size for this GPU").
     CPU runs stay diagnostic (D2).
  3. **Activation type** is read from the native executor settings dump
     (`activation_data_type: FLOAT16`) captured by teeing stderr, because the Swift API doesn't
     expose it. If that dump is absent, the report falls back to preference log lines and says so
     in `activation.source`.
  4. **Hashing timing.** The model SHA-256 in the report is computed *after* generation, so it
     never warms the page cache before a timed load. The runtime's DEBUG loaded-model log hashes
     in a detached utility task right after the first engine load, which **overlaps the first
     request's I/O in Debug full-app runs**; C9's protocol should account for this or time from
     after the log line. Release logs the manifest digest without rehashing.
  5. **The override fails loudly.** If a DEBUG override flag is present but can't be resolved,
     the app `fatalError`s rather than silently loading the bundled B0.
  6. **`AquinasApplicationRuntime.shared` is now resolved lazily** (first `body` use). A
     `--litert-probe` process therefore no longer builds MiniLM, grounding, and a second runtime
     object, so probe memory numbers aren't inflated. Normal app launch behavior is unchanged in
     practice: the runtime is created on the first render.
- Tests added (`Aquinas-iOSTests/LiteRTProbeHarnessTests.swift`, 13, all passing):
  `noFlagResolvesToNil`, `absolutePathResolves`, `documentNameResolves`,
  `missingFilesAreRejected`, `invalidOverrideValuesAreRejected`, `overrideStoreDerivesManifest`,
  `releaseIgnoresOverride`, `fixtureParsesToTranscript`, `fixtureWithoutTurns`,
  `malformedFixturesAreRejected`, `rawProbeDefaults`, `rawProbeFlags`,
  `rawProbeRejectsInvalidFlags`.
  - `releaseIgnoresOverride` exercises the gate logic. The Release compile-out itself is shown by
    `C3-release-build-1`: the Release simulator build succeeds, and the DEBUG-only
    "Model override failed" string is absent from the Release binary.
- Full suite result: **175/176 passed** (`C3-tests-2`, final code; `C3-tests-1` identical on the
  pre-fix code).
  - The one failure is `MiniLMGroundingRetrievalTests.namedPassagesUseSourceTextAnchors`: the
    "What do the Gospels say about the resurrection of Jesus?" case doesn't return a `citation-`
    reference containing "he isn't here, but is risen".
  - It **fails identically on base `31aa476`** with the same provisioned assets (`C3-basecheck-1`,
    a temporary detached worktree, since removed). C3 touched no grounding code.
  - The C3 gate says "all tests pass" and has no On-failure branch, so C3 is `blocked` pending the
    owner's decision.
- Build: Debug and Release simulator builds succeed.
- Sample result JSON path (raw and quality modes on B0): all runs use B0 `9a6345f1…65282`
  (computed in-report), on the iPhone 17 simulator with iOS 27.0.
  - Raw, GPU (default): `C3-B0-raw-2`. Status `failed`: the simulator Metal allocation ceiling,
    expected. The JSON is still complete (settings, activation FLOAT16, memory, error).
  - Raw, CPU, greedy: `C3-B0-raw-3` (warm cache) and `C3-B0-raw-5` (cold). Status `passed`.
    Cold load 6.69 s, generation 0.82 s, resolved activation **FLOAT16** (executor settings),
    peak footprint 818 MB. Response: "Prudence is the ability to govern and discipline oneself by
    the use of reason".
  - Raw, CPU with `--litert-probe-benchmark`: `C3-B0-raw-4`. 38 prefill / 17 decode tokens,
    251.5 / 24.9 tok/s, same response.
  - Quality, CPU, "What is prudence?": `C3-B0-quality-1`. Status `passed`, generation 3.86 s,
    `corpusGrounded`, peak footprint 4.37 GB (CPU weight mapping).
  - Quality, CPU, fixture `fixtures/c3-topic-shift.json` (mercy/justice turn, then "What's the
    capital of Portugal?"): `C3-B0-quality-2`. Status `passed`: "The capital of Portugal is
    Lisbon." plus unrequested elaboration, with no stale answer.
  - All result files are at `LocalModels/e4b-eval/<run-id>/litert-probe-result.json`, next to
    `console.log`, `litert-probe-stderr.log`, and `run.txt` (exact launch command, device, git
    head).
  - Reusable runner: `LocalModels/e4b-eval/run-sim-probe.sh <run-id> <flags…>`. It refuses to
    reuse a run ID, and `PROBE_CLEAR_CACHE=1` gives a cold cache.
  - `os_proc_available_memory()` reads 0 in the simulator, as expected; it's meaningful only on
    the phone (C5).

### C4 — Simulator compatibility
| Run ID | Mode | Backend | Load s | Gen s | Activation (and how it was determined) | Classification |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |
- Quoted log lines:

### C5 — Early phone screen
- Device / iOS build / backup location / Home data counts before → after:
- `operating_cap` (frozen, see Frozen values):
- B0 reference peak footprint (same protocol):

| Run ID | Case | Peak footprint | ÷ cap | Load s | Prefill tok/s | Decode tok/s | Largest Metal alloc | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | load only | | | | | | | |
| | prudence | | | | | | | |
| | 2K prefill + 256 | | | | | | | |
| | 4K prefill + 256 | | | | | | | |
- 60 s hold: jetsam or pressure events?

### C6 — Integration diagnostics
- Template/role/EOS/channel/truncation diff summary:
- Structured-schema results (per schema: pass / template / retrieval / model):
- Image-history and attachment behavior in text-only mode:
- E4B-specific adapter fixes (commit):

### C7 — Full-app functional and lifecycle stress
| Case | Result | Next request OK? | Memory back within 10%? | Engine overlap? | Notes |
| --- | --- | --- | --- | --- | --- |
| Conversation + follow-up + topic shift | | | | | |
| Definition / Insight / node label / Make Node / Midpoint | | | | | |
| Question of the Day / compaction / queue reorder | | | | | |
| Cancel mid-generation | | | | | |
| Foreground preemption | | | | | |
| Forced stall timeout | | | | | |
| Background during generation | | | | | |
| Idle unload → reload | | | | | |
| Memory warning | | | | | |

### C8 — Quality A/B
- Eval set location and SHA-256s (see Frozen values):
- Config hash:
- Scorer model:
- Owner review coverage (% of cases, all critical flags, weak-preference cases):

| Metric (held-out) | B0 | M4-L | M2-L (opt.) | Required | Pass? |
| --- | --- | --- | --- | --- | --- |
| Critical failures | | | | M4-L ≤ B0 and ≤ 1 | |
| Mean accuracy | | | | ≥ B0 + 0.3 and ≥ 3.0 | |
| Worst category Δ accuracy | | | | ≥ −0.5 | |
| Objective checks passed | | | | ≥ B0 | |
| Valid-link rate | | | | ≥ B0 | |
| Repetition / garbage rejects | | | | 0 | |
- Sampling (temperature 0.2) observations:

### C9 — Physical-device sustained gate
- Frozen protocol file:
- Device / iOS / backup / data counts:

| Metric | Budget | B0 | M4-L | Pass? |
| --- | --- | --- | --- | --- |
| Peak footprint | ≤ 0.85 × cap | | | |
| Cold load p95 / max | ≤ 12 s | | | |
| Cached load p95 / max | ≤ 3 s | | | |
| One-sentence complete p95 | ≤ 4 s | | | |
| Justice-and-mercy complete p95 | ≤ 60 s | | | |
| Turn 20 ÷ turn 1 latency | ≤ 1.5× | | | |
| Max thermal state | < critical | | | |
| 5× background/foreground; warning; idle > 60 s | survive and recover | | | |

### C10 — Promotion
- Owner approval (date and quote) and provenance label (D8):
- Rollback values (old manifest file · bytes · SHA-256; old file location):
- No-override phone smoke (loaded URL and SHA-256):
- Rollback check result:
- Commits / PR URL:

### C11 / C12 — Optional
- M2-L control analysis:
- Vision probe:

## Final summary

_Fill this in at the end: promoted or rejected, which gate decided it, and follow-ups (for
example a QAT-preserving fine-tune, reopening D7 if exporter support appears, raising the
context, or vision)._
