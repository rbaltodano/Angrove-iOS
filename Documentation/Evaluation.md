# Evaluating the AI product

Angrove evaluates the **app pipeline**, not just a model prompt: conversation context, local
retrieval, evidence selection, generation, response parsing and validated key terms can all
change the answer. Unit tests cover deterministic contracts; model evaluations cover answer
behavior. Neither substitutes for usability research or physical-device release validation.

## A measured product decision: native thinking

On October 2, 2026, four completed simulator CPU runs compared native thinking on and off using
app revision `5cf05539ba7cd94b809eecf237f48a23ec9a9b51`. All used the same stock Gemma 4 E4B
package and app pipeline. The host was an Apple M4 Pro on macOS 27.0.1, with an iOS 27.0 simulator.

| Comparison set | Thinking off | Thinking on | Median answer time off / on |
| --- | --- | --- | --- |
| Held-out (40 cases, already used in development) | 37/40 | 36/40 | 23.0 s / 43.7 s |
| Sealed-1 (40 cases, already used in development) | 37/40 | 38/40 | 23.5 s / 47.6 s |
| Combined objective passes | **74/80** | **74/80** | — |

The absence of an aggregate score increase, together with the time increase, supported keeping
native thinking **off by default** (`504db27`). This is evidence for that configuration decision,
not a claim that reasoning never helps or that the app is “92.5% accurate.” The objective scorer
checks patterns, output constraints and metadata; it can penalize valid paraphrases and miss
substantive errors. The previous review identified wording-sensitive score flips.

The times above are the arithmetic median of all 40 raw `seconds` values per run, rounded to one
decimal. The historical scorer report used the upper middle observation for an even-sized set
(23.05/44.13 and 23.75/48.15 seconds). This public report uses the conventional median consistently.
Timing starts inside the eval adapter's `respond` call, after model loading; it excludes queue
wait and UI reveal. It includes retrieval, short-circuit answers and any audit generation.

### Public evidence

The following aggregate exports retain run, model, fixture, input-artifact and scorer hashes,
case/category counts, outcomes and timings. They exclude prompts, generated answers, filesystem
paths, device identifiers and native logs. Raw experiment material remains in the private eval
archive. These summaries are inspectable evidence, not a fully public independent replication
kit; the private fixture/scorer files are still required to reproduce the original scores.

- [Held-out, thinking off](Evaluation/T2-heldout-thinking-off.json)
- [Held-out, thinking on](Evaluation/T2-heldout-thinking-on.json)
- [Sealed-1, thinking off](Evaluation/T2-sealed-1-thinking-off.json)
- [Sealed-1, thinking on](Evaluation/T2-sealed-1-thinking-on.json)

The model SHA-256 is `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
All four runs completed 40 cases with zero recorded runtime errors. These are historical
observations on that build, not a test run of today's working tree.

## Repeatable evaluation workflow

1. Define a hypothesis and freeze model hash, app commit, prompt/configuration, retrieval assets,
   scorer version and fixture hash before running. Use development cases to iterate. Reserve a
   new sealed set for independent acceptance; both sets above are now development material.
2. Cover regression facts, contextual definitions, reasoning, source-sensitive claims,
   uncertainty/false premises and multi-turn references. Include cases where an abstention is
   safer than a plausible unsupported answer.
3. In a disposable Debug build with the assets installed, use the existing
   `LiteRTEvalBatchProbe` launch path. It runs cases through `LiteRTAngroveModel`, preserves one
   result per case, and writes a completion marker. An input JSONL record has this shape:

   ```json
   {"id":"example-001","category":"definition","turns":[],"question":"What is prudence?"}
   ```

   This is an input example, not an evaluated result. Turn records use `role` and `text`.
   Launch arguments are `--litert-probe --litert-probe-auto --litert-eval-batch <fixture-path>
   --litert-probe-run-id <new-id> --litert-record-generations`. Simulator CPU comparisons also
   pass `--litert-probe-cpu`; the thinking arm adds `--litert-eval-thinking`. Keep all other
   variables fixed. Copy results out before another run overwrites the probe's output files.
4. Score objective constraints with the frozen scorer and review the actual answers. Separately
   report `pass`, `abstained`, `incomplete_or_wrong` and `reject`; an abstention is not a runtime
   crash. Blind review should judge factual correctness, source fidelity, reasoning, usefulness
   and voice. Preserve original scores when revising a scorer.
5. Export aggregate evidence with the public script. It rejects incomplete runs, duplicate or
   missing cases, changed fixtures, mismatched score totals and invalid timings:

   ```sh
   python3 scripts/export_eval_summary.py \
     --run-dir /path/to/completed-run \
     --cases /path/to/frozen-cases.jsonl \
     --app-revision <exact-built-commit> \
     --host 'host hardware and OS' \
     --output /path/to/public-summary.json
   ```

   Add repeatable `--scorer-artifact /path/to/scorer.py` arguments to record scorer and
   additions-file hashes. The four published reports include these fingerprints.

   This tool summarizes existing v2 score artifacts; it does not judge correctness or execute
   inference. Its behavior checks run with `python3 -m unittest discover -s scripts/tests -v`.
6. On the target phone, measure cold and cached load, time to first visible answer, total answer
   time, peak physical memory, thermal state, sustained turns, cancellation, background/foreground
   transitions and idle reload. Keep failed trials. Simulator CPU timing cannot establish any of
   these physical-device budgets. No current phone p95, battery or broad device-support claim is
   made in this report.

## Regression coverage in the app

| Contract | Existing suites |
| --- | --- |
| Local engine lifecycle, cancellation and explicit unavailable actions | `ModelRuntimeLifecycleTests`, `LiteRTProductionRuntimeTests`, `ModelActionAvailabilityTests` |
| Retrieval reaches source text, disambiguates named sources and rejects irrelevant evidence | `MiniLMGroundingRetrievalTests`, `SummaArticleEvidenceTests`, `ScriptureCitationTests` |
| Model failure and evidence routing | `EvidenceAblationTests`, `DefinedTermMarkupTests` |
| Queued labels and semantic membership | `InsightTreeLabelQueueTests`, `InsightTreeSemanticMembershipTests` |
| Durable conversation identity and late-result reconciliation | `InquiryPersistenceStoreTests`, `StreamingMessageNavigationTests` |
| Development encryption, migration, key loss and widget separation | `PersonalDataEncryptionTests`, `DailyQuestionWidgetStoreTests` |

Asset-dependent tests explicitly skip without the gitignored grounding export. Test presence
is not a claim that a new full suite has passed. The encryption change's focused simulator
verification is recorded separately; real-device lock and backup restore remain pending.
