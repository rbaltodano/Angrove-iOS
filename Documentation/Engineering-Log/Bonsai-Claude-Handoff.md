# Claude takeover: Bonsai optimization, October 15, 2026

## Claude session update (evening, October 15)

All uncommitted on `feature/bonsai-9b-runtime`; defaults unchanged (E4B, standard prompt,
standard routing). Production phone app untouched. Sealed-3 untouched.

1. **Follow-up routing (done, opt-in).** `LiteRTAngroveModel(followUpRouting: .evaluativeAware)`;
   Mac eval `TEST_RUNNER_ANGROVE_EVAL_FOLLOWUP_ROUTING`; phone probe
   `--litert-eval-followup-routing`. Diagnostic test `MacFollowUpRetrievalDiagnostics` (opt-in,
   `TEST_RUNNER_ANGROVE_FOLLOWUP_DIAGNOSTIC=1`). Results and reading in Angrove-Eval `RESULTS.md`
   ("Follow-up routing…"): fixes subjectless-follow-up retrieval/history; changes only held-E4;
   Bonsai stays wrong on E4 because the answering Summa article isn't retrieved — the MiniLM
   retriever matches "Whether …?" heading wording, not natural questions (separate experiment).
2. **Isolated ModelProbe build (done).** Project settings `ANGROVE_BUNDLE_ID` /
   `ANGROVE_APP_GROUP` (production values at project level) drive the app + both extension bundle
   IDs, the four entitlement files and `BAAppGroupID`. `Shared/Widgets/AngroveAppGroup.swift`
   derives the group from the running bundle on iPhone (Mac keeps the literal); used by
   `DailyQuestionWidgetStore` and the widget Keychain key. Tests `AngroveAppGroupTests`.
   A signed production Release build was verified to have unchanged IDs/entitlements.
   `Angrove-Eval/build-app.sh` now builds Release by default with both settings overridden,
   adds the DEBUG compilation condition (probe entry points only), excludes the bundled E4B,
   and refuses any non-isolated bundle/App Group. Installed on the phone as
   "Angrove – Bonsai Optimization" (`com.ryanbaltodano.Aquinas-iOS.ModelProbe`) with
   heldout.jsonl, both Bonsai GGUFs and the E4B package staged in its Documents.
3. **Phone probe options (done).** `LiteRTEvalBatchProbe`: `--bonsai-model-document <gguf>`,
   `--bonsai-profile`, `--litert-eval-prompt-style`, `--litert-eval-followup-routing`,
   `--litert-eval-case-gap-seconds`; per case: Bonsai engine-call stats, thermal state start/end,
   battery level/state, memory; summary: thermal transitions, memory after load; keeps the
   screen awake. `Angrove-Eval/run-phone-matrix.sh <suffix>` runs E4B / 9B compact / 4B compact
   with cool-downs; `tools/phone_matrix_summary.py` summarizes.
4. **Phone matrix (done):** Angrove-Eval `RESULTS.md` "Matched phone matrix" (runs `PH-*`).
   Base iPhone 17, Release probe, held-out 40: E4B 35/40, 22.6 s median; compact 9B 36/40 (one
   false pass on E4), **19.8 s**; compact 4B 34/40, **12.7 s**. 9B reached "serious" thermal
   sooner than E4B (535 vs 659 s) and caused two system jetsam events (background apps evicted,
   probe survived); 4B never passed "fair". Next: repeat in a different order with matched wall
   time; reduce 9B memory pressure; address the E4 retrieval issue and 4B substantive errors.


## Start here

Owner asked Codex to stop at a clean point because usage is low and Claude will take over.
**All current experiments are complete. No benchmark/build is intentionally left running.**
No new experiment is authorized by a scheduler or background task; resume only from the owner's
new message. Everything remains **uncommitted** on `feature/bonsai-9b-runtime` in the shared
canonical checkout `~/Developer/Angrove-iOS-main`. Other agents have unrelated changes here.
Do not commit, stash, reset, switch branches, overwrite their edits, or stage wholesale.
The existing staged Worktree image deletions predate this work; preserve them.

Read root `AGENTS.md`, `Shared/AGENTS.md`, `Documentation/Development-Workflow.md`, then:
- `Documentation/Engineering-Log/Bonsai-9B-Handoff.md`: full integration/history and every experiment checkpoint.
- `Documentation/Engineering-Log/Bonsai-Optimization-Plan.md`: current approach, technical pitfalls and next steps.
- `~/Developer/Angrove-Eval/README.md` **before any eval**, and its `RESULTS.md` for detailed scores
  and manual answer reviews. Run IDs are immutable; always create a new run folder.
- Before model work, read the Shelving record in
  `~/Developer/Angrove-Foundations/research/rotated-ternary/STATUS.md`. The old Gemma 12B/Qwen
  research is shelved. The owner's explicit new direction here is **Bonsai 2 4B and 9B**.

## Owner's goal and current conclusion

Owner wants Bonsai 9B near current Gemma E4B response latency/thermals, and Bonsai 4B faster
and cooler with comparable quality. They are willing to change the on-device runtime/prompt
architecture. Keep all inference on-device; the app has no network model backend.

**Prompt shortening produced a large Mac response-time improvement. Quality remains unresolved;
phone thermal and matched Release latency claims are not established.** Focus next on context
correctness and isolated phone measurement, rather than writing more compensating prompt prose.
No model or prompt default has changed. E4B, standard prompt and caller/greedy sampling remain
normal behavior. Compact prompt and recommended sampling are explicit initializer/eval opt-ins.

## Results: held-out 40, M4 Pro, scorer v2

| Configuration | Bonsai 4B | Bonsai 9B |
| --- | --- | --- |
| Original full prompt, greedy | 35/40, 8.00 s median | 37/40, 11.43 s |
| Full prompt, Prism recommended prose sampling | 34/40, 8.01 s | 38/40, 11.64 s |
| Compact prompt, same recommended sampling | **34/40, 4.34 s** | **36/40, 6.72 s** |

Recorded same-Mac E4B reference: **36/40, 7.67 s held-out**, **36/40, 7.51 s sealed-1**.
Earlier greedy Bonsai sealed-1: **4B 35/40, 6.70 s; 9B 39/40, 11.02 s**.
The original greedy totals were 4B 70/80, 9B 76/80, E4B 72/80. New optimization phases ran
held-out only, not sealed-1 again. **Never run/read sealed-3**; it remains reserved for acceptance.

Latest immutable runs:
- `B4-MAC-prism-heldout-1`, `B9-MAC-prism-heldout-1`: full prompt + recommended sampler.
- `B4-MAC-compact-heldout-1`, `B9-MAC-compact-heldout-1`: compact conversation system prompt.
- Prior baseline locations are in RESULTS.md; 9B held-out is the derived
  `B9-MAC-heldout-2-combined`, preserving the original 30 plus a 10-case continuation.

Each optimization run completed all 40 expected IDs, zero generation errors/rejects, successful
Xcode test exit. Each has 46 engine calls (42 prose, 4 structured), including audits/extra passes.
One fixed-seed pass and historical comparison do **not** establish statistical equivalence.

Compact-vs-full: input tokens ~98K → ~52K across all passes (−47%); prefill time −55%.
Median first-pass input is **2,444 → 1,236.5 tokens**. Response medians −46% (4B), −42% (9B).
Generated tokens also fall 29%/24%. Native decode speed does not improve: compact pooled
throughput ~64 tok/s (4B), ~39 tok/s (9B). It is less input work and shorter output, not a faster
native decoder. See each compact run's `compact-comparison.json` and result `runtimeGenerations`.
Engine first-answer timing excludes retrieval/load/earlier passes and is not visible UI latency.

### Quality caveats: read these answers

- **held-E4** asks which theological virtue is greatest after faith/hope/charity history.
  4B loses context with both full and compact prompts. Full/recommended 9B answers correctly;
  compact 9B loses context again but **passes the regex falsely** by mentioning charity/love
  in an unrelated discussion of greatness. Equal aggregate scores hide this regression.
- Compact 4B still gives contradictory promise-keeping answers and invents historical details.
  Its pure-act definition is an unchanged structured path with a bad Incarnation claim.
- Some scored misses are wording rather than substantive errors. Compact 9B held-C7 correctly
  says grace elevates/perfects nature, but doesn't match the exact required expressions.
- Shared source/quote misses and weak link/format compliance need manual review. Do not promote
  solely on the numerical scorer or claim compact 9B is quality-equivalent to E4B.

## Code and controls

Prism fork XCFramework `prism-b10777-e3de715`, Swift module `llama`, via local Vendor/LlamaCpp.
Models are outside the repo in `~/Developer/bonsai-downloads`:
- `Ternary-Bonsai-2-4B-PQ2_0.gguf`, 1,146,465,120 bytes,
  SHA-256 `d406b1e912c0d2a4c124ad10bf38a76ae662fdc4d24b176451403dc7b7f30409`.
- `Ternary-Bonsai-2-9B-PQ2_0.gguf`, 2,416,851,840 bytes,
  SHA-256 `7a89ab48f5038c704480f60781f9b8d4035351f5f6beb7d11fad80001fde23f9`.

Main files:
- `Shared/Services/LlamaAngroveRuntime.swift`: Metal engine, ChatML, 16K context, clear cache on
  each request, 3072 max output, thinking off in eval. Init `samplingProfile: .prismRecommended`
  enables Prism prose settings: temp .7, top-p .8, top-k 20, min-p disabled, presence 1.5,
  repeat 1.0, frequency 0, window 64, seed inherited (0). Structured calls remain greedy.
  `recordsGenerationStats: true` records every call; `takeGenerationStats()` drains per case.
  Native llama_sampler_sample already accepts tokens; don't double-accept them.
  `LlamaExitCleanup` handles process exit. Conformance to AngroveTextRuntime lives in an
  extension: declaring it on the actor triggered a Release/WMO compiler isolation error.
- `Shared/Services/LiteRTAngroveModel.swift`: init `conversationPromptStyle: .bonsaiCompact`.
  Compact conversation instructions omit long voice example/redundancy, use truthful Bonsai
  identity, preserve reference text, summary, explicit correction and reasoning/source rules.
  Structured-task prompts and exact-authority branch remain unchanged (including their older
  model-identity behavior). History routing and latest-user wrapper also remain unchanged.
- `Angrove-macOSTests/MacModelEvalBatchTests.swift`: real Angrove pipeline with LazyGroundingProvider.
  Env vars below. Console emits MacEvalResult / MacEvalSummary because test sandbox cannot
  reliably write the external run directory. Archive from console only after successful completion.
- `Angrove-macOSTests/MacBonsaiSamplerTests.swift`: four passing native sampler/prompt tests.
- `project.pbxproj`: llama linked to app targets and Mac tests. Contains unrelated edits;
  stage only intended hunks with `git add -p` if owner later authorizes staging/commit.
- `Shared/Services/BonsaiModelFlag.swift`: normal app flag still **--bonsai-9b**, looks up the
  exact-sized 9B in App Support/Bonsai or Documents/Bonsai. No normal --bonsai-4b flag or UI
  compact-prompt switch was added. Both sizes are supported by the eval GGUF path.
- Other inherited integration files are listed in Bonsai-9B-Handoff.md. Preserve all of them.

Mac eval variables (xcodebuild strips TEST_RUNNER_ before passing into the test host):
```
TEST_RUNNER_ANGROVE_EVAL_GGUF=<absolute GGUF path>
TEST_RUNNER_ANGROVE_EVAL_FILE=<absolute heldout.jsonl path>
TEST_RUNNER_ANGROVE_EVAL_OUT=<fresh external run directory>
TEST_RUNNER_ANGROVE_EVAL_MODEL_LABEL=bonsai-4b  # or bonsai-9b
TEST_RUNNER_ANGROVE_EVAL_BONSAI_PROFILE=prismRecommended  # default caller
TEST_RUNNER_ANGROVE_EVAL_PROMPT_STYLE=bonsaiCompact        # default standard
TEST_RUNNER_ANGROVE_EVAL_IDS=id1,id2                       # optional; validated
```
Build test host, then use Mac scheme, concrete arm64 destination, derived data
`build/workspace-layout-mac`, `-test-timeouts-enabled NO`, and
`-only-testing:Angrove-macOSTests/MacModelEvalBatchTests`.
Use a fresh run ID even after a failure; preserve evidence. Score with unchanged
`python3 score_objective_v2.py eval-set/heldout.jsonl runs/<new-id>` from Angrove-Eval.

Temporary convenience scripts in /tmp (read before use; not canonical tooling):
- `/tmp/bonsai-run-compact.py <fresh-run-id> heldout.jsonl <4|9>` creates provenance and runs
  test-without-building with compact/recommended settings.
- `/tmp/bonsai-run-recommended.py` similarly runs the full prompt with recommended sampling.
- `/tmp/bonsai-archive-eval.py <run-id>` reconstructs console JSON after completion.
- `/tmp/bonsai-progress.py <run-id>` and `/tmp/bonsai-profile-summary.py <run-id>` read progress/timings.

## Immediate next work (not started)

1. **Fix/measure underspecified follow-up grounding.** Inspect `groundingQuery`,
   `followUpDependsOnContext`, `conversationRequest`. Code inspection shows retrieval can use
   the latest question alone even when chat history is retained. Test general comparisons,
   superlatives and “why?” across multiple subjects, not only the held-out virtue fixture.
   Confirm actual reference selection; don't assume every context failure is model capacity.
   Keep this experiment separate from prompt/sampler changes and rerun relevant quality cases.
2. **Repair isolated ModelProbe builds** before phone work. Angrove-Eval/build-app.sh is broken:
   old LocalModels path and a global bundle-ID override causing extension ID collisions. Use
   per-target app/extension IDs, required special-build display name, and audit App Group /
   widget/startup effects so probes cannot mutate production data. No production bundle install,
   launch, wipe or model staging without asking owner. ModelProbe ID:
   `com.ryanbaltodano.Aquinas-iOS.ModelProbe`.
3. **Matched Release phone measurements** for E4B and both Bonsais. Current phone data for 9B
   is only an earlier three-turn Debug smoke sample (~45 s answer, 14–17 s prefill), not a matched
   current benchmark. Measure cold weight load separately from prefill/first-answer/complete
   response; compare full vs compact, sustained tasks, memory, thermal state/throttling, energy
   evidence if available, matched starting conditions and charging. No phone thermal result yet.
4. **Prefix/session checkpoints**, after prompt/context correctness. Current engine clears all
   memory every request. Qwen3.5 is recurrent/hybrid: restore compatible complete state, not
   just KV positions. Keep caches bounded/in-memory, invalidate on cancel/unload/context changes,
   and verify cross-conversation isolation and restore vs full recomputation.
5. **Metal/MTP experiments**, independently. Pinned fork auto-enables tensor API on supported
   A19/M5; verify actual logs. Flash attention is AUTO currently. Paper's ~90 phone tokens/sec
   is 2B plain or 9B copy-heavy speculation; 9B ordinary phone decode is ~22, and plain won its
   everyday phone workload. Don't promise 90 for ordinary 9B conversations. Paper/source links
   and detailed technical cautions are in Bonsai-Optimization-Plan.md.

## Verified stopping state

- Four focused tests pass: `/tmp/bonsai-compact-tests2.log`.
- Signed iOS device-target build passed: `/tmp/bonsai-compact-device-final.log`; bundled model
  resources excluded (`EXCLUDED_SOURCE_FILE_NAMES=*.litertlm`) and **not installed on phone**.
- Signed Release Mac update installed at **/Applications/Angrove.app**, using the required
  installer after normal quit: `/tmp/bonsai-compact-mac-install.log`. Normal defaults unchanged.
- No commits, staging, stashing, branch switches, production phone operations, or sealed-3 access.
- Prior handoff describes an earlier agent's Debug production phone installation. Do not infer
  current device state from old notes; inspect read-only before any separately authorized action.
- Keep future status updates short, status first. Owner explicitly requested this stopping point.
