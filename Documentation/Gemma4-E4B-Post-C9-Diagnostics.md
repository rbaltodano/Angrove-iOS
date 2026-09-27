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
