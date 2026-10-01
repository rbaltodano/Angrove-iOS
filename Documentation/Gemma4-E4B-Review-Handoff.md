# Gemma 4 E4B review handoff — 2026-09-27

This is a review snapshot for Claude. Work only in `~/Developer/Aquinas-iOS-e4b-qat`, on
`feature/gemma4-e4b-qat`. The branch and its evidence are local and unpushed. `main` still
selects the fine-tuned E2B baseline (B0). The GitHub remote is public; the owner said not to
post publicly or merge without them. This review does not authorize device runs or promotion.

## Read and check

1. Read [`AGENTS.md`](../AGENTS.md), then the execution rules and C9 failure branch in the
   [frozen plan](Gemma4-E4B-QAT-Plan.md). The plan's opening “Not yet executed” marker is
   historical; use the ledger for current status.
2. Read the [current handoff, status board, C9 protocol and closeout](Gemma4-E4B-QAT-Progress.md).
   The ledger's older “Prior handoff” and its remaining-steps list are historical.
3. Review the [frozen P1 diagnostic protocol and stopping point](Gemma4-E4B-Post-C9-Diagnostics.md),
   the [runtime description](Model-Runtime.md), and the
   [proposed Foundations update](Gemma4-E4B-MODEL-INTEGRATION-Update.md). The latter is a review
   draft; do not apply its superseded promotion claims.
4. Inspect the DEBUG sustained harness in
   [`LiteRTSustainedProbe.swift`](../Angrove-iOS/Features/Developer/LiteRTSustainedProbe.swift),
   its call sites, and the bounded-memory `LiteRTModelInstaller.sha256` change. Do not edit
   `Angrove-iOS/Services/LiteRTAngroveModel.swift`; the owner may change prompts there on main.

## Decision already reached

| Item | State | Evidence or limit |
| --- | --- | --- |
| C0–C8 | Done | C8's 40-case held-out simulator CPU review favored E4B: mean accuracy 3.85 vs B0 3.05; critical failures 1 vs 9 after owner-delegated review. This was not an independent reviewer, and the held-out set has not run on the phone GPU. |
| C9 | **Failed** | Ry, iPhone 17, iOS 27.0, LiteRT-LM 0.14.0 GPU, 4,096 context, greedy. The first valid E4B cold trial (`C9-M4Ls-2`) loaded in 12.824 s against ≤12 s and completed the short answer in 21.910 s against ≤4 s. |
| C10 | **Blocked** | Branch manifest and seed select E4B; no rollback trial, PR, push, or merge. Main remains B0. |
| P1 | Protocol frozen; no model runs | The DEBUG build and fresh production-data backup passed. The disposable probe was uninstalled at the stopping point. |

The C9 limits and nearest-rank p95 method were committed before trials (`87a5cc9`). With five
planned samples, p95 is the maximum. Thus this one valid over-limit E4B sample makes both
planned gates fail even if the four remaining samples were faster. **No measured five-sample
p95 exists.** Do not retroactively relax a budget or relabel C9 as a pass. B0's valid cold
context trial (`C9-B0-2`) loaded in 7.916 s and completed the short answer in 18.446 s;
its own answer also exceeded the four-second budget, but B0 was contextual and did not lower
the candidate's absolute limit. The E4B trial's peak physical footprint was 1,087,706,216 B,
thermal state nominal, and no jetsam observed. Retrieval ended 13.155 s after acceptance;
the first visible answer and completion both occurred at 21.910 s. Native prefill boundaries
were unavailable and recorded as such. Cached, 20-turn, real OS lifecycle, and phone GPU
quality trials were held after the decisive failure.

`C9-B0-1` is preserved as incomplete and invalid for controlled memory comparison after a
DEBUG SHA-256 memory problem. The bounded-memory hash fix (`a4fd7c0`) yielded the same B0 hash
and reduced a local hash reproduction's peak footprint from 3.87 GB to about 14 MB.
`C9-M4Ls-1` refused to start because the phone was already warm; it did not load the model.
Neither is a valid candidate result. The corrected device build passed.

## Raw evidence and phone state

Evidence is gitignored and available only in this worktree under `LocalModels/e4b-eval/`.
Do not reuse run IDs or modify run folders.

- `C9-M4Ls-2/run.txt`, `litert-sustained-result.json`, `litert-lifecycle.jsonl`,
  `litert-probe-stderr.log`, `new-crashlogs.txt`: exact candidate command, timings,
  settings, samples and device reports.
- `C9-B0-2/`: valid comparator; `C9-B0-1/` and `C9-M4Ls-1/`: invalid/preflight records.
- `C9-preflight-3/artifact-manifest.json`, `backup-manifest.json`, `data-counts.json`:
  exact artifact hashes and verified production-data backup.
- `C9-diagnostics-1/hash-original.txt`, `hash-bounded.txt`, `build.log`:
  hash correction and device build evidence.
- `P1-preflight-1/backup-manifest.json`, `data-counts.json`, `build-instrumented.log`:
  verified fresh backup and P1 build. There are no `P1-M4Ls-*` result folders.

The standard E4B M4-Ls package SHA-256 is
`0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`;
B0 is `9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282`.
The owner-approved production E4B installation remains on Ry **as a temporary personal trial**;
its app data was backed up and left untouched. The disposable
`com.ryanbaltodano.Aquinas-iOS.ModelProbe` is uninstalled. Never use `devicectl
--remove-existing-content` against production `com.ryanbaltodano.Aquinas-iOS`. Back up
production data before any future model experiment and use the disposable bundle ID.

## Questions for review and next decision

- Check that the C9 harness measures the frozen request-to-visible-answer contract faithfully,
  including retrieval, UI buffering, and cold load; note any limits without changing the
  recorded result. Examine the SHA fix for correctness and whether DEBUG instrumentation
  changed product behavior.
- Check that the current documentation distinguishes an E4B branch/phone trial from a shipped
  model. The Foundations draft awaits reconciliation with the owner's uncommitted edits in
  `../Aquinas-Foundations`; this task did not change that repo.
- Assess whether P1's cached and sustained diagnostic protocol can inform a **new** proposal.
  It cannot pass C9. A later promotion would need criteria frozen before its runs, phone GPU
  held-out quality confirmation, real OS lifecycle and recovery checks, rollback evidence,
  and an explicit owner decision. The current public remote restriction also prevents a PR.

The 12B rotated-ternary, IQ2_M, and Qwen research was shelved; do not resume it. Source model
files in `LocalModels/` are governed by the plan. Free disk space has been tight (roughly 8 GB),
so inspect and clear only stale build products before any large future build.
