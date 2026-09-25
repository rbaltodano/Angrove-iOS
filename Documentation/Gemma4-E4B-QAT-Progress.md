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
| C2 | Provenance classification | C1 | todo | | | Can run in parallel with C3 |
| C3 | Harness hardening (code) | C0 | in-progress | Claude Code (Opus 5.5) session | 2026-09-25 | Started while the C1 download runs (C3 depends only on C0) |
| C4 | Simulator compatibility (informational) | C1, C3 | todo | | | |
| C5 | Early phone memory/compat screen | C4 | todo | | | Freezes `operating_cap` |
| C6 | Integration diagnostics | C5 | todo | | | |
| C7 | Full-app functional + lifecycle stress | C6 | todo | | | |
| C8 | Quality A/B (40 dev + 40 held-out) | C7 | todo | | | Needs owner review time |
| C9 | Physical-device sustained gate | C8 | todo | | | |
| C10 | Promotion | C9 + owner approval | todo | | | |
| C11 | Optional: M2-L control analysis | C8 | todo | | | |
| C12 | Optional: vision probe | C10 | todo | | | |

**Next action:** Finish C3; run C2 alongside it.

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
- Classification (confirmed-QAT + citation / unconfirmed):
- Discussions #16 and #18 findings:
- #2497 / E2B #30 / blog status when checked:
- Supporting: decoder dtype histogram, `prefer_activation_type`:
- Draft owner-approval question (if any):

### C3 — Harness hardening
- Commit:
- Tests added:
- Full suite result:
- Sample result JSON path (raw and quality modes on B0):

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
