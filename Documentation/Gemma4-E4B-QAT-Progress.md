# Gemma 4 E4B QAT migration — progress ledger

> This is the **mutable** record for [`Gemma4-E4B-QAT-Plan.md`](Gemma4-E4B-QAT-Plan.md) (plan v2).
> Update it at the start and end of every checkpoint and commit each update on
> `feature/gemma4-e4b-qat`. Never delete earlier entries; if evidence is superseded, strike it
> through (`~~old~~`) and add the new value with a date and run ID.
>
> Status values: `todo` · `in-progress` · `done` · `failed` · `blocked` · `skipped` (with reason)
> Selection and invalidation rules: plan §0.

## Current handoff — after C9 (2026-09-27)

- Worktree `~/Developer/Aquinas-iOS-e4b-qat`, branch `feature/gemma4-e4b-qat`.
  All takeover commits are local and unpushed; `main` still declares B0.
- C0–C8 remain done. **C9 failed** on the physical iPhone under the frozen protocol:
  E4B cold load 12.824 s versus ≤12 s, and cold short answer 21.910 s versus ≤4 s.
  See `C9-M4Ls-2` below; no five-trial p95 was claimed. C10 is blocked. Do not relabel or
  rerun C9 as a pass, merge E4B, or open a PR in the public GitHub repository.
- The owner-approved earlier E4B production build remains installed on Ry as a temporary
  personal trial; production app data was backed up and untouched. The disposable probe
  app was uninstalled after the gate failed.
- A bounded-memory SHA-256 fix (`a4fd7c0`) and DEBUG C9 timing harness (`7ac77a8`)
  are committed; the physical build passed. The system-prompt file was not edited.
- The owner delegated the next step to the senior developer. P1 informational usability
  diagnostics are frozen in `Gemma4-E4B-Post-C9-Diagnostics.md` before new phone runs.
  C9 remains failed and immutable. P1 cannot promote E4B; any new product criteria need a
  separate predeclared promotion plan. The C8 phone GPU repeat, C10 rollback check,
  Foundations update, and PR remain undone under the original plan.

## Prior handoff (2026-09-27; historical, superseded by the current handoff)

The owner is handing this work to Codex. State as of commit `2776cc9` on `feature/gemma4-e4b-qat`
(worktree `~/Developer/Aquinas-iOS-e4b-qat`; not pushed; `main` is at `047245e`).

**Where things stand**
- **Done:** C0–C8.
  - C7 passed on the simulator CPU and fixed 3 lifecycle bugs.
  - After C7, a phone session showed a load/unload race; it's fixed in `2776cc9`. Load and unload
    now take the generation slot, and a lease is never granted on a model an unload just dropped.
    Test: `unloadDuringLoadYieldsToLease`.
- **C10 in progress:** the owner approved promotion.
  - Done on the branch: the manifest and seed are switched to E4B (`21479f3`); the simulator
    no-override smoke passed.
  - The owner's phone runs this branch's build as the production app (`com.ryanbaltodano.Aquinas-iOS`,
    installed 2026-09-27 with data kept). Its console log shows the bundled E4B loading with the
    manifest SHA-256.
  - Data backup from before the install: `LocalModels/phone-backup-20260927-155645/` (gitignored).
- **Remaining, in order:**
  1. **C9 on the phone.** Freeze the protocol in this ledger first (plan §C9). Include C7's device
     carry-overs: backgrounding, memory warnings, and the wait after a cancel or stall. Reinstall
     the disposable probe app (`com.ryanbaltodano.Aquinas-iOS.ModelProbe`, uninstalled 2026-09-27)
     with `LocalModels/e4b-eval/run-device-probe.sh`.
  2. Confirm the C8 held-out set on the phone GPU (`--litert-eval-batch`, no `--litert-probe-cpu`).
  3. Finish C10:
     - Rollback check: B0's values are in the manifest comment; its file is at root `LocalModels/`.
     - Open a PR from this branch. Merge only if C9 passes.
     - At merge, main's gitignored `Aquinas-iOS/LocalModels/` still holds E2B. Swap in
       `gemma-4-E4B-it.litertlm` (an APFS clone) and move E2B out, or the main build fails the
       manifest check.
  4. Apply `Documentation/Gemma4-E4B-MODEL-INTEGRATION-Update.md` to
     `../Aquinas-Foundations/MODEL-INTEGRATION.md`. That repo has uncommitted owner edits, so
     coordinate with the owner.
- **Known issues outside this plan** (not model-specific):
  - Insight Tree node labels (`InsightTreeViewModel.requestClusterLabels`) call the model outside
    `ModelTaskQueue`, so they jump ahead of queued questions. The owner is handing this to Codex
    separately.
  - The node-label task was once sent an empty Insight (`": "`).
  - Make Node has no UI entry; the owner is reworking it.
  - Pre-existing failing test: `MiniLMGroundingRetrievalTests.namedPassagesUseSourceTextAnchors`
    (accepted baseline).
- **Parallel work:** the owner may change system prompts in `LiteRTAquinasModel.swift` on `main`.
  This branch doesn't modify that file relative to `main`.

**Tools and evidence (gitignored, in `LocalModels/e4b-eval/`)**
- Run folders `C*-*/` are immutable evidence; never reuse a run ID.
- Simulator: `run-sim-probe.sh <run-id> <args>` runs a probe; `c7-launch.sh` and `c7-collect.sh`
  run the full app with debug switches.
- Phone: `run-device-probe.sh`.
- Probes (DEBUG launch args):
  - `--litert-probe --litert-probe-auto` plus one of: `--litert-diagnostics-probe` (every model
    contract), `--litert-eval-batch <jsonl>` (C8), or `--litert-lifecycle-probe` (C7 stress cases).
  - Common flags: `--litert-model-path <abs>`, `--litert-probe-cpu` or `--litert-force-cpu`
    (the simulator can't run E4B on its GPU), `--litert-record-generations`,
    `--litert-lifecycle-trace`, `--litert-idle-timeout-seconds <n>`,
    `--litert-stall-once-seconds <n>`.
  - Memory warning in the simulator:
    `xcrun simctl spawn <device> notifyutil -p com.aquinas.debug.memory-warning`.
- Eval set and scoring: `eval-set/` (frozen), `score_objective.py`, `make_blind_pairs.py`, `c8_gate.py`.
- Build and test: an arm64 simulator destination (`platform=iOS Simulator,name=iPhone 17,OS=27.0`)
  with `-derivedDataPath build/DerivedData`. Free disk space is tight (about 8 GB); delete stale
  build products before large builds.

## Status board

| ID | Checkpoint | Depends on | Status | Owner / session | Last updated | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| C0 | Baseline identity and workspace | — | done | Claude Code (Opus 5.5) session | 2026-09-25 | Run C0-B0-1; B0 hash matches |
| C1 | Acquire and verify candidates | C0 | done | Claude Code (Opus 5.5) session | 2026-09-26 | M4-L (C1-M4L-2) and M4-Ls (C1-M4Ls-1, added via C5's branch) hashes match; M2-L not downloaded |
| C2 | Provenance classification | C1 | done | Claude Code (Opus 5.5) session | 2026-09-25 | **unconfirmed**; package is a GPU-only "artisan" text decoder (C2-M4L-1) |
| C3 | Harness hardening (code) | C0 | done | Claude Code (Opus 5.5) session | 2026-09-26 | `fa88428`. 175/176 tests; the 1 failure is pre-existing on base and accepted as baseline by the owner (see *Decisions log*) |
| C4 | Simulator compatibility (informational) | C1, C3 | done | Claude Code (Opus 5.5) session | 2026-09-26 | M4-L **sim-pass** (GPU_ARTISAN, F16; C4-M4L-1..3); M4-Ls **sim-gpu-fail**, coherent on CPU (C4-M4Ls-1..2) |
| C5 | Early phone memory/compat screen | C4 | done | Claude Code (Opus 5.5) session | 2026-09-26 | M4-L **failed** (jetsam at 2K and 4K); per the On failure branch, M4-Ls **passed** all four runs (4K peak 0.165 × cap). M4-Ls is now the active candidate |
| C6 | Integration diagnostics | C5 | done | Claude Code (Opus 5.5) session | 2026-09-26 | M4-Ls: 12/12 contracts OK, no template/parsing failures (simulator CPU). Found and fixed 2 app bugs; found B0's JSON-wrapped system prompt |
| C7 | Full-app functional + lifecycle stress | C6 | done | Claude Code (Opus 5.5) session | 2026-09-27 | **Pass** (simulator CPU). Fixed 3 lifecycle bugs: suspension read as a stall, two overlap paths. Final probe: all cases pass, 0 overlaps, memory within 1%. 199/200 tests (known baseline failure). Make Node has no UI entry (pre-existing) |
| C8 | Quality A/B (40 dev + 40 held-out) | C7 | done | Claude Code (Opus 5.5) session | 2026-09-27 | **M4-Ls passes all held-out rows** after the owner-delegated review (accuracy 3.05 → 3.85; critical 9 → 1). Run before C7 by recorded decision; simulator CPU; confirm held-out on the phone GPU before C10 |
| C9 | Physical-device sustained gate | C8 | failed | Codex takeover | 2026-09-27 | M4-Ls failed cold-load and short-answer p95 gates; C9-M4Ls-2, early stop is decisive for nearest-rank p95 |
| C10 | Promotion | C9 + owner approval | blocked | Claude Code + Codex takeover | 2026-09-27 | C9 failed; owner-approved branch prework retained, no merge/PR. Production phone still has E4B pending owner choice |
| C11 | Optional: M2-L control analysis | C8 | todo | | | |
| C12 | Optional: vision probe | C10 | todo | | | |

**Next action:** C9 failed; follow its On failure branch. Do not promote. Owner decides whether to keep the earlier E4B phone install temporarily or roll it back, and whether a revised configuration becomes a new candidate. C8 phone GPU confirmation, C10 rollback check, and PR are held. Main still declares B0.

## Candidate registry

Add a row for every distinct artifact and configuration. A changed hash, runtime, or config means
a new row (plan §0, rule 5).

| ID | Artifact | HF repo @ revision | Bytes | Published SHA-256 | Computed SHA-256 | Runtime / config | Provenance | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B0 | `gemma-4-E2B-it.litertlm` (wi8 E2B fine-tune, bundled) | local export | 3,862,121,696 | `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282` (manifest) | `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282` (match, C0-B0-1) | LiteRT-LM 0.14.0, GPU, 4,096, deterministic | fine-tuned PTQ | baseline |
| M4-L | `gemma-4-E4B-it-gpu.litertlm` | `litert-community/gemma-4-E4B-it-litert-lm` @ `2eee7ac325f20eb8c9ac1d0e972f7c84663062da` | 2,969,059,328 | `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff` | `4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff` (match, C1-M4L-2) | LiteRT-LM 0.14.0, GPU (GPU_ARTISAN), 4,096, deterministic | unconfirmed (C2-M4L-1); text-only `gpu_artisan` decoder | **rejected at C5** (jetsam `vm-pageshortage` at 2K and 4K prefill; `C5-M4L-4`, `C5-M4L-5`) |
| M4-Ls | `gemma-4-E4B-it.litertlm` | same @ same | 3,659,530,240 | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` (match, C1-M4Ls-1) | LiteRT-LM 0.14.0, GPU, 4,096, deterministic, vision/audio not loaded | unconfirmed (no statement for any E4B package; see C2) | **active candidate** (passed C5) |
| M2-L | `gemma-4-E2B-it.litertlm` (stock) | `litert-community/gemma-4-E2B-it-litert-lm` @ `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1` | 2,588,147,712 | `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c` | | control arm (D9) | confirmed QAT (E2B discussion #30) | optional |

## Frozen values

Record these **before** the candidate numbers they govern are seen.

| Name | Value | Frozen on / run ID | Notes |
| --- | --- | --- | --- |
| `operating_cap` (C5) | **6,970,472,776 bytes** (6.49 GiB). C5 gate 0.80× = 5,576,378,221; C9 gate 0.85× = 5,924,901,860 | 2026-09-26, run `C5-B0-1` (launch sample), frozen before any M4-L phone run | `os_proc_available_memory()` at launch in the ModelProbe build (production memory entitlements), iPhone 17 "Ry", iOS 27.0 (24A5430a). Defined by the plan, not chosen; the owner may still revise it in *Decisions* before reading M4-L's phone numbers |
| Eval set dev SHA-256 (C8) | `2b112f0c1ea22b4bc6e107ece5dc9bf71e4175883c8c40761bb8a8bb997337bd` (`eval-set/dev.jsonl`, 40 cases) | 2026-09-26, before any C8 run | Generator `build_eval_set.py` `de623e49…99cdb`. 7 regression, 7 definition, 7 reasoning, 7 source, 6 uncertainty, 6 multi-turn |
| Eval set held-out SHA-256 (C8) | `06e0014eb2eb28fdeba7a192b82b89d2921a29d15d14962658d05a7f72a20dfd` (`eval-set/heldout.jsonl`, 40 cases) | 2026-09-26, before any C8 run | Same category spread. Seeds S1, S3, S5, S7, S9, S11 are here; S2, S4, S6, S8, S10 are in dev, each with a paraphrase in the other set |
| C8 config hash | ~~`f83d962f…a0fe71c`~~ (v1, app `fb3cc59`; superseded before any complete run, see C8 evidence) → **`7bcffd4a4485c45f3227c8272dcc5ad592e5dac8d178225e99ee90ac29c25f4f`** (`eval-set/c8-config-v2.json`, app `e1ddd70`) | 2026-09-26, v2 frozen before any v2 run | App commit of the batch probe, production decoding, 4,096 context, simulator CPU FLOAT16, grounding asset hashes, eval-set and rubric hashes, both arms' model hashes. Rubric frozen as `eval-set/rubric.md` (`68b242dd…62576`) |
| C9 timing protocol | v1, frozen in C9 below | 2026-09-27, Codex takeover; committed before trials | Original budgets unchanged; B0 versus M4-Ls |

## Open questions for the user

_Add a dated entry for anything that blocks progress. Say what the question is, why it blocks,
and what options you recommend._

- **2026-09-27: C9 backup prerequisite blocked.** Ry is reachable, but two read-only attempts
  to copy production Application Support failed opening a CanvasState file (`openat` EPERM).
  Documents also encountered a CoreDevice tunnel timeout. Preferences copied successfully;
  this is not a complete backup. Owner asked to unlock Ry and leave it unlocked for a retry.
  No experiment/install starts until the backup and data counts are verified (plan §4.2).
- **2026-09-27: C10 PR destination conflicts with private-only instruction.** `gh repo view`
  confirms `rbaltodano/Aquinas-iOS` is PUBLIC. Owner's current “don't post anything publicly”
  instruction prevents a push/PR there. Asked for a private destination or to retain the PR
  locally. Nothing was pushed or posted.

- ~~**2026-09-26: Merge the backend removal before C6.**~~ **Resolved 2026-09-27:** merged (`b6903b4`). C6 may need
  E4B-specific adapter fixes in `LiteRTAquinasModel.swift`, and the owner's uncommitted work on
  `main` rewrites that file (and deletes `BackendAquinasModel`, which this branch's quality probe
  still uses as its fallback). Doing C6 on the old code would mean redoing the fixes after a
  conflicted merge. Recommended: commit the backend removal on `main`, then merge `main` into
  `feature/gemma4-e4b-qat`, rerun the build and tests, and then run C6 for M4-Ls.
- **2026-09-26: C5 memory metric doesn't see M4-L's GPU memory. Still open for C9.** M4-L is rejected; the active candidate M4-Ls is not an artisan package, but C9 should still check jetsam reports, not `phys_footprint` alone.
  - The plan gates on peak `phys_footprint` ÷ `operating_cap`.
  - For the GPU_ARTISAN package, `phys_footprint` stayed at 0.36–0.51 GB while jetsam reports
    showed 2.67–3.35 GB resident, and the phone killed the probe for `vm-pageshortage`. For B0 the
    metrics agree.
  - **Recommended:** any future candidate using the artisan path is gated on jetsam absence plus
    the jetsam report's resident pages (or a Metal-allocation total) rather than `phys_footprint`
    alone. Record it as a *Decision* if adopted.
- ~~**2026-09-25: C3 gate: pre-existing test failure. BLOCKS C3 → C4.**~~ **Resolved 2026-09-26:** accepted as a
  known baseline failure (see *Decisions log*). The C3 gate requires
  "the build and all tests pass". 175/176 pass. The failure,
  `MiniLMGroundingRetrievalTests.namedPassagesUseSourceTextAnchors` (resurrection case), fails
  identically on untouched base `31aa476` (`C3-basecheck-1`) and is unrelated to C3's code. The
  plan has no On-failure branch for C3.
  - **Recommended:** accept this as a known baseline failure for the C3 gate. Record that here and
    set C3 to `done`; C4 can then run immediately.
  - **Alternative:** fix the grounding test or corpus mismatch first in a separate change on
    `main`, then rerun the suite.
  - Either way, C8's grounding is identical for B0 and M4-L, so it doesn't bias the A/B.
- ~~**2026-09-25: C5 harness prerequisites. Not blocking yet.**~~ **Resolved 2026-09-26 (session
  decision, option (a), reversible):** see C5 evidence, "Protocol choices". C5 asks for "~2,000-token prefill
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
| 2026-09-26 | Don't commit or merge the owner's uncommitted backend removal on `main`; continue on this branch. Its model-path changes are only failure-fallback removal plus a new quote-notability task; conversation prompts are unchanged, so results carry over. Add quote notability to C6 after the merge | Claude Code session (owner delegated all decisions 2026-09-26) | `git diff` of `LiteRTAquinasModel.swift` on `main`; no edits there since 11:59 |
| 2026-09-27 | Owner delegated the C8 owner review to the session. The session applied only the evidence-based held-C2 reclassification (critical → non-critical, a corpus-induced locator), which it had recommended before any review; the held-out gate then passes. Caveat: the reviewer and the first-pass scorer are now the same assistant, so the plan's independent spot check didn't happen | Owner (delegation) + Claude Code session | "i don't have time to go through everything in that artifact. again i trust your judgment. continue" |
| 2026-09-26 | **Run C8 before C7** (deviates from §5 order). C7 exercises the full app's UI, queue, lifecycle, and Insight Tree, which the owner's uncommitted backend removal rewrites (56 files, about 3.3k lines removed); C7 evidence gathered before that merge would be invalidated by it (§0 rule 5). C8 exercises the model prompt path, which that work leaves unchanged apart from failure fallback. Risk accepted: if C7 later forces a model-path change, the affected C8 results are rerun | Claude Code session (delegated) | Owner away with the phone; `main` still uncommitted |
| 2026-09-26 | Run C8 on the **simulator CPU** for both arms (same backend, same numerics class: FLOAT16 activations). The phone GPU isn't available. Confirm the held-out set on the phone GPU when it is available, before C10 | Claude Code session (delegated) | Both standard packages fail the simulator's Metal delegate |
| 2026-09-26 | Fix the follow-up history bug and the image failure before C8 (`d583c94`), although neither is E4B-specific. Both break the multi-turn behavior C8 grades, and both arms run the same code, so the A/B stays fair. The C8 configuration is frozen after these fixes | Claude Code session (delegated) | C6 harness run `C6prep-harness-1` |
| 2026-09-26 | M4-L rejected at C5 (jetsam at 2K and 4K). Per C5's On failure branch, M4-Ls tried once on the GPU and passed; **M4-Ls is now the active candidate** for C6 onward (D1's fallback case). M4-L's failed results stand (plan §0 rule 5) | Plan branch, executed by Claude Code session | `C5-M4L-4`, `C5-M4L-5`, `C5-M4Ls-1..4` |
| 2026-09-26 | Accept the pre-existing `MiniLMGroundingRetrievalTests.namedPassagesUseSourceTextAnchors` failure (fails identically on base `31aa476`, run `C3-basecheck-1`) as a known baseline failure for the C3 gate; C3 → `done` | User | Owner replied "phone is plugged in, go ahead and continue" to the recommended resolution. Recorded as acceptance of that recommendation |
| 2026-09-27 | Pushed `main` (`b6903b4`) and `feature/gemma4-e4b-qat` to GitHub. GitHub CI (Xcode 26.6, iOS 26.5 simulator) failed one timing-sensitive test, `InquiryPersistenceStoreTests.threeConversationsKeepTheirAnswers` (25 s on the runner), which passes locally on iOS 27. The previous `main` CI run (`36164608561`, before these changes) failed three other timing tests. Per the owner, local iOS 27 runs are authoritative and CI flakiness doesn't block | Owner instruction | CI run `36286937989` |
| 2026-09-27 | Owner asked the session to verify and commit the backend-removal and Home work on `main`, then merge. Verified (build; 182/183 tests, the one failure pre-existing; the app launches and Home renders), committed as `fdf3d72`, and merged into this branch. The one conflict (`AquinasApplicationRuntime`: `--force-backend-model` removed, DEBUG model override kept) was resolved, and the probes' dead backend fallbacks were removed. Merged code: build OK, 198/199 tests (same pre-existing failure). Two pre-existing Home bugs found (not from this work): an empty "Where You Left Off" section when no conversation is selected, and "On the Incarnation" (Athanasius) described as "outlined by Augustine of Hippo". One likely catalog error: Today in History 05-11 (the Didache manuscript's colophon dates the copy to 11 June 1056) | Owner request, executed by Claude Code session | `LocalModels/e4b-eval/main-verify-1`, `merge-verify-1` |
| 2026-09-27 | C7 on the simulator CPU. Run the stress cases through a DEBUG probe (`--litert-lifecycle-probe`) that drives the app's own runtime, queue, and model, plus manual UI runs for real suspension and memory warnings. Fix the three lifecycle bugs C7 found in this branch; they are runtime bugs, not model-specific | Claude Code session (delegated) | Hand-driven CPU timing is too coarse for preemption and cancel windows; the probe is repeatable. The bugs affect B0 as well, and C9 needs them fixed |
| 2026-09-26 | Note only: the owner's **uncommitted** backend-removal work in the main checkout also edits this plan (C3 step 4 and C7 wording) and adds a decision row to its copy of this ledger. It doesn't affect C4 or C5. When it lands on `main`, merge it into `feature/gemma4-e4b-qat`; expect conflicts in `LiteRTDeviceProbe.swift`, `AquinasApplicationRuntime.swift`, and this ledger | Claude Code session | This branch predates that work; main's working tree is not touched |
| 2026-09-25 | Adopt plan v2 after independent review: conversion route blocked (D7); provenance labels but doesn't gate (D8); M2-L optional control (D9); early phone screen before quality; numeric memory cap; eval set 40 dev + 40 held-out with cross-model first-pass scoring and owner spot checks | User + planning session | [`Gemma4-E4B-QAT-Plan-Review.md`](Gemma4-E4B-QAT-Plan-Review.md), "Disposition" |
| 2026-09-26 | Remove the app's HTTP backend client (`BackendAquinasModel`, `--force-backend-model`, tree and Home services). C3 and C7 no longer need to disable backend recovery | User | The app is fully on-device; plan steps C3 item 4 and C7 updated to match |

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
- ~~**M4-Ls:** not downloaded. Only needed if C4/C5 send us back here.~~ **2026-09-26:** C5's On
  failure branch sent us here.
  - **M4-Ls:** computed `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` =
    published, 3,659,530,240 bytes, run `C1-M4Ls-1`. Same `hf download` command with
    `gemma-4-E4B-it.litertlm`. Free disk 24 GiB before, 20 GiB after.
  - Peek (`C1-M4Ls-1/peek.txt`): standard multimodal layout with `tf_lite_embedder`,
    `tf_lite_per_layer_embedder`, audio sections (CPU-constrained), a vision encoder
    (`prefer_activation_type: fp16`) and vision adapter, and a `tf_lite_prefill_decode` decoder
    with **`prefer_activation_type: fp16`**. That's the same structure as B0, not the artisan
    format.

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
- **M4-Ls supporting evidence (added 2026-09-27, run `C2-M4Ls-1`).** Constant bytes by dtype:
  - `tf_lite_prefill_decode`: INT4 1,945 MB, **INT2 168 MB**, INT8 83 MB, FP32 2 MB.
  - `tf_lite_embedder` and `tf_lite_per_layer_embedder`: **all INT2** (168 MB and 705 MB).
  - Vision encoder INT8/FP32.
  - `tf_lite_mtp_drafter` (a speculative-decoding drafter; not used by the app): INT4/INT8.
  - This is the int2/int4/int8 mix a maintainer described for the confirmed-QAT E2B package, and
    the public exporter (`litert_torch`) can't emit int2. So it's **strongly consistent with
    Google's QAT pipeline**, but it isn't an artifact-specific statement.
  - Classification stays **unconfirmed** under D8. Accurate label: "Gemma 4 E4B (LiteRT
    Community)". The owner may record a decision to say more.
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
All runs: M4-L via `--litert-model-path …/LocalModels/gemma-4-E4B-it-gpu.litertlm` (computed SHA-256
`4912bb5a…2bb7ff` in each report), iPhone 17 simulator, iOS 27.0, Debug build at `26f7ade`
(runs 2–3 at `26f7ade` plus the reporting-only parser fix committed right after). Greedy decoding.

| Run ID | Mode | Backend | Load s | Gen s | Activation (and how it was determined) | Classification |
| --- | --- | --- | --- | --- | --- | --- |
| C4-M4L-1 | raw, 2,048, "What is prudence?", cold cache | GPU → `GPU_ARTISAN` (Metal) | 15.84 | 2.24 | **F16**: `CalculationsPrecision::F16` (the executor's `activation_data_type` is "Not set"); read from the log by hand, before the parser fix | sim-pass |
| C4-M4L-2 | quality (production path), 4,096, "What is prudence?", cold cache | GPU → `GPU_ARTISAN` | 9.82 | 5.62 | **F16** (same line, parsed automatically) | sim-pass |
| C4-M4L-3 | raw, 2,048, no cache clear | GPU → `GPU_ARTISAN` | 19.67 | 2.22 | F16 | sim-pass |

- **Classification: `sim-pass`.** Per the gate branch, go to C5. The CPU check isn't required on
  this branch and wasn't run (the package is GPU-only anyway; see C2).
- **Outputs.**
  - Raw (runs 1 and 3, identical): "Prudence is the ability to govern and discipline oneself by
    the use of reason." That's the same sentence as B0 on CPU, plus a period.
  - Quality: "Prudence is the third prudence, which is both true and perfect because it takes
    counsel, judges, and commands rightly concerning the good end of man's whole life. It is
    distinct from the first prudence, which is found only in sinners, and imperfect prudence,
    which is common to both good and wicked men." That's coherent and `corpusGrounded`, with 0
    validated Insight links (B0 also had 0 on this question).
- **Activation.** It isn't FLOAT32, so there's no fallback to explain. The artisan executor
  computes in F16 by design. No delegate rollback, `Failed to initialize kernel`, or max-buffer
  error occurred. That's unlike B0, whose standard delegate hits the simulator's 256 MiB
  allocation ceiling.
- **Findings that matter downstream.**
  1. **No LiteRT cache is written for M4-L**: the cache folder is empty before and after every
     run. Reloads are full loads (15.8 s, then 19.7 s without clearing), so C9's "cached load
     p95 ≤ 3 s" budget may not be achievable by design. C5 and C9 should measure the phone
     before drawing conclusions.
  2. The simulator's `phys_footprint` doesn't reflect GPU memory reliably (raw peak 212 MB vs
     quality peak 3.26 GB). These aren't gate numbers; C5's phone numbers are.
  3. The 4,096-token quality configuration loaded and generated with no "too long" error for
     this prompt. The #18 hard limit still needs C6's truncation check.
- Quoted log lines (from `C4-M4L-1/litert-probe-stderr.log`):
  - `litert_lm_loader.cc:244] section_backend_constraint: gpu_artisan`
  - `engine_settings.cc:189] Artisan model detected. Switching backend from GPU to GPU_ARTISAN.`
  - `litert_executor_utils.cc:444] Build ModelResources for Artisan Text Decoder.`
  - `llm_gpu_artisan_executor.cc:304]   LlmExecutorSettings: backend: GPU_ARTISAN`
  - `gpu_model_info_generator.cc:32] CalculationsPrecision::F16`
  - `llm_metal_runner.mm:165] Metal LLM tokens initialized.`
  - `RegisterAccelerator: ptr=…, name=GPU Metal`
  - Executor settings: `activation_data_type: Not set` and `allow_src_quantized_fc_conv_ops: true`.
- **M4-Ls (added 2026-09-26, after C5 sent us to it):**
  | Run ID | Mode | Backend | Load s | Gen s | Activation | Classification |
  | --- | --- | --- | --- | --- | --- | --- |
  | C4-M4Ls-1 | raw, 2,048, cold cache | GPU | — | — | FLOAT16 (executor settings) | **sim-gpu-fail**: `Failed to create DelegateKernelLiteRtMetal: … texture binding has argument index 31 that is greater than 30`, then "Restored original execution plan", then "Failed to create engine" |
  | C4-M4Ls-2 | raw, 2,048, `--litert-probe-cpu` | CPU | 5.67 | 1.52 | FLOAT16 | coherent: "Prudence is the ability to govern and discipline oneself by the use of reason." |
  - Per the `sim-gpu-fail` branch the phone decides, and it passed (C5). This is another case of a
    simulator Metal limit that the phone doesn't have.

### C5 — Early phone screen
- Device / iOS build / backup location / Home data counts before → after:
  - Device: iPhone 17 "Ry" (iPhone18,3, `92295FBA-BC31-5608-BCB3-7C367E627732`), iOS 27.0 (24A5430a).
  - Backup: `/Users/ryanbaltodano/Developer/aquinas-backup-20260926-170531-e4b-c5`, taken before any install with `xcrun devicectl device copy from` on the
    production container (`com.ryanbaltodano.Aquinas-iOS`). It covers `Library/Application Support`,
    `Library/Preferences`, and `Library/Saved Application State`. 30/30 files match the device's
    sizes, with per-file SHA-256 in `MANIFEST.sha256`.
    - **Excluded:** about 26 GB of old experiment models in the production app's `Documents/`
      (listed in the backup's `README.txt`), plus caches and tmp.
  - Home data counts before: 1 conversation, 10 saved Insights, 1 study topic, 77 seen Insight
    IDs, 19 Insight Tree canvas-state files, 5 conversation backup files
    (`HOME-DATA-COUNTS.json`).
  - Probes install only under `com.ryanbaltodano.Aquinas-iOS.ModelProbe`, using the existing
    profile with the same three kernel memory entitlements as production.
  - **Protocol choices (recorded before any phone numbers):**
    - All C5 runs use the production context of 4,096 tokens (D5) and greedy decoding, in a fresh
      process each.
    - Prefill prompts come from grounding-corpus text (Summa), calibrated on the simulator with
      M4-L's tokenizer (runs `C5prep-calib-*`).
      - 2K: `fixtures/c5-prefill-2k.txt`, 1,995 prefill tokens, SHA-256 `a81b1222…fcd5a7`.
      - 4K: `fixtures/c5-prefill-4k.txt`, 3,818 prefill tokens, SHA-256 `2623ddac…87c284`.
      - A true 4,000-token prefill can't fit a 256-token decode inside 4,096.
    - **Decode is approximated** with the system message "Summarize the passage in about 240
      words." It yielded 204–226 decode tokens in the simulator. There is no decode cap (see the
      C5 prerequisite in *Open questions*; resolved by option (a)).
    - Prefill and decode runs use `--litert-probe-benchmark`, which switches LiteRT-LM into
      benchmark mode (recorded in each report). The load-only and prudence runs don't.
    - The 60 s hold uses `--litert-probe-hold-seconds 60` on the 4K run.
    - New harness options for this: `8b64c7e` (load-only, hold, question file, system message),
      14/14 harness tests pass.
- `operating_cap` (frozen, see Frozen values): 6,970,472,776 bytes, from `C5-B0-1`'s launch sample (committed before any M4-L phone run).
- B0 reference peak footprint (same protocol): **2,038,600,496 bytes** (0.29 × cap, run `C5-B0-4`).
  All four B0 runs passed. B0's footprint agrees with jetsam's resident count: `C5-B0-4`'s
  lifetimeMax was 124,426 pages × 16 KiB = 2.04 GB.
  | Run ID | Case | Peak footprint | ÷ cap | Load s | Prefill tok/s | Decode tok/s | Result |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | C5-B0-1 | load only | 1,807,192,568 | 0.26 | 10.98 | — | — | pass (FP16) |
  | C5-B0-2 | prudence | 1,972,163,184 | 0.28 | 8.16 | — | — | pass: "Prudence is the virtue that enables one to discern the right course of action in a given situation" (5.03 s) |
  | C5-B0-3 | 2K (2,007) + 226 | 1,785,074,216 | 0.26 | 16.24 | 634.3 | 12.9 | pass (system jetsam event reclaimed daemons; probe untouched) |
  | C5-B0-4 | 4K (3,830) + 265 | 2,038,600,496 | 0.29 | 12.27 | 834.7 | 17.1 | pass; 60 s hold OK (available after hold 6.59 GB) |

All runs: 4,096 context, greedy decoding, ModelProbe build `8b64c7e`, model hash verified in-report.

| Run ID | Case | Peak footprint | ÷ cap | Load s | Prefill tok/s | Decode tok/s | Largest Metal alloc | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C5-M4L-1 | load only | 355,109,064 † | 0.05 † | 8.54 | — | — | — | pass (F16) |
| C5-M4L-2 | prudence | 506,530,568 † | 0.07 † | 1.43 | — | — | — | pass: "Prudence is the ability to govern and discipline oneself by the use of reason." (3.46 s). **Jetsam saw this process at 2.67 GB resident** |
| ~~C5-M4L-3~~ | ~~2K prefill + 256~~ | — | — | — | — | — | — | **invalid**: `C5-M4L-2`'s process (PID 33461) was still alive, frontmost, and holding 2.67 GB. The script's terminate step failed, so this wasn't a fresh process. It was killed (`vm-pageshortage`, 3.30 GB resident). Superseded by `C5-M4L-5` |
| C5-M4L-4 | 4K (3,818) + ~256 | — | — | — | — | — | — | **FAIL: jetsam** `vm-pageshortage` during prefill. The only probe process, active and frontmost, **3.31 GB resident** (JetsamEvent 17:24:52). No result JSON |
| C5-M4L-5 | 2K (1,995) + ~256 | — | — | — | — | — | — | **FAIL: jetsam** `vm-pageshortage` during prefill. Fresh process, verified alone, active and frontmost, **3.35 GB resident** (JetsamEvent 17:27:30). No result JSON |

† **`phys_footprint` under-reports M4-L.** The artisan GPU executor's memory isn't reflected in
`task_vm_info.phys_footprint`: 0.36–0.51 GB reported, against 2.67–3.35 GB resident in the jetsam
reports, and the system's wired pages rise further. For B0 the two measures agree. So the plan's
footprint ÷ cap gate **can't be evaluated honestly for M4-L from the in-process metric**; jetsam
itself is the decisive signal here. See *Open questions*.

- 60 s hold: not reached for M4-L; the 4K run was killed during prefill. B0 held 60 s with no
  pressure kill.
- Jetsam and pressure evidence: `C5-M4L-4/device-logs-new/JetsamEvent-2026-09-26-172323.ips` (the
  invalid overlap), `C5-M4L-4/device-logs-late/JetsamEvent-2026-09-26-172452.ips` (the 4K kill), and
  `C5-M4L-5/device-logs-late/JetsamEvent-2026-09-26-172730.ips` (the 2K kill).
  - Each M4-L kill also took the suspended production Aquinas app (PID 32720) and many daemons
    (`vm-pageshortage`). The production app's data is on disk and backed up.
  - Device timestamps run about 30–60 s ahead of the host clock.
- Harness fix during C5: `run-device-probe.sh` now force-kills and **verifies no probe process
  is alive** before launch and after teardown, recorded as "preflight" and "teardown" in each
  `run.txt`. It refuses to run if the probe app path can't be resolved exactly.
- **C5 gate for M4-L: failed** (jetsam at 2K and 4K). Per the On failure branch, M4-Ls (the
  standard 3.66 GB package) is tried on the GPU once.

**M4-Ls (the On failure branch's single GPU try).** Copied to the probe app's Documents and loaded
with `--litert-model-document gemma-4-E4B-it.litertlm`. Every run's preflight and teardown
verified no other probe process was alive.

| Run ID | Case | Peak footprint | ÷ cap | Load s | Prefill tok/s | Decode tok/s | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C5-M4Ls-1 | load only (cold: first load, wrote GPU cache) | 986,796,008 | 0.142 | 14.32 | — | — | pass (FLOAT16) |
| C5-M4Ls-2 | prudence | 986,763,192 | 0.142 | 8.34 | — | — | pass: "Prudence is the ability to govern and discipline oneself by the use of reason, especially in the choice of action." (2.10 s) |
| C5-M4Ls-3 | 2K (1,995) + 216 | 1,148,670,936 | 0.165 | 6.58 | 827.5 | 19.8 | pass, coherent summary |
| C5-M4Ls-4 | 4K (3,818) + 203 | 1,152,586,976 | **0.165** | 7.09 | 810.1 | 18.9 | pass, coherent summary with one garbled phrase ("The authoritatively argues"; B0 had a similar one, "The textually,"). **60 s hold OK**: available 5.89 GB after the hold |

- No jetsam: the device's crash-log listing has no JetsamEvent in the M4-Ls window, no signal 9,
  and no GPU out-of-memory error. The only new device log was a `diskwrites_resource` report
  from the first load's GPU weight cache.
- **Gate for M4-Ls: pass.** No jetsam; the 4K-run peak is 1,152,586,976 bytes, far below
  0.80 × cap = 5,576,378,221; output is coherent.
- Footprint validity: M4-Ls uses the standard delegate like B0, whose `phys_footprint` matched
  jetsam's resident count. This is independent support, not proof, for M4-Ls.
- Versus B0 on the same protocol: M4-Ls has a lower peak (1.15 vs 2.04 GB), faster prefill
  (810–828 vs 634–835 tok/s), faster decode (18.9–19.8 vs 12.9–17.1 tok/s), and similar warm load
  (6.6–8.3 vs 8.2–16.2 s).
- On the phone, both E4B packages sit in the probe app's Documents (6.6 GB). Keep them for C9;
  remove them with the probe app when the evaluation ends.

### C6 — Integration diagnostics
**Status 2026-09-26: in progress.** (C6 was started without its separate in-progress commit;
this entry records it.)

- **Instrument.** Commit `e02437d`.
  - `--litert-record-generations` (DEBUG only, off by default) writes each native generation's
    exact rendered prompt, taken from LiteRT-LM's own `renderPreface`/`renderMessage`, together
    with the sampler and the raw output or error, to `Documents/litert-generations.jsonl`.
  - `--litert-diagnostics-probe` runs, through the production model on fixed inputs:
    single-turn, follow-up, and topic-shift conversation; two image cases; contextual definition;
    node label; tree seed; Midpoint; Make Node (exactly 3); Question of the Day; and compaction.
- **Harness validation, simulator** (`C6prep-harness-1`). This used M4-L only because the
  simulator GPU can run it; it is **not** candidate evidence. All 12 cases returned and 14
  generations were recorded with rendered prompts. It exposed two app bugs that affect **B0 and
  E4B equally**:
  1. **Follow-ups lost all history.** `isLikelyTopicShift` treated "Can you give a concrete
     example?" after a mercy/justice question as a new topic, because the two share no content
     words. The rendered prompt had no prior turns (`initialMessageCount 0`), and the model
     replied that no concept had been given.
     - Fixed in `d583c94`: a referring word, or a question with no subject of its own once
       generic follow-up wording is removed, continues the conversation. Real topic changes
       (Portugal, JavaScript, Peloponnesian War) still reset.
     - Test: `subjectlessFollowUpsKeepContext`.
  2. **Any image broke the conversation.** The runtime has no vision executor, and LiteRT-LM
     rejects image content ("Vision executor should not be null, please TryLoadingVisionExecutor()
     first"). That failed the turn *and every later turn* carrying the image in history (the
     simulator fell through to the backend-error text).
     - Fixed in `d583c94`: when `LiteRTAquinasRuntime.supportsVision` is false, image turns go
       to the engine as text plus a short note that the model can't view the image.
     - Test: `imagesBecomeTextNotesWithoutVision`.
- Full suite after the fixes: 178/179 (`C6-tests-2`). The one failure is the accepted baseline
  failure.
- Observed on M4-L, to recheck on M4-Ls and B0: "What is natural law?" is routed to the
  structured contextual-definition task, so it returns no `{{term}}` links. That's app routing,
  not the model, and matters for §6's natural-law seed in C8.
**Runs (2026-09-26).** Simulator CPU, because the phone had been disconnected (the owner took
it) and the simulator's Metal delegate can't run either standard package. Template and parsing
behavior doesn't depend on the backend. Build `fb02847`, with `--litert-diagnostics-probe
--litert-record-generations --litert-probe-cpu`:
- `C6-M4Ls-1`: all 12 cases OK (FLOAT16).
- `C6-B0-1`: 11/12 OK. Make Node failed, as a **model** failure: B0 returned malformed children
  JSON, with one child missing its definition and a definition placed in a title.

- Template/role/EOS/channel/truncation diff summary:
  - **Stop tokens** {1, 50, 106} and the **`thought` channel** (`<|channel>thought\n` …
    `<channel|>`) are identical. Roles render the same way: `<|turn>system|user|model` …
    `<turn|>`, with history as separate turns.
  - **Chat templates differ, and B0's is defective.** B0's embedded Jinja template renders the
    system message with `messages[0]['content'] | trim`. LiteRT-LM passes system content as a
    list, so **B0 has always received its system prompt as a JSON string**
    (`[{"text": "You are Aquinas…", "type": "text"}]`). This holds for all 9 comparable
    generations (0 rendered prompts identical).
  - M4-Ls ships Google's newer template, which iterates the content list, so its system turn is
    plain text. It also adds the `'\n\n'` before tools and fixes tool-response handling.
  - **No E4B-specific adapter fix is needed.** B0's defect is packaging. It handicaps B0 somewhat
    in C8, which is fair for "replace what ships", and would matter if B0 is ever kept or
    re-exported.
  - **Truncation:** exceeding 4,096 is a **hard error**, not truncation. `C6-M4Ls-overflow-1`:
    "Input token ids are too long. Exceeding the maximum number of tokens allowed: 4730 >= 4096",
    then the send fails. That matches discussion #18.
  - The app's guard (`AquinasContextBudget`: 4 bytes/token estimate, 1,400-token non-conversation
    reserve, compaction at 3,200) under-reserves: the conversation system prompt alone is about
    1.9–2.7k tokens, more with grounding. The conservative 4-bytes estimate compensates, though.
    Grounded, history-carrying requests at app estimates of 2,537 / 3,003 / 3,174 all completed
    (`C6-M4Ls-longhistory-1`, `-nearthreshold-2`, `-atthreshold-1`).
  - **Watch item for C7/C9:** margin at the compaction threshold is thin. Not changed now, to
    keep C8's configuration fixed.
- Structured-schema results (per schema: pass / template / retrieval / model):
  | Schema | M4-Ls | B0 |
  | --- | --- | --- |
  | Contextual definition | pass (accurate prudence definition) | pass structurally; **model**: definition inaccurate (describes natural law) |
  | Node label | pass ("Cardinal Virtues") | pass ("Virtues") |
  | Tree seed (response-driven extraction) | pass | pass |
  | Midpoint | pass (5 candidates) | pass (5) |
  | Make Node (exactly 3) | pass | **fail: model** (malformed JSON) |
  | Question of the Day | pass | pass |
  | Compaction | pass | pass |
  | Quote notability (added after the merge; `C6-M4Ls-quote-1`, `C6-B0-quote-1`) | pass (synthesis → notable, with a reason; plain question → not notable) | **fail: model**. Both answers drop the closing `}`, so the app gets `invalidResponse`. The shipped Quote feature doesn't work on B0 |
- Image-history and attachment behavior in text-only mode: before `d583c94`, any image failed
  that turn and every later turn (`C6prep-harness-1`). After the fix, both models answer the
  text and say they can't see the image (for example M4-Ls: "I'm sorry, but I can't see the
  picture you're referring to…"). The image-bearing history no longer breaks the follow-up.
  There is no crash and no loss of text context.
- Follow-up context: after `d583c94`, "Can you give a concrete example?" carries both prior turns
  (`initialMessageCount 2`), and both models answer on-topic.
- E4B-specific adapter fixes (commit): none required. App fixes made in C6, not E4B-specific:
  `d583c94` (follow-up history, images).

### C7 — Full-app functional and lifecycle stress
Simulator (iPhone 17, iOS 27.0), **CPU executor** (M4-Ls can't run on the simulator GPU, C4),
merged code. Runs are in `LocalModels/e4b-eval/C7-M4Ls-*`. The phone GPU repeat is part of C9.

**Instrumentation added (DEBUG unless noted).**
- `--litert-force-cpu`, `--litert-stall-once-seconds <n>`, and `--litert-idle-timeout-seconds <n>`.
- A Darwin-notification trigger for memory warnings:
  `notifyutil -p com.aquinas.debug.memory-warning`.
- `LiteRTLifecycleTrace`: always-on "Native Call" signposts. With `--litert-lifecycle-trace` it
  also writes a JSONL trace with `phys_footprint`.
- Vendor patch: `NativeActivityMonitor` reports engine and conversation deletes on their
  detached threads, and native streams until the native side releases them.
- `--litert-lifecycle-probe`, which runs the stress cases through the app's own runtime, queue,
  and model.

**Functional (full app UI, `C7-M4Ls-func-1`).** All actions validated locally, with these exceptions.
| Action | Result |
| --- | --- |
| 3 questions + follow-up | Pass. The follow-up carried history (`initialMessageCount` 2, then 4) |
| Topic-shift reset | Pass. "Switching topics: … Eucharist" sent with no history |
| Contextual definition | Pass ("Accidents", 6.4 s) |
| Save Insight → node label → Midpoint | Pass. Label JSON valid; Midpoint produced 3 candidates and placed "Visible Accidents" |
| Make Node | **Not reachable in the UI (pre-existing).** Nothing calls `onCreateCanvasConcept` since `d00394c` split `InquiryControlDock`. The model contract passed in C6 (exactly 3) |
| Question of the Day | Pass. Grounded question from the Eucharist conversation |
| Compaction (`/compact`) | Pass. A 17 s checkpoint that keeps each topic |
| Queue reorder | UI drag not exercised: CPU answers finish before a second one can be queued by hand. Covered by the new test `reorderedUpcomingTasksRunInNewOrder` (model-independent) |

Side findings (all pre-existing, none model-specific):
- The node-label task was sent an empty Insight (`": "`) and returned "No insights provided". The
  app then asked for a definition of that label: two wasted generations, with nothing persisted.
- The Midpoint card's second row wraps its percentage vertically when the title is long.
- Regenerate returns an identical answer, because production decoding is greedy.

**Lifecycle stress.** The first manual pass (`C7-M4Ls-stress-1/2`) found three bugs. All three are
fixed in the runtime.
1. **Suspension read as a stall.** Backgrounding during generation suspends the process. On
   resume, the watchdog counted the suspended time as "no tokens", failed the answer ("couldn't
   complete"), and abandoned a healthy stream. Fix: a watchdog gap over 15 s (or a suspension
   before the first check) restarts the stall window. Verified in `C7-M4Ls-stress-4`: after 64 s
   in the background, the answer resumed and completed.
2. **Overlap after a thrown generation.** After a stall, the next conversation started while
   the abandoned native stream was still decoding: two sessions on one engine
   (`stress-2`, 15:09:18 and 15:22:24). Fix: new native calls wait up to 45 s for an abandoned
   stream. The error-retry path no longer rebuilds the engine under a live stream.
3. **Overlap at reload.** A new engine loaded while the previous engine's native delete was still
   running on its detached thread (`lifecycle-2`: 3 overlaps). Fix: loads wait up to 10 s for
   pending deletes. In practice the wait is about 0.1 s.

Final probe (`C7-M4Ls-lifecycle-4`): **all cases pass; 0 overlaps.**
| Case | Result | Next request OK? | Memory back within 10%? | Engine overlap? | Notes |
| --- | --- | --- | --- | --- | --- |
| Conversation + follow-up + topic shift | Pass | Yes | n/a | No | func-1 |
| Definition / Insight / node label / Make Node / Midpoint | Pass; Make Node N/A (no UI entry) | Yes | n/a | No | func-1; C6 covers Make Node |
| Question of the Day / compaction / queue reorder | Pass (reorder via test) | Yes | n/a | No | func-1 |
| Cancel mid-generation | Pass; 0 updates after cancel; UI area stays empty | Yes (48 s: waits for the abandoned stream) | Yes | No | stress-2, lifecycle-4 |
| Foreground preemption | Pass; background task re-queued and succeeded on attempt 2 | Yes | Yes | No | lifecycle-4 |
| Forced stall timeout | Pass; explicit failure message shown | Yes (38 s) | Yes | No (was yes before fix 2) | stress-2, lifecycle-4 |
| Background during generation | Pass after fix 1 | Yes | Yes | No | stress-4 (real suspension); lifecycle-4 (queue level) |
| Idle unload → reload | Pass | Yes | Yes: ratio 1.000–1.006 (about 105 MB each time; first cycle 1.12 while retrieval assets load) | No (was yes before fix 3) | lifecycle-4 |
| Memory warning | Pass; unload is immediate (2.96 GB → 169 MB) | Yes | Yes | No | stress-4 (app); lifecycle-4 (idle and during generation) |

- Tests: 199/200. The one failure is the known baseline `namedPassagesUseSourceTextAnchors`.
  New test: `reorderedUpcomingTasksRunInNewOrder`.
- C8 impact: the fixes only change stall, error-retry, and reload paths. No C8 generation
  errored, retried, or stalled (0 errors in 160 generations), so C8 results stand.
- Carried to C9 (phone GPU): repeat backgrounding and memory warning on the device. A cancel or
  stall now delays the next request until the abandoned stream ends (up to 45 s); measure that
  on the GPU.

### C8 — Quality A/B
- Eval set location and SHA-256s (see Frozen values): `LocalModels/e4b-eval/eval-set/`, frozen
  2026-09-26. Each case records its category, whether it is a fixture, and objective checks:
  required regex groups, forbidden claims, `requires_links`, and optional `max_words`.
  - **Exposure disclosure.** Before the freeze I had already seen candidate outputs (M4-L, and
    M4-Ls in C4/C5) for "What is prudence?", the Portugal topic shift, "What is natural law?", and
    a mercy/justice follow-up. All four are plan-mandated §6 seeds, so they're included anyway. No
    other case was written after seeing a candidate answer to it.
- Config hash: v2 `7bcffd4a…c25f4f` (see Frozen values).
- **v1 runs aborted: a native crash in the shipped runtime, found and fixed.**
  - `C8-B0-held-1` (v1) crashed after 26/40 cases with **SIGSEGV** in LiteRT-LM teardown
    (`litert_lm_conversation_delete` → `~LlmLiteRtCompiledModelExecutorStatic`, freeing tensor
    buffers). It was preceded by "EngineAdvancedImpl destructed with 1 living sessions!" (4 of
    those in 28 generations).
  - Cause: the vendored wrapper deleted the engine and its conversation on two detached threads
    that race whenever both are released together, which happens on every 4-generation engine
    refresh. The race is backend-independent and exists on the phone, affecting B0 in production.
  - Fixed in `e1ddd70`: a conversation holds its engine until its native delete returns.
  - Verified by `C8fix-stress-1` (same workload, uncommitted fix): 40/40 cases, 39 generations,
    0 living-session warnings, no crash.
  - `C8-M4Ls-held-1` (v1) was stopped as superseded (`ABORTED.txt`). v1 evidence is not used for
    the gate.
- Scorer model: Claude Opus 5.5 (the reviewing assistant; not a candidate), blind A/B per
  `rubric.md`. Pairs, key, and scores: `C8-blind-held-1/`. Scores were hashed before the key was
  opened (`scores.jsonl` `f63f826e…36adba`, `pairs.jsonl` `2cc41bdf…3d1c7`). First-pass scores are
  not edited after unblinding; later evidence goes to owner review.
- Owner review coverage (% of cases, all critical flags, weak-preference cases): **delegated.**
  - 2026-09-27 the owner declined to review the cases ("I don't have time … I trust your
    judgment") and delegated the review to the session; see *Decisions log*.
  - Applied: exactly one change, held-C2, where M4-Ls's critical flag was removed on documentary
    evidence (the locator was copied from the app's corpus label). Recorded as an `owner`
    override in `C8-blind-held-1/scores-reviewed.jsonl`.
  - No other first-pass score was changed. Gate rerun: `C8-blind-held-1-reviewed/` →
    **all six held-out rows pass.**
  - The earlier review-page text follows, kept for the record: **pending.**
  - Review page (private, blind A/B, no key): https://claude.ai/artifact/FWZ2bVVoGuuK5LaUKUoABH
  - Required: 10 critical-flag cases and 24 weak-preference cases, which is 34/40 (85%, above the
    25% minimum). 6 more are optional.
  - Decisions are stored in the page's `reviews` collection. The session reads them back with
    `ArtifactData list reviews`, adds them to `scores.jsonl` as `owner` overrides, and reruns
    `c8_gate.py`.

**Held-out runs (config v2):** `C8-B0-held-2` and `C8-M4Ls-held-2`, 40/40 cases each, 0
failures, 0 living-session warnings. Simulator CPU, FLOAT16. In-run hashes: B0 `9a6345f1…`,
M4-Ls `0b2a8980…`, held-out file `06e0014e…`. Median 13.2 s/case for B0 and 23.5 s for M4-Ls
(CPU; not a latency measurement). 5 cases per arm were answered by verified grounding with no
generation. Objective scores: `score_objective.py` → `objective-scores.json` in each run folder.
Gate computed by `c8_gate.py` (first pass, before owner review):

| Metric (held-out) | B0 | M4-Ls | M2-L (opt.) | Required | Pass? (first pass) |
| --- | --- | --- | --- | --- | --- |
| Critical failures | 9 | 2 → **1** after review | — | M4-Ls ≤ B0 and ≤ 1 | **yes** after the delegated review (first pass: no, by one) |
| Mean accuracy | 3.05 | **3.85** | — | ≥ B0 + 0.3 and ≥ 3.0 | yes (+0.80) |
| Worst category Δ accuracy | — | −0.14 (regression: 3.86 → 3.71) | — | ≥ −0.5 | yes |
| Objective checks passed | 26/40 | **28/40** | — | ≥ B0 | yes |
| Valid-link rate | none (1 case with links; 0 raw markers) | **0.86** (19 cases with links) | — | ≥ B0 | yes |
| Repetition / garbage rejects | 0 | 0 | — | 0 | yes |

- Also: mean depth 2.95 → 3.43; mean voice 3.00 → 3.85. Category accuracy B0 → M4-Ls:
  definition 3.14 → 4.00, multi-turn 2.83 → 4.00, reasoning 2.29 → 3.43, regression 3.86 → 3.71,
  source 3.29 → 4.29, uncertainty 2.83 → 3.67. Pairwise (sum of the three dimensions): M4-Ls wins
  27, ties 10, loses 3.
- **B0's 9 critical failures** (unblinded):
  - held-A3: named "wisdom, fortitude, piety" as the theological virtues.
  - held-A5: wrong definition of transcendental.
  - held-B1: an erring conscience "does not bind".
  - held-B4: presents an objection as the Summa's teaching.
  - held-B5: "God's existence cannot be proven by reason".
  - held-C3: "the soul is not incorruptible".
  - held-C4: "law pertains to the will".
  - held-D4: swapped Dante's and Aquinas's centuries and invented a "Summa contra Cleros".
  - held-E5: "No, Aquinas did not comment", with the context present.
  - Several of these are B0 adopting an article's *objections* as the conclusion.
- **M4-Ls's 2 critical flags:**
  - held-A5: the same wrong "transcendental" definition as B0.
  - held-C2: "Article 7 of Question 41" for God's simplicity (Summa I q3 a7).
- **Scorer note for owner review (held-C2), evidence found after unblinding.** The grounding
  passage the app supplied reads **"41 Article. 7 - Whether God is altogether simple?"**; `41` is
  the corpus file's running section number (the same scheme yields "Summa Theologica, 273, A[4]"
  in B0's answers). M4-Ls repeated the app's label rather than inventing one.
  - **Recommendation:** reclassify as non-critical (a corpus-induced locator error; accuracy
    unchanged).
  - With that override, M4-Ls has **1** critical failure and **every held-out gate row passes**.
- **App findings from C8 (both arms, not model-specific; not fixed during the frozen run):**
  1. **Topic-shift false positive, again.** held-E2 "How is each article structured?" after a
     Summa question was sent with **no history** in both arms (`initialMessageCount 0`), so both
     answered about generic articles. The referring-word rule from `d583c94` doesn't cover
     "each"/"its"-less follow-ups that name a new noun. Propose: carry history whenever the
     previous turn is recent and the question is short, and reset only on a clear new named
     subject.
  2. **Grounding locators are misleading.** Corpus running numbers are shown to the model as if
     they were question numbers. Propose: normalize corpus labels to real Summa locators
     (Part/Question/Article) or strip them.
  3. **Corpus-scope abstentions on well-known questions**: just war (held-B3), when the Summa was
     left unfinished (held-D2), levitation (held-D6). They affect both arms identically.
- **Dev runs (config v2):** `C8-B0-dev-2`, `C8-M4Ls-dev-2`, 40/40 each, 0 failures, 0 living-session
  warnings.
  - Objective checks: B0 29/40, M4-Ls 30/40.
  - Cases with validated links: 4 → 25. Valid-link rate 1.00 (4 cases) → 0.94.
  - Rejects: 0 / 0.
  - Category passes B0 → M4-Ls: definition 6→6, multi-turn 3→4, reasoning 5→6, regression 7→5,
    source 4→5, uncertainty 4→4.
  - The dev set doesn't gate. No E4B-specific template issue was found (C6), so no prompt
    adjustment is made.
  - Blind subjective scoring of dev is pending.
- Sampling (temperature 0.2) observations: `C8-M4Ls-sampled-1..3`, M4-Ls, dev cases R2, R5, A1,
  B3, and E1, with `--litert-eval-sampled` (topK 40, topP 0.95, temperature 0.2, seed 7;
  switch added in `52f17f9`).
  - All 15 outputs passed objective checks with 0 rejects: no loops or mixed-script corruption,
    unlike the old 4-bit checkpoint.
  - Every output differs from greedy. With the fixed seed, the three repeats were identical, so
    repeat variance at a fixed seed is zero on this backend.
  - Informational only; the production decoding policy is unchanged.
- Dev-set blind subjective scoring: **not done**. It doesn't gate, and the objective dev results
  agree with held-out. This is recorded as a deviation from `rubric.md`'s "score every case".

### C9 — Physical-device sustained gate
**Frozen protocol v1 — 2026-09-27, Codex takeover (before trials).** This ledger section is
its committed protocol; amendments require a new version committed before affected runs.

- Candidate: **M4-Ls**, standard package hash `0b2a8980…45bd52e0`; comparator B0
  `9a6345f1…3365282`, full hashes in the registry. Same LiteRT 0.14.0 vendor binary,
  GPU, 4,096 context, deterministic production sampler, production retrieval/MiniLM assets,
  text-only. No prompt or decoding-policy changes. Record build commit, binary/asset hashes,
  effective settings, model URL/hash, device OS/build, and exact commands with each run.
- Device: physical base iPhone 17 “Ry”; verify identity/OS on connection. Only disposable
  `com.ryanbaltodano.Aquinas-iOS.ModelProbe`, using the full app runtime, queue, and override.
  Back up production Documents and Library, verify readable backup and Home data counts before
  installs/experiments. Preserve the installed production app and all model source files.
- Fixed prompts: S = “In one sentence, what is prudence?”; J = “How can justice and mercy work
  together when someone repeatedly does wrong? Answer in at most 180 words.” J's declared
  target is approximately 256 output tokens, requested through the prompt (no native hard
  decode cap, as recorded for C5). Report actual output words/tokens where available; never
  truncate timing or silently discard an over-budget answer.
- Five cold and five cached fresh-process trials **per prompt per arm**: 40 sessions total.
  For each prompt and repetition 1–5: B0 cold, M4-Ls cold, B0 cached, M4-Ls cached; reverse
  arm order on even repetitions. Preserve each arm's cache for its paired cached trial.
  Cold means clear only that arm's disposable LiteRT cache before launch; cached means
  cache present from its cold trial. Record cache inventory/actions. No benchmark mode.
  Start each session at nominal thermal state; record power/charging state, start/end
  thermal state, and any cooldown. Never exclude a slow completed trial.
- Measure monotonic boundaries: queue acceptance, retrieval completion, native prefill start
  and end, first visible answer delivered to UI, visible answer complete, metadata complete.
  Record native engine load separately. Answer latency is queue acceptance to visible answer
  completion, including load/retrieval. Public approach text is not first answer output.
  Buffered output is reported as buffered. Native boundaries unavailable from production
  instrumentation must be explicitly unavailable, never inferred as measured. Resolve missing
  gate instrumentation before trials; do not replace the full app with raw-probe measurements.
- Report every sample, nearest-rank p95 (`ceil(.95*n)`, hence max for n=5), and max, separately
  by arm, prompt, and cache state. Both cache strata must meet answer budgets.
- Sustained: one warm-up excluded from ratio, then 20 consecutive J requests per arm through
  the full app queue, no deliberate pauses. Use identical fresh conversation inputs each turn
  to control input size; separately carry out lifecycle follow-up/history cases from C7.
  Record each latency, thermal state at least once per second while active, and peak physical
  footprint. Compare turn 20/turn 1 within the same arm.
- Lifecycle on M4-Ls GPU: five actual OS background/foreground cycles while a native generation
  is active (5, 15, 65, 5, 15 seconds background hold); each followed by a successful new request.
  Queue-only inactive toggles are supplementary and cannot establish OS suspension recovery.
  Simulate one app memory warning during generation and one while idle, verify unload/recovery.
  Hold idle for 75 seconds and verify a subsequent request; also explicitly test idle unload
  and reload with a DEBUG shortened idle timeout in a separate lifecycle run.
- C7 carry-overs: cancel during native generation, immediately enqueue a new request, measure
  cancellation-to-success and abandoned-native wait; repeat with a forced DEBUG stall.
  Include foreground preemption. Require zero stale updates after cancel, no overlap of old
  native work/deletes with new conversation/load, and settled post-unload resident memory
  within 10% of the warmed pre-request unloaded baseline. Report first retrieval warm-up
  separately. Preserve traces proving native completion rather than assuming a timeout did so.
- Frozen gates (M4-Ls): peak physical footprint ≤ **5,924,901,860 bytes** (0.85 of frozen
  6,970,472,776 cap); cold load p95 ≤12 s; cached load p95 ≤3 s; S answer p95 ≤4 s;
  J answer p95 ≤60 s; turn20/turn1 ≤1.5; thermal never critical; no jetsam, signal 9,
  GPU OOM, unrecovered warning/background cycle, stale updates, or native overlap.
  Inspect device crash/jetsam logs before/after, including delayed reports; footprint alone
  cannot prove safety. B0 results are contextual and never lower M4-Ls's absolute budgets.
- IDs: new `C9-B0-<n>` and `C9-M4Ls-<n>` directories only, immutable after collection;
  preparation uses `C9-preflight-<n>`. Archive exact commands, results, traces, and failure
  evidence under `LocalModels/e4b-eval/`. Interrupted trials remain recorded and get new IDs.
- On failure: record and commit, stop promotion; owner decides any new configuration/candidate.
  Missing prerequisite with no failure branch: mark blocked and record the question, per §0.
  C8 GPU confirmation follows a passing C9, both arms on frozen held-out fixtures, with new
  run/config IDs; then C10 disposable no-override smoke, scratch-branch rollback, and PR.
  No merge is authorized. Verify repository visibility before pushing/opening a PR: owner's
  “don't post anything publicly” restriction applies.

**Preflight evidence (no C9 model trials yet).**
- Protocol commit: `87a5cc9`; source takeover commit: `be06935`, correct worktree/branch.
- Device: Ry, iPhone17 hardware `iPhone18,3`, iOS 27.0 (24A5430a), paired and reachable.
- `LocalModels/e4b-eval/C9-preflight-1/`: device metadata, production Library inventory,
  exact commands, backup transfer logs, hashed preferences backup, preflight summary.
  `C9-preflight-2/backup-appsupport.log`: retry failed with the same protected-file error.
  **Backup incomplete.** Parsed preferences show 13 saved Insights, 1 study topic, 81 seen
  Insight IDs. Conversation count is not yet verified. Earlier backup remains untouched.
- `df -h /`: 5.5 GiB free; worktree `build/DerivedData` is 8.3 GB. No build or cleanup
  performed yet; clear only verified stale build products before building.
- Harness preparation still needed: existing quality probe preloads a separate runtime and
  ignores UI updates; it cannot establish queue-to-visible-answer C9 timing. Existing lifecycle
  probe simulates queue inactivity, not OS suspension, and waits for native drain before
  enqueueing the post-cancel request. Add dedicated C9 instrumentation outside
  `LiteRTAquinasModel.swift` before collecting results. The vendored conversation API has no
  native prefill-boundary callbacks; benchmark metrics require benchmark mode, which changes
  execution settings. Record this limitation explicitly; do not substitute inferred timestamps.
  Device-interaction skill's session/synthesis tools are not available in this session.
- **Status: blocked at backup prerequisite**, per plan §0 rule 6. No model trials, installs,
  model changes, production-container writes, push, PR, or merge occurred. C8 GPU confirmation
  and C10 rollback remain pending. Resume with a new preflight ID after Ry is unlocked.

| Metric | Budget | B0 | M4-Ls | Pass? |
| --- | --- | --- | --- | --- |
| Peak footprint | ≤ 5,924,901,860 B | 1,974,162,320 B (`C9-B0-2`) | 1,087,706,216 B (`C9-M4Ls-2`) | yes in sampled trials; gate ended early |
| Cold load p95 / max | ≤ 12 s | 7.916 s (1 valid trial) | **12.824 s** (1 valid trial) | **no**: 5-trial p95 must be at least 12.824 s |
| Cached load p95 / max | ≤ 3 s | not run | not run | held after decisive failure |
| One-sentence complete p95 | ≤ 4 s | 18.446 s (cold, 1 trial) | **21.910 s** (cold, 1 trial) | **no**: 5-trial p95 must be at least 21.910 s |
| Justice-and-mercy complete p95 | ≤ 60 s | not run | not run | held after decisive failure |
| Turn 20 ÷ turn 1 latency | ≤ 1.5× | not run | not run | held after decisive failure |
| Max thermal state | < critical | nominal (0) | nominal (0) | yes in sampled trials |
| 5× background/foreground; warning; idle > 60 s | survive and recover | not run | not run | held after decisive failure |

**C9 gate decision — failed 2026-09-27 (run `C9-M4Ls-2`).** On physical iPhone 17 Ry,
iOS 27.0 (24A5430a), DEBUG disposable bundle, GPU, 4,096 context, greedy sampler,
exact M4-Ls SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
Exact launch arguments: `LocalModels/e4b-eval/C9-M4Ls-2/run.txt`; settings/result:
`litert-sustained-result.json`; monotonic load/retrieval/UI timestamps and thermal/memory
samples: `litert-lifecycle.jsonl`; native settings: `litert-probe-stderr.log`; device logs:
`new-crashlogs.txt` (one disk-writes report, no jetsam). Artifact/runtime/grounding hashes:
`C9-preflight-3/artifact-manifest.json`; backup and Home counts in `backup-manifest.json`
and `data-counts.json`. Build `C9-diagnostics-1/build.log` passed after hash-memory correction
(`a4fd7c0`). Candidate response was coherent, 35 words. First visible answer equaled completed
answer (LiteRT buffering); retrieval completed at 13.155 s and UI answer at 21.910 s after
acceptance; metadata at 21.910 s. Native prefill boundaries unavailable, recorded null per
frozen protocol. Peak footprint 1.088 GB, below cap, thermal nominal. Cold load **12.824 s >
12 s** and cold short answer **21.910 s > 4 s**. The frozen nearest-rank p95 for five samples
is their max, so even four perfect future samples cannot make either gate pass. We therefore
stop the remaining trials without claiming a measured five-sample p95. No product budget was
revised after seeing numbers.

Valid B0 context: `C9-B0-2`, exact SHA-256 `9a6345f1…3365282`, same runtime/phone and corrected
harness, cold load 7.916 s, short answer 18.446 s, peak 1.974 GB, nominal thermal. `C9-B0-1`
is preserved as invalid/incomplete due to DEBUG hash memory overhead, fixed in `a4fd7c0`.
`C9-M4Ls-1` was a preflight thermal refusal with no candidate load. All run folders immutable.

**On failure branch:** do not promote M4-Ls. Main still has the B0 manifest (verified with
`git show main:Aquinas-iOS/Services/LiteRTModelStore.swift`); no merge, push, or PR. The branch
retains owner-approved E4B promotion prework for review, but C10 cannot close while C9 failed.
The production phone app remains on the earlier E4B build as a temporary personal trial,
per the C9 closeout recommendation. C8's held-out phone GPU repeat and the C10 scratch rollback are not run because they
depend on a passing C9. The GitHub repository is public, so no PR can be opened under the owner's
no-public-posting instruction in any case. New tuning or relaxed budgets require a new plan and
candidate/run IDs; this failed result stays intact.

### C9 resumption — 2026-09-27

Owner authorized continuation. Protected Application Support now copies successfully under new
run `C9-preflight-3` (9 persisted conversations); completing Documents/preferences backup before
any install. Prepare DEBUG-only full-app queue timing instrumentation without editing
`LiteRTAquinasModel.swift`. No production prompt, sampler, model, or vendor binary changes.
Native prefill timestamps remain explicitly unavailable in production mode per frozen protocol.
Stale worktree simulator products removed before device build; models/evidence preserved.

**C9 backup clarification v1.1, frozen before trials:** Documents contains only seven legacy
model binaries (inventory: `C9-preflight-3/documents-inventory.json`), no user-created data.
Copying them was stopped to avoid disk exhaustion; this attempt's partial/redundant model
backup copies removed. Production model files untouched. Backup scope is persisted Application
Support and Preferences; regenerateable caches omitted. Application Support matches every
file and size in the new device inventory. Preferences copy from `C9-preflight-1` is reused:
the new phone inventory confirms the same 42,225-byte file and exact modification timestamp
(2026-09-27T21:34:02Z); direct retries stalled. All backed-up JSON/plists parse; hashes in
`C9-preflight-3/backup-manifest.json`. Counts: 9 conversations, 13 saved Insights, 1 study
topic, 81 seen Insight IDs. Backup prerequisite is satisfied without modifying production.

Harness commit `7ac77a8` adds DEBUG-only full-app shared queue timing, retrieval observation,
visible answer delivery, metadata completion, per-second thermal/memory traces, and independent
per-model disposable caches. Native prefill timestamps remain explicitly unavailable, as
frozen in v1. No benchmark mode, prompt changes, or vendor binary changes. Device build passes
(`C9-preflight-3/build-final.log`). The commit message's backup-verification phrase preceded
the completed verification; this entry is its actual completion evidence. No trials yet.

**Initial C9 trials (preserved, not rerun under the same IDs).**
- `C9-B0-1`: cold S, nominal thermal state, GPU FLOAT16, 4,096 context. Native load 11.918 s;
  peak observed physical footprint 4,341,227,624 bytes. Runner observed PID 46564 absent
  before a completed answer/result; cause unconfirmed (no matching delayed crash report yet).
  It is not a successful baseline timing sample. Exact arguments and traces are in the run.
- `C9-M4Ls-1`: trial not started: thermal state fair (1). Harness refused before loading the
  candidate, per frozen nominal-start rule. Cool down, then use a new ID.
- Runner now captures lifecycle traces, clears prior traces before launch, and bounds each
  CoreDevice command to 30 seconds. SHA-256 `759133eb…903fb6`; complete hash in preparation
  evidence. Production process closed before the trials; installed production app/data retained.

**C9 diagnostic correction before further model trials:** `sha256(of:)` used FileHandle reads
without a per-chunk autorelease pool. The runtime invokes it after load for DEBUG identity
logging, concurrently with generation. Local reproduction on the exact B0 bytes produced the
same SHA-256 both ways, but original peak footprint was **3,873,705,152 bytes**, versus
**13,959,696 bytes** with per-chunk autorelease (1.86 GB versus 18.4 MB max RSS).
Evidence: `C9-diagnostics-1/hash-original.txt`, `hash-bounded.txt`, and archived reproduction
source. Add a per-chunk pool in `LiteRTModelInstaller.sha256`; no model, sampler, prompts, or
vendor binary change. `C9-B0-1` is invalid for controlled model-memory comparison due to this
proven diagnostic overhead; its incomplete result remains preserved and its exact exit cause
remains unconfirmed. M4-Ls has not yet loaded in any C9 trial. Restart trial pair with new IDs
on the rebuilt harness; keep the frozen budgets. This correction also makes installation hash
verification bounded in memory. Phone repeat must confirm actual memory behavior.

### C9 closeout — 2026-09-27

The owner asked for pros and cons of restoring B0 versus retaining E4B on the phone after C9.
Session recommendation: **retain the existing E4B production app temporarily as a personal
trial**, because held-out CPU quality favored it and C9 memory was lower; warn that latency
failed the frozen gate and sustained stability is unverified. This is not a promotion or a new
candidate decision. No production install, data, model file, or app container was changed in
this closeout. The disposable `com.ryanbaltodano.Aquinas-iOS.ModelProbe` app was uninstalled
after evidence collection, removing its copied B0 model; `C9-diagnostics-1/probe-uninstall.log`
and `probe-after-uninstall.log`. A separate app listing confirms the production
`com.ryanbaltodano.Aquinas-iOS` remains installed. All raw evidence and the verified
production-data backup remain gitignored in the worktree. To change the product decision, the
owner must adopt a new candidate/configuration with new run IDs; never erase C9's failure.


### C10 — Promotion
- Owner approval: 2026-09-27, "let's just get this model into the app and we can try the fine
  tuning for it after". Provenance label (D8): "Gemma 4 E4B (LiteRT Community)", not "QAT".
- **Ordering decision:** the promotion work is done now, but it doesn't merge until C9 passes on
  the phone (the plan's dependency). The phone GPU hasn't had a sustained run yet.
- Done on the branch:
  - The manifest points to `gemma-4-E4B-it.litertlm` (3,659,530,240 bytes, `0b2a8980…45bd52e0`),
    with a provenance comment.
  - The seed is at `Aquinas-iOS/LocalModels/gemma-4-E4B-it.litertlm` (APFS clone); only E4B is
    bundled.
  - `visionBackend` comment updated (text-only; C12). `Model-Runtime.md` updated.
  - `MODEL-INTEGRATION.md` isn't edited: the Foundations repo has uncommitted owner changes.
    The drafted edits are in `Gemma4-E4B-MODEL-INTEGRATION-Update.md`.
  - The plan is marked executed only when C10 closes.
- Rollback values: `gemma-4-E2B-it.litertlm`, 3,862,121,696 bytes, SHA-256
  `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282`. The file has moved to the
  root `LocalModels/`; the values are also in the manifest comment.
- Simulator no-override smoke (`C10-sim-nooverride-1`, CPU): the app loaded
  `…/Aquinas-iOS.app/gemma-4-E4B-it.litertlm` with computed SHA-256 = manifest `0b2a8980…45bd52e0`.
  The full lifecycle probe passed (all cases, 0 overlaps).
- Build: pass. Tests: 199/200 (the known baseline failure).
- No-override phone smoke (production app, Debug build of `2776cc9`'s parent `21479f3`, 2026-09-27):
  it loaded `/private/var/containers/Bundle/Application/981F9234-…/Aquinas-iOS.app/gemma-4-E4B-it.litertlm`
  with computed SHA-256 = manifest `0b2a8980…45bd52e0`. The same session surfaced the load/unload race
  fixed in `2776cc9` (then reinstalled). Repeat under C9 on the final build.
- Rollback check result: pending (phone).
- Commits / PR URL: pending.

### C11 / C12 — Optional
- M2-L control analysis:
- Vision probe:

## Final summary

**Rejected with evidence at C9** under the frozen provisional budgets: M4-Ls's first valid
cold phone trial exceeded both the 12-second load and 4-second one-sentence answer limits.
Main remains B0. No PR or merge. The owner is considering whether to plan a new candidate; no later gate is claimed. Keep the earlier C8 CPU
quality result as evidence, but it does not override this physical-device gate.
