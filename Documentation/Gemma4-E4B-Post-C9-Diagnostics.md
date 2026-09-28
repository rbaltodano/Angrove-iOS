# E4B phone usability diagnostics after C9

> Status: frozen for P1, 2026-09-27. Owner delegated the next model decision to the
> senior developer. This is an informational follow-up, not a revision of the failed C9 gate
> or an approval to promote. Preserve all C9 evidence and its `failed` status.

## Decision to make

The standard E4B package scored higher than B0 in C8 and used less memory in the valid C9
phone sample, but missed the frozen cold-load and cold-answer budgets. Determine whether its
cached and sustained phone behavior is suitable for a new product proposal, or whether to
stop work on this package. Do not choose a new acceptance budget from P1 data and then call
P1 a passing promotion gate. Any future promotion requires a separate plan with criteria
frozen before its runs, phone GPU quality confirmation, and owner approval.

## Frozen P1 protocol

- Worktree/branch: `Aquinas-iOS-e4b-qat` / `feature/gemma4-e4b-qat`. Active artifact M4-Ls,
  SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`;
  LiteRT-LM 0.14.0, GPU, text-only, 4,096 tokens, production greedy decoding and retrieval.
  No prompt, model, system-instruction, or runtime setting changes during P1.
- Use Ry (base iPhone 17), DEBUG disposable bundle
  `com.ryanbaltodano.Aquinas-iOS.ModelProbe`, with `--litert-sustained-probe` and the bundled
  E4B file via the DEBUG model-path override. Do not install over or write into production
  Aquinas. Verify production data backup and current Home counts before installing. Keep the
  production process closed during measurements. Never use `--remove-existing-content` on it.
- Raw evidence uses fresh immutable IDs `P1-M4Ls-<n>` in `LocalModels/e4b-eval/`, with exact
  commands, model hash, OS, effective settings, result JSON, lifecycle trace, stderr, and
  before/after crash-log listings. The existing C9 runner may be used with a new result name.
  A failed or preflight-only run keeps its ID and is never overwritten.
- At nominal thermal state, launch one fresh-process **prime** run, clearing only the
  disposable E4B cache. Fixed short input: “In one sentence, what is prudence?” Its latency is
  informational; C9 already proved the old cold gate failed. After that, run three cached
  fresh-process trials with the same short input and the cache present. Do not clear the
  cache between them. Report every load, retrieval, visible completion, metadata completion,
  peak footprint, and thermal sample; report min/median/max, not a five-sample p95.
- If these runs complete without crash, run one fresh-process 20-turn sequence through the
  shared app queue, using the same short input as independent fresh-conversation turns. Discard
  its first turn as warm-up for the turn-20/turn-1 ratio. Record each latency, thermal state,
  memory, and native overlap events. Then run one 75-second idle hold followed by a new
  request with a shortened DEBUG idle timeout to exercise reload.
- A real OS background/foreground cycle, a memory warning, and cancel/stall recovery remain
  safety questions from C7. Do not substitute queue-only lifecycle probes for real OS cycles.
  If device control cannot perform them, record them as unverified and do not recommend
  promotion. Stop any run on jetsam, signal 9, critical thermal state, stale UI updates, or
  concurrent old native work and a new load.
- Do not run the 40-case held-out GPU set, edit `LiteRTAquinasModel.swift`, update Foundations,
  push, open a public PR, or merge under P1. Those steps belong to a later passing promotion
  plan. Keep the current production E4B installation as a personal trial only.

## Decision rule

P1 does not pass or fail C9. Recommend either (a) a new, predeclared product plan with explicit
latency tradeoffs and full device/quality gates, or (b) stopping E4B promotion work. Base the
recommendation on every P1 sample and the C9 failure. Report what remained unverified.

### Instrumentation amendment before P1 runs (2026-09-27)

For the 20-turn continuous foreground diagnostic only, the DEBUG probe disables iOS's idle
screen timer while the run is active, then restores it. This prevents the screen locking and
suspending a test intended to measure sustained foreground work. The separate real OS
background/foreground question still requires explicit scene transitions. Thermal tracing runs
from a detached task so synchronous retrieval/model calls do not pause its one-second samples.
Neither change alters the LiteRT model, sampler, prompt, queue, or runtime lifecycle policy.
Commit the instrumented build and use it for **all** P1 runs; no P1 model run preceded this
amendment.

## Stopping point — 2026-09-27

Protocol and instrumentation committed before trials. Fresh production-data backup verified:
`LocalModels/e4b-eval/P1-preflight-1/backup-manifest.json` and `data-counts.json` (28 files,
9 conversations, 13 saved Insights, 1 study topic, 81 seen Insight IDs). P1 DEBUG physical build
passed (`build-instrumented.log`). The disposable probe was installed but never launched for a
P1 model run, then uninstalled at the owner's request to reach a stopping point. Production E4B
remains installed with its data untouched. No P1 run IDs exist. Resume by reinstalling the
built disposable app, checking its new installed bundle path, then prime its E4B cache under
`P1-M4Ls-1` with the frozen flags. Do not reuse old C9 IDs or results.

## P1 results so far — 2026-09-27 (Claude session)

Fresh production-data backup first: `P1-preflight-2` (28 files, matching `P1-preflight-1`).
The production app process was closed before the runs. The disposable app was built from
`e1a4a7b`'s instrumented code (unchanged at `3ca9ad6`), installed, and then uninstalled
afterwards. Summaries come from `LocalModels/e4b-eval/p1_summary.py`. Load time is taken from
the native load interval in the lifecycle trace. Thermal state stayed nominal throughout, all
answers succeeded, and there was no jetsam.

| Run | Kind | Load (s) | Request → answer complete (s) | Peak footprint |
| --- | --- | --- | --- | --- |
| P1-M4Ls-1 | Prime (cache cleared) | 14.77 | 24.69 | 1.13 GB |
| P1-M4Ls-2 | Cached | 7.66 | 16.37 | 1.13 GB |
| P1-M4Ls-3 | Cached | 7.47 | 16.13 | 1.13 GB |
| P1-M4Ls-4 | Cached | 8.32 | 17.44 | 1.24 GB |

Cached: load min / median / max = 7.47 / 7.66 / 8.32 s; answer = 16.13 / 16.37 / 17.44 s. After
the load, each answer took about 8.7–9.1 s, consistent with C9.

**Not run yet:** the 20-turn sequence (`--litert-c9-twenty-turns`), the 75-second idle hold with
reload, and the real OS lifecycle checks. Resume at `P1-M4Ls-5` by reinstalling the disposable
app (its bundle path changes on every install).

**Reading (informational, not a gate).** Cached load (about 7.7 s) matches B0's
*cache-cleared* load in C9 (7.9 s). B0's cached load hasn't been measured, so there is no
cached comparison yet. Most of the answer time after loading is spent on prefill and decode
of the grounded prompt, and C9's valid samples show it for both models (E4B about 9 s vs B0
about 10.5 s). Reducing prompt size is a model-independent latency lever.

## Owner report: memory pressure in daily use — 2026-09-28

The owner reports that the production E4B build on Ry is unusable in daily use: answers never
load, and background music stops (iOS is killing other apps to reclaim memory).

**Likely cause (hypothesis, not yet verified on the phone): the installed build predates the
SHA-256 fix.**
- The production app on Ry is a Debug build of `2776cc9`, installed 2026-09-27.
- DEBUG builds hash the loaded model once per process (`LiteRTAquinasRuntime.logLoadedModelOnce`
  → `LiteRTModelInstaller.sha256`).
- Before `a4fd7c0`, that hash kept the file's 8 MiB read buffers alive for the whole task. Codex
  reproduced a 3.87 GB peak (`C9-diagnostics-1`) and saw it on the phone (`C9-B0-1`, invalid).
- Model plus hash therefore approaches the whole phone's memory budget, which fits the report.
- P1 ran the fixed build: peak 1.13–1.24 GB, no pressure kills. In C5, E2B's `phys_footprint`
  agreed with jetsam's resident count (2.04 GB) on the same standard GPU delegate, so the P1
  number is plausibly complete. Unlike the artisan package (M4-L), there is no evidence that it
  under-reports for M4-Ls.

**Next time the phone is connected:**
1. Install a build that includes `a4fd7c0` into production, keeping data (the current branch
   HEAD, or a Release build, which skips the DEBUG hash entirely). Back up first.
2. Verify with the owner's scenario: music playing, ask a question, and pull any JetsamEvent
   reports. Record the jetsam resident count for the Aquinas process next to `phys_footprint`.
3. If pressure persists with the fixed build, the model itself is too large for daily use. Then
   try a 2,048-token KV cache and a faster idle unload as a new candidate configuration, or
   revert the phone to `main`'s E2B build.

## Prompt size per question — 2026-09-28 (from existing C8 records, no new runs)

`C8-M4Ls-held-2/litert-generations.jsonl`, 35 conversation prompts rendered by LiteRT-LM's own
template:
- Median 19,138 characters, maximum 24,020. That is roughly 4,000+ tokens at about 4.5
  characters per token (an estimate; the exact count needs the tokenizer).
- Example split: system preface about 8,100 characters, per-turn message about 9,000. The
  per-turn message is mostly standing instructions (revisability rules, register examples,
  naming rules) repeated on every turn, with the question itself about 100 characters.

At C5's measured prefill rate (about 830 tokens/s on the phone GPU), prefill alone is about
4–5 s per answer, before any decoding. That explains most of the ~9 s answer time after load,
for both models. It also leaves little of the 4,096-token window for history and the answer
(C6's thin compaction margin). Trimming the standing instructions is the single biggest
latency lever, and it's model-independent. It belongs to the owner's system-prompt work on
`main` (`LiteRTAquinasModel.swift`).

Release build of `ee3d5e2` for production is ready at
`build/DerivedData/Build/Products/Release-iphoneos/Aquinas-iOS.app` (bundled model SHA-256
`0b2a8980…`). Not installed yet: the phone was unreachable.
