# Historical model and runtime exploration

These experiments explain decisions in [the product case study](Case-Study.md). They are
**historical and shelved as of September 25, 2026**. This summary uses existing records; no model
was downloaded, converted, trained or run for this publication. Research branches were not
merged into the production model/runtime. Current development uses stock Gemma 4 E4B through
LiteRT-LM.

## Gemma 4 12B: runtime feasibility was not product readiness

The August 27, 2026 experiment asked whether a larger dense model could fit the base iPhone 17.
A calibrated **IQ2_M GGUF** contained 4,371,806,688 bytes. A disposable llama.cpp Metal probe used
a 512-token context and 32-token chunked prefill. Reducing the prefill batch eliminated an
initial GPU out-of-memory failure and enabled short deterministic generation.

A retained-session trial generated 48 tokens in 5.537 seconds (about 8.7 tokens/second), then
terminated with signal 9 during a requested 40-second resident hold. A same-minute system report
showed memory pressure. That correlation supports a memory-headroom concern, but the report did
not retain a separate post-kill record identifying the probe as the jetsam victim. The response
was token-capped, so it was neither a completed-answer quality score nor a sustained stability
pass. This route was not promoted.

Earlier stock 12B LiteRT packages also failed the product constraints: one failed generation
and, with a matched runtime, caused a system-memory-exhaustion reboot; another generated a
coherent answer but took 54.94 seconds to load and 190.61 seconds to generate in the recorded
trial. These are specific package/runtime observations, not proof that all 12B models are
infeasible or that one runtime universally beats another.

**Decision lesson:** count initialization buffers, KV cache, app/OS headroom and session retention,
not just the quantized file. Successful token generation does not establish a usable app.

## Qwen3-4B: a smaller model worked, but factual reliability remained separate

The tested smaller model in the August records is **Qwen3-4B**, not Qwen3.5. Its official
**Q4_K_M GGUF** occupied about 2.33 GiB on device (SHA-256
`ab27b9bfa375a178d6cba48f3ad892b94b7739659dcc7aae8058ce0ffed6b328`). The disposable llama.cpp
Metal runtime completed bounded multi-turn probes at 2,048 and 4,096 context. In the 4K probe,
a 24-token generation took 1.306 seconds (18.4 tokens/second), followed by a successful 40-second
resident hold. Those bounded probes established feasibility on that phone, not broad supported
device coverage or a blind answer-quality win.

A subsequent research-only adapter put Qwen into the real conversation UI, isolated from the
production app container. Fine-tuning experiments exposed two different problems:

- A PDF parser mistook repeated page headers for new articles, producing incomplete training
  examples. Correcting article boundaries reduced the recorded corruption from 32% to 0.5%.
- Reformatting raw continuations into question/answer determinations and adjusting repetition
  sampling improved output form. A John 14 citation test still produced fabricated quotations;
  supplying the source passage alone produced an unhelpful response in the recorded test.

These observations motivated prioritizing retrieval, passage use and source fidelity over
assuming that a model swap or a lower validation loss would fix citations. They do not establish
that fine-tuning can never improve factual reliability; this was a narrow, exploratory
investigation without a matched, blind comparison against today's E4B pipeline.

## Proposed alternatives are not completed experiments

The September 28 [model strategy proposal](Model-Strategy-Plan.md) lists Qwen3.5-4B and
Qwen3.5-9B among future candidates. This summary does not attach Qwen3-4B's measured results to
those different models. A separate rotated-ternary 12B prototype remained a bounded compression
research effort: it did not deliver a runnable custom-format phone model or a blind quality pass.
All of that shelved work remains historical here.

## Evidence provenance and limits

This is a curated summary of archived narrative records, not newly collected raw benchmark
artifacts. The source-document snapshots used on October 5, 2026 are fingerprinted below.
Their hashes identify the record versions; they do not independently validate the measurements.
Original research material remains in the local archive and is not published by this change.

| Archived record | SHA-256 of the consulted document |
| --- | --- |
| `MODELQUANTIZATIONRESEARCH.md` | `794a3cb6c8ae4c981c0dd53afc1e3253d5eab0b127222ab68c3cea07b5880749` |
| `QWEN-TESTING-CASE-STUDY.md` | `66d1bdb3d55bf58fee6523fe00675ceee626e22543c48f6028da814785190755` |
| `STATUS.md` | `bfc33f8956f4eadf377eff12893c44d0a6da81863fa70691243c63d837455bc5` |

The devices, context sizes, token caps, model packages and tasks differ. Do not compare these
numbers with the simulator thinking experiment as a runtime leaderboard. The current LiteRT
choice reflects the working product integration and the limits observed in these experiments,
not a universal speed or quality ranking.
