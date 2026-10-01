# Gemma 4 E4B QAT migration — execution plan

> **Status:** plan v2, revised 2026-09-25 after an independent review
> ([`Gemma4-E4B-QAT-Plan-Review.md`](Gemma4-E4B-QAT-Plan-Review.md); how each finding was handled
> is recorded at the end of that file). Not yet executed.
>
> This file is the **instructions**. It changes only when the plan itself changes. Record all
> progress, measurements, and decisions in [`Gemma4-E4B-QAT-Progress.md`](Gemma4-E4B-QAT-Progress.md),
> never here.

## 0. How to use these two documents

1. Read this plan in full, then read the ledger's status board, candidate registry, and
   *Open questions*.
2. **Choose the next checkpoint:** the first checkpoint in §5 order whose status is `todo`,
   `in-progress`, or `blocked`-with-a-recorded-resolution, **and** whose listed dependencies are
   all `done` or `skipped`. `skipped` counts as resolved only when the ledger records a reason.
   Never redo a `done` checkpoint unless the ledger marks its evidence invalid.
3. Before starting, set the checkpoint to `in-progress` with your session name and date, and
   commit.
4. When you finish, fill in **every** evidence field, set the status (`done`, `failed`,
   `blocked`, or `skipped`), and commit. Evidence must name the candidate ID, the exact command
   or launch arguments, and an evidence path (§4.4).
5. **Invalidation rule:** a gate's result belongs to one exact candidate: artifact hash, runtime,
   and configuration. If any of those changes, every dependent gate for that candidate must be
   rerun under a new run ID. A failed quality result is never erased by a later artifact or
   configuration swap; the new configuration is recorded as a **new candidate**.
6. When something fails, follow its **On failure** branch. If no branch applies, set the
   checkpoint to `blocked`, write the question in *Open questions*, and stop.

Required reading before any code change:
- [`AGENTS.md`](../AGENTS.md)
- [`Model-Runtime.md`](Model-Runtime.md)
- [`Development-Workflow.md`](Development-Workflow.md)
- [`../../Aquinas-Foundations/MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md),
  especially the LiteRT checkpoints and §8, the fine-tuning policy
- For background only: the earlier
  [`GEMMA-4-QAT-EVALUATION-PLAN.md`](../../Aquinas-Foundations/GEMMA-4-QAT-EVALUATION-PLAN.md),
  plus `research/gemma-4-qat/compatibility.md` and `LITERT-QAT-SUPPORT-CLARIFICATION.md`

Where this plan and the older one conflict, this plan wins.

## 1. Goal and non-goals

**Goal:** replace the on-device conversation model with Google's **Gemma 4 E4B** published
LiteRT-LM package, running on the existing LiteRT-LM runtime. Promote it only if it:
- beats the current checkpoint by a predeclared margin on a held-out quality set; and
- passes numeric memory, latency, lifecycle, and stability gates on the base iPhone 17 (8 GB).

**Non-goals:**
- **Fine-tuning** (decision D4).
- **Vision.** Stay text-only (optional C12).
- **Model hosting and download UI.**
- **Changing the production decoding policy.**
- **Converting Google's QAT Transformers checkpoint ourselves.** That route is blocked (§3, D7).

## 2. Background facts (verified 2026-09-25)

| Fact | Source |
| --- | --- |
| "4B" means **E4B**: 4.5B effective parameters, ~8B including per-layer embeddings. | HF `google/gemma-4-E4B-it-qat-mobile-transformers` |
| `litert-community/gemma-4-E4B-it-litert-lm` is at revision `2eee7ac325f20eb8c9ac1d0e972f7c84663062da`. Its GPU package is 2,969,059,328 bytes (HF SHA-256 `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff`) and its standard package is 3,659,530,240 bytes (SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`). | HF API tree listing |
| A LiteRT Community maintainer confirmed that the **E2B** `.litertlm` package is QAT (mixed int2/int4/int8), even though its filename doesn't say so. **No equivalent statement for E4B has been found.** | [E2B discussion #30](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/discussions/30); Foundations `LITERT-QAT-SUPPORT-CLARIFICATION.md` |
| Stock E2B package (candidate M2-L): revision `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1`, `gemma-4-E2B-it.litertlm`, 2,588,147,712 bytes, SHA-256 `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c`. An earlier base-iPhone run recorded a 3.89 s cold load. | Foundations `research/gemma-4-qat/compatibility.md` |
| Our exporter (`litert_torch 0.10.0.dev20260730`) accepts only `dynamic_wi4_afp32`, `dynamic_wi8_emb4_afp32`, and `dynamic_wi8_afp32`. It has **no import/preservation path** for the mobile QAT (wNa8o8) schema. | Same `compatibility.md` |
| The published iPhone 17 **Pro** benchmarks use the 3.66 GB package, cached initialization, 2,048 context, 1,024 prefill and 256 decode tokens. They do **not** predict our GPU package, the 8 GB base phone, or a 4,096-token app configuration. | HF E4B model card |
| **A simulator GPU failure is not a phone failure.** In August, a package that failed the simulator's Metal delegate ran cleanly on the physical iPhone 17. | `../Aquinas_Backend/CLAUDE.md` (August 3, 2026 correction) |
| The app vendors LiteRT-LM **v0.14.0**. | `Vendor/LiteRTLM` |

**Current code facts that constrain the gates:**

- **Probe, raw mode** (`LiteRTDeviceProbe.swift`) is hard-coded to 2,048 context, **samples at
  temperature 0.2**, and asks "What is prudence?". `--litert-probe-cpu` affects only raw mode.
- **Probe, quality mode** (`--litert-quality-probe`) uses the production `LiteRTAngroveModel` path
  and reads `--litert-probe-question`. It builds a **single-turn** transcript only.
- **`LiteRTModelStore`** checks a `developmentModelURL` by **size only**. It prefers an
  Application Support copy over the bundle.
- **`LiteRTAngroveRuntime`** deliberately **abandons** wedged native calls, leaving them running
  (`abandoningStall`). It also skips `conversation.cancel()` on unload because of a native
  thread-pool wedge, and waits 400 ms for teardown to drain. With a larger model, an abandoned
  engine overlapping a reload is a real out-of-memory risk.
- **Memory telemetry:** `ModelRuntimeLifecycle` already records resident memory at load/unload
  through OS signposts.

**Baseline:** the bundled `Angrove-iOS/LocalModels/gemma-4-E2B-it.litertlm` is the
`dynamic_wi8_emb4_afp32` E2B fine-tune, 3,862,121,696 bytes, SHA-256 `9a6345f1…65282`. Some
`MODEL-INTEGRATION.md` text calling it failed is stale; C0 establishes the truth.

## 3. Decisions (do not relitigate)

- **D1 — Evaluate the published package; don't convert.** Primary candidate: the E4B GPU package
  (M4-L). The standard package (M4-Ls) is tried only if M4-L cannot load on the phone.
- **D2 — Use the GPU (Metal) backend.** CPU runs are diagnostic only.
- **D3 — One process-scoped engine.** Switching models means changing
  `LiteRTModelManifest.angrove`, plus the DEBUG-only override from C3. Never add a second live
  engine or a model picker.
- **D4 — No fine-tuning in this plan.** Evaluate raw instruction checkpoints first
  (`MODEL-INTEGRATION.md` §8). Merging a LoRA adapter and re-exporting through our PTQ recipes
  would produce a *different* quantized model. It would not preserve Google's QAT-trained
  low-bit tolerance, and its fidelity would be unverified. A QAT-preserving fine-tune is a
  separate future plan.
- **D5 — Keep the production context at 4,096 tokens** for a like-for-like comparison. The C5
  screen still measures 2K and 4K.
- **D6 — Every promotion is reversible.** Record the old manifest, keep the old file, and verify
  rollback in C10.
- **D7 — The conversion route is blocked.** Exporting from
  `google/gemma-4-E4B-it-qat-mobile-transformers` is **not** part of this plan. Reopen it only if
  a pinned exporter version *documents* mobile QAT import and preservation. That would be a new
  plan with a time box and at least 40 GB of free disk.
- **D8 — Label provenance honestly; it doesn't gate quality.** Promotion depends on measured
  gates, not on the "QAT" label. M4-L may be called "QAT" in docs and UI **only** with an
  artifact-specific maintainer or source statement (C2). A candidate with unconfirmed provenance
  may be promoted only after the owner records a decision to do so under an accurate label.
- **D9 — M2-L (stock QAT E2B) is an optional control arm.** It shows whether any gain comes from
  QAT or from the larger E4B model. Run it in C8 only if disk space and time allow; it never
  blocks promotion.

## 4. Environment, safety, and evidence rules

### 4.1 Workspace
- Work on a branch, `feature/gemma4-e4b-qat`, in a **git worktree** created from `main`.
  Record the base commit.
- The main checkout has unrelated uncommitted work. Record the list of dirty files as
  *excluded* and never stage them.
- **Ignored assets are not in a worktree.** Both of these are gitignored:
  - the E2B baseline model, `Angrove-iOS/LocalModels/gemma-4-E2B-it.litertlm`;
  - the MiniLM/grounding assets, `Angrove-iOS/LocalGrounding/` (`MiniLM.mlpackage`,
    `embeddings.bin`, `passages.json`, `vocab.txt`).

  Provision them explicitly: symlink or copy them from the main checkout, and record each source
  path and hash. Otherwise the worktree's builds silently fall back to `NLEmbedding` and the
  lexical grounding, which would invalidate every quality comparison.

### 4.2 Builds and devices
- Build on a concrete arm64 simulator:
  `-destination 'platform=iOS Simulator,name=iPhone 17'`.
- Before any device install, back up the app data (`Development-Workflow.md`) and record the
  Home data counts.
- Use a **disposable bundle ID** for device probes. The llama.cpp research used
  `com.ryanbaltodano.Aquinas-iOS.ModelProbe`; reuse that pattern.
- **Never** run `devicectl … --remove-existing-content true` against the production container.

### 4.3 Disk
- The main path needs about 15–20 GB (downloads, builds, caches). M2-L adds 2.6 GB.
- Check `df -h /` before every download, and stop and ask if less than 12 GB would remain.
- Models live in the gitignored `LocalModels/` at the repo root. Never commit a model.

### 4.4 Evidence
- Every run gets an ID, `<checkpoint>-<candidate>-<n>`, for example `C5-M4L-1`.
- Raw outputs go to `LocalModels/e4b-eval/<run-id>/` (gitignored). Each run folder holds the
  exact command or launch arguments, the effective settings the probe reports, and the device
  and OS.
- **Evidence folders are immutable.** A rerun gets a new ID.
- The ledger records a summary and each run ID. Committed files must stay small, so never
  commit model outputs larger than a few KB.

## 5. Checkpoints

Order and dependencies:

`C0 → C1 → C2 → C3 → C4 → C5 → C6 → C7 → C8 → C9 → C10`, with `C11` and `C12` optional.

C2 can run in parallel with C3.

### C0 — Baseline identity and workspace

**Depends on:** nothing.

**Do**
1. Set up the worktree (§4.1) and provision the ignored assets.
2. Record the environment:
   - the base commit, the list of excluded dirty files, and free disk;
   - the Xcode and simulator runtime versions;
   - the LiteRT-LM iOS framework binary SHA-256
     (`Vendor/LiteRTLM/Binaries/CLiteRTLM.xcframework/ios-arm64/…`).
3. Re-identify the B0 baseline by **computing** its SHA-256 and comparing it to the manifest.
4. Build the app.

**Gate:** the build passes and B0's identity matches the manifest.

**Evidence:** all of the above.

### C1 — Acquire and verify the candidates

**Depends on:** C0.

**Do**
1. Download M4-L (`gemma-4-E4B-it-gpu.litertlm`) at the **pinned revision** from §2 into
   `LocalModels/`. Use `hf download` from `../Aquinas_Backend/aquinas_env` with `--revision`.
2. Compute its SHA-256 and compare it to the **HF-published LFS SHA-256** in §2.
3. Download M2-L the same way, but only if C8's optional arm is planned.
4. Download M4-Ls only if C4/C5 send you here.

**Gate:** the computed hash equals the published hash. A mismatch fails the checkpoint; delete
the file and retry once.

**Evidence:** a registry row for each candidate.

### C2 — Provenance classification

**Depends on:** C1. Can run in parallel with C3.

**Do**
1. Search the E4B repository's model card and discussions for a maintainer statement on QAT
   provenance. Read discussions #16 ("strange loops and errors") and #18 ("context window size
   4096？") as well; both are relevant to our configuration.
2. Recheck E2B discussion #30, Google's QAT blog post, and LiteRT-LM issue #2497 for updates.
3. As **supporting** evidence only, inspect the package with `litert-lm-peek` or
   `litert-lm-builder` from `../Aquinas_Backend/litert_conversion_env`: sections, metadata,
   `prefer_activation_type`, and the decoder's dtype histogram.
4. If nothing definitive exists, draft a one-paragraph question for the E4B discussion board and
   put it in *Open questions*. **Posting it requires owner approval.**

**Gate:** none. The classification is **confirmed-QAT** (with a citation) or **unconfirmed**.
Both continue; see D8.

**Evidence:** the classification, citations, the dtype histogram, and the activation metadata.

### C3 — Harness hardening (code)

**Depends on:** C0. This is the only checkpoint that adds shared app code before promotion.

**Do**
1. **Raw probe.** Add launch flags `--litert-probe-context <n>` (default 2048),
   `--litert-probe-greedy`, and `--litert-probe-raw-question "<q>"`.
   - `--litert-probe-greedy` gives deterministic decoding matching the production sampler; it
     is the default for any gate.
   - Temperature 0.2 remains available only through an explicit `--litert-probe-sampled`.
2. **Quality probe.** Add `--litert-probe-fixture <file>`. It loads a JSON conversation fixture
   (prior user/assistant turns plus a final question) from Documents or an absolute simulator
   path, so multi-turn and topic-shift cases run through the production path.
3. **Effective-settings report.** Both modes print, and write to
   `Documents/litert-probe-result.json`:
   - the model URL, byte count, and **computed** SHA-256;
   - the backend, context, and sampler;
   - the resolved activation type, if the runtime exposes it (otherwise the relevant log line);
   - load and generation seconds, and prefill and decode token counts, if available;
   - the peak physical footprint (`task_vm_info.phys_footprint`) and `os_proc_available_memory()`
     at launch, before load, and after generation.
4. **DEBUG model override.** In `AngroveApplicationRuntime.init`, inside an `#if DEBUG` block,
   accept `--litert-model-path <abs>` or
   `--litert-model-document <name>`.
   - Resolve the file with **one shared resolver** used by both the probe and the app.
   - Build `LiteRTModelStore(manifest: <derived name/size, sha "development-override">,
     developmentModelURL:)`.
   - Log the loaded URL and SHA-256 once at engine initialization.
   - Release builds ignore both flags.
5. Make `LiteRTDeviceProbe.locateModel()` fall back to `LiteRTModelManifest.angrove.fileName`.
6. **Tests.** The resolver resolves each flag form, and rejects missing files. The override is
   compiled out of Release. Parse fixtures, including a malformed fixture.
7. Run the build and the full test suite.

**Gate:** the build and all tests pass. A simulator run of each probe mode on B0 writes a result
JSON containing every field in step 3.

**Evidence:** commit, test names, and a sample result JSON path.

### C4 — Simulator compatibility (informational)

**Depends on:** C1, C3.

**Do:** run M4-L through the raw probe (greedy, 2048, "What is prudence?") and the quality probe
(`--litert-probe-question "What is prudence?"`) in the arm64 simulator. Capture:
- Metal device creation;
- delegate selection;
- the resolved activation type;
- any `Failed to initialize kernel`, max-buffer, or delegate-rollback errors;
- load and generation seconds.

**Classification:** `sim-pass`, `sim-gpu-fail` (the simulator's Metal delegate failed), or
`model-fail` (it fails on CPU as well, or the output is incoherent on CPU).

**Gate and branches**
- **`sim-pass`:** go to C5.
- **`sim-gpu-fail`:** do **not** reject the candidate. Confirm it generates coherent output with
  `--litert-probe-cpu`, record `sim-gpu-fail`, and go to C5. The phone decides.
- **`model-fail`:** go to C5 anyway for a single bounded load test. If the phone also fails, try
  M4-Ls once (C1).
- **FLOAT32 activation:** record whether it comes from a quantized graph by design or from an
  unintended fallback (look for delegate or kernel fallback log lines). Do not patch package
  metadata.

### C5 — Early phone memory and compatibility screen

**Depends on:** C4. This runs **before** any expensive quality work. Disposable bundle ID only.

**Do**
1. **Freeze the memory cap first.**
   - On the base iPhone 17, in the probe app with the production entitlements, record
     `os_proc_available_memory()` at launch.
   - Run B0 through the same protocol (steps 2–3) and record its peak footprint.
   - Define **`operating_cap` = the launch value of `os_proc_available_memory()`** on that
     device and OS build.
   - The gate is **`candidate_peak ≤ 0.85 × operating_cap`**, measured in the full app during
     C9. The owner may revise the cap in *Decisions* **before** candidate numbers are seen.
2. **M4-L raw probe (greedy)**, one run each, in a fresh process:
   - load only;
   - "What is prudence?";
   - a ~2,000-token prefill fixture with a 256-token decode;
   - a ~4,000-token prefill fixture with a 256-token decode.

   Record the peak footprint, load seconds, and prefill and decode rates for each. If the
   runtime reports it, also record the largest single Metal allocation.
3. Hold the loaded session for 60 s after the 4K run. Watch for jetsam or `vm-pageshortage`
   entries in the device logs.

**Gate:** there is no jetsam, signal 9, or GPU out-of-memory error. The 4K-run peak footprint
must be ≤ 0.80 × `operating_cap`; this is stricter than C9 because the full app adds MiniLM and
UI overhead. The output must be coherent.

**On failure**
- Try M4-Ls on the GPU once.
- If only the 4K run fails, record it and ask the owner whether a 2K-context configuration
  should become a **new candidate**. That would override D5.
- Otherwise mark C5 `failed` and stop. The plan's outcome is "rejected with evidence".

### C6 — Integration diagnostics

**Depends on:** C5.

**Do**
1. **Rendered prompts.** Diff B0 against M4-L on:
   - the rendered chat template and role markers;
   - how system instructions are placed;
   - EOS and channel handling, including the thought/visible channel markers;
   - how the runtime truncates at 4,096 tokens.

   Use a fixed fixture and print the exact prompt LiteRT-LM receives, if it's exposed; otherwise
   use a tokenized reconstruction.
2. **Structured outputs.** Run every structured-output schema used locally once through the
   quality path: definition, node label, Midpoint, Make Node, Question of the Day, and
   compaction. Classify each failure as **template/parsing**, **retrieval**, or **model**.
3. **Images in text-only mode.** Open a conversation that has image-bearing history and try to
   attach an image. Confirm the app degrades gracefully, with no crash and no silent loss of
   text context.

**Gate:** there are no template or parsing failures. Fix these in the adapter only when they are
**E4B-specific**, and record the fix. Model failures continue to C8 as quality findings.

### C7 — Full-app functional and lifecycle stress (simulator)

**Depends on:** C6.

Run the full app with the C3 override. The app has no backend recovery path, so a local failure
surfaces directly.

1. **Functional.** Run:
   - three questions plus one follow-up, and a topic-shift reset;
   - a contextual definition;
   - save an Insight, then run node label, Make Node (exactly 3), and Midpoint;
   - Question of the Day and compaction;
   - queue reorder.
2. **Lifecycle stress.** Run each of these, and each must be followed by a **successful new
   request**:
   - cancel mid-generation;
   - foreground preemption of background work;
   - a forced stall timeout (temporarily lower the watchdog in DEBUG);
   - backgrounding during generation;
   - idle unload followed by reload;
   - a simulated memory warning.
3. **Assertions for each stress case:**
   - there are no stale UI updates after cancellation;
   - resident memory returns to within 10% of its pre-request level after unload;
   - the signposts show **no overlap** between an abandoned engine's native work and a new
     engine's load. If an abandoned call is still running when reload starts, record it as a
     blocker.

**Gate:** all functional actions validate locally, and all stress cases pass their assertions.

### C8 — Quality A/B

**Depends on:** C7.

**Do**
1. **Build the eval set before looking at any candidate output**, and write it to
   `LocalModels/e4b-eval/eval-set/`.
   - **40 development cases** and **40 held-out cases**. Freeze both files and record their
     SHA-256 in the ledger.
   - Categories, spread evenly across both sets:
     - definitions/distinctions;
     - reasoning/application;
     - source-dependent questions where grounding should apply;
     - absent or conflicting evidence, where the answer should state uncertainty;
     - multi-turn and topic shift (as fixtures);
     - known regressions.

     The known regressions come from the §6 seed list: factual traps, repetition/looping,
     shallow answers, and named-entity fidelity.
   - Each case records its category, whether it is a fixture, and any **objective check** (a
     required fact or a forbidden claim).
2. **Freeze the configuration.** This means production retrieval, the same grounding corpus,
   deterministic decoding, the same budgets, and 4,096 context. Record the configuration hash.
   Prompt adjustments may be tried on the development set **only**, and only for E4B-specific
   template issues from C6.
3. **Run.** Run B0 and M4-L (and M2-L if D9 applies) on both sets through the quality probe with
   fixtures. Record whether grounding answered each case, or generation did.
4. **Score.**
   - **Objective checks and link validity:** score these automatically. Link validity means each
     `{{term}}` marker yields a key term that actually occurs in the text, within the ceiling of
     12.
   - **Subjective scores:** accuracy, depth, and voice, each 1–5, plus a critical-failure flag.
     First-pass scoring is done by **a different model** from any candidate (for example, the
     reviewing assistant), using the rubric in the older plan and blind A/B labels
     (`blind-key.json`).
   - **Owner review:** the owner reviews at least 25% of cases, **all** critical flags, and every
     case where the scorer's preference is weak. The owner's scores override the scorer's.
5. **Informational:** run five development cases at temperature 0.2, seed 7, with 3 repeats. This
   does not change the production policy.

**Gate (held-out set only)**

| Check | Required |
| --- | --- |
| Critical failures | M4-L ≤ B0, and at most 1 |
| Mean accuracy | M4-L ≥ B0 + 0.3 **and** ≥ 3.0 absolute |
| Any category's mean accuracy | Does not regress by more than 0.5 against B0 |
| Objective checks passed | M4-L ≥ B0 |
| Valid-link rate | M4-L ≥ B0 |
| Repetition or garbage rejects | Zero |

**Absolute floors apply even if B0 performs badly.** A broken baseline never lowers the bar.

**On failure:** mark C8 `failed`. The outcome is "rejected with evidence". Do not go back to
conversion (D7).

### C9 — Physical-device sustained gate

**Depends on:** C8. Uses the disposable bundle ID and the full app with the override.

**Protocol (freeze in the ledger before running)**
- **Cold** means a fresh process with the LiteRT cache cleared. **Cached** means a fresh process
  with the cache present.
- Run 5 trials of each. Report every sample, the p95, and the max.
- Time these boundaries:
  - request accepted;
  - retrieval complete;
  - prefill start and end;
  - first visible output delivered to the UI (LiteRT currently buffers, so report this
    honestly);
  - visible answer complete;
  - metadata complete.
- Use fixed inputs: the one-sentence prompt, and the justice-and-mercy prompt with a declared
  output budget.
- Alternate B0 and M4-L sessions to limit thermal and ordering bias. Record the starting thermal
  state.

**Also run**
- 20 consecutive turns, recording the per-turn latency, the thermal state over time, and the
  peak physical footprint;
- 5 background/foreground cycles during generation;
- 1 simulated memory warning, followed by a successful request;
- an idle hold of more than 60 s.

**Gate (provisional product budgets; the owner may revise them before the run)**

| Metric | Budget |
| --- | --- |
| Peak physical footprint | ≤ 0.85 × `operating_cap` (C5) |
| Cold load (p95) | ≤ 12 s |
| Cached load (p95) | ≤ 3 s |
| One-sentence answer complete (p95) | ≤ 4 s |
| Justice-and-mercy answer complete (p95) | ≤ 60 s |
| Turn-20 latency vs. turn-1 latency | ≤ 1.5× |
| Thermal state | Never `critical` |

There must also be no jetsam, and the app must recover from every warning and background cycle.

**On failure:** record it. Do not promote. The owner decides whether any configuration change
becomes a new candidate.

### C10 — Promotion

**Depends on:** C9, plus **explicit owner approval recorded in the ledger**. D8 applies to the
label.

**Do**
1. Update `LiteRTModelManifest.angrove`: the file name, bytes, and SHA-256, plus a comment
   stating the provenance classification.
2. Place the package as the development seed at `Angrove-iOS/LocalModels/<name>`. Keep B0's file
   in root `LocalModels/` until the owner signs off.
3. Update the `visionBackend` comment in `LiteRTAngroveRuntime.swift`. Stay text-only.
4. Update the docs in the same change:
   - `MODEL-INTEGRATION.md`: add a dated checkpoint with the measurements, fix the stale `wi8`
     text, and update §2.
   - `Model-Runtime.md`.
   - Mark this plan `executed`.
5. Run the build and the full test suite.
6. **Phone checks, without the override.**
   - Run a **no-override** smoke test on the phone, using the packaged artifact installed under
     the disposable ID. The log must show the loaded URL and SHA-256.
   - **Rollback check:** restore the old manifest and file on a scratch branch, rebuild, and
     confirm B0 loads.
7. Open a PR from `feature/gemma4-e4b-qat`. Don't merge it.

**Gate:** the build and tests are green, both phone checks pass, and the PR is open.

**Evidence:** the commits, the PR URL, the rollback values, and the verified loaded hashes.

### C11 — Optional: M2-L control analysis

If D9 ran, summarize whether M4-L's gains over B0 track M2-L's. In other words, is the gain from
QAT or from model size? This is informational only.

### C12 — Optional: vision probe (never blocks)

With the promoted package, set `visionBackend = .gpu` in a DEBUG experiment and test one image.
Record whether the vision tower loads. Report only.

## 6. Eval seed list (seeds for C8, not the eval set itself)

These are the known regressions from `MODEL-INTEGRATION.md`. Put each in the development or
held-out set, not both. Add fresh paraphrase variants to the other set.

| Seed | Must |
| --- | --- |
| What is prudence? | Short and accurate |
| Can an otherwise good deed be morally tainted by an evil motive? | Show dialectic depth |
| Think carefully about whether mercy can conflict with justice. | Show depth without looping |
| How can justice and mercy work together when someone repeatedly does wrong? | Show depth |
| Was the Peloponnesian War part of the Greco-Persian Wars? | Say no |
| When was the First Council of Nicaea, and what did it address? | Say 325 and Arianism |
| What did Constantinople (381) add to the creed? | Name the Holy Spirit article |
| Who wrote the Didache? | Say the author is unknown |
| What is natural law? | Include `{{term}}` markers |
| How does Aquinas distinguish essence from existence? | Keep named entities exact |
| Ask the mercy/justice question, then "What's the capital of Portugal?" | Not repeat the stale answer |

## 7. Definition of done

The work is complete when one of these is true:
- **Promoted:** C10 is `done`, the PR is open, and the docs are updated.
- **Rejected with evidence:** a gate failed, B0 is unchanged, and the ledger's final summary says
  why.
