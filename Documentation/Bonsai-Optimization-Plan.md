# Bonsai on-device optimization experiments

Owner direction, October 15, 2026: investigate both Bonsai 2 4B and 9B aggressively before
rejecting them on current integration speed/quality. E4B remains the product default until
an explicit decision. All inference stays on-device through AngroveModel and one shared queue.

## First experiment: recommended non-thinking sampling

Opt-in only: `LlamaAngroveRuntime(samplingProfile: .prismRecommended)`;
Mac eval environment `TEST_RUNNER_ANGROVE_EVAL_BONSAI_PROFILE=prismRecommended`.
Use temperature 0.7, top-p 0.8, top-k 20, min-p disabled, presence penalty 1.5,
repeat penalty 1.0 (disabled), frequency penalty 0, history window 64. Fixed seed 0 for prose.
Structured calls retain their caller's deterministic settings; this is intentional contract
protection, not a claim that every app call runs Prism's prose profile. Thinking remains off.

Sources: [small-model settings](https://github.com/PrismML-Eng/Bonsai-demo/blob/main/SMALL-MODELS.md),
[whitepaper](https://github.com/PrismML-Eng/Bonsai-demo/blob/main/bonsai-2-small-whitepaper.pdf).

Run the full held-out 40 for each model with scorer v2 unchanged, new immutable evidence folders,
matching app prompt/context settings and no simultaneous build workload. Record every engine
call, including structured audits and retries: prompt/output tokens, prefill/decode time, engine
first-answer timing, stop reason, actual sampling settings, seed, and whether structured.
Engine first-answer timing is not a measurement of visible UI streaming latency.
Report whole-case time alongside tokens/sec. One fixed-seed pass is an initial experiment,
not a statistical accuracy improvement claim; replicate promising configurations with more
seeds before selecting them. Keep sealed-3 untouched.

## Recommended sampling results

First-pass held-out results: 4B recommended **34/40, 8.01 s** versus caller **35/40, 8.00 s**;
9B recommended **38/40, 11.64 s** versus caller **37/40, 11.43 s**. No meaningful latency
improvement from sampling alone. Prefill consumed **46.1% (4B)** and **55.2% (9B)** of engine
time across all calls; pooled decode was **65.25** and **40.19 tokens/sec** respectively on
the M4 Pro. The 9B theological-virtue follow-up is correct in this seeded run. The 4B still
loses that context. Full evidence and caveats are in Angrove-Eval/RESULTS.md.

Runs: `B4-MAC-prism-heldout-1`, `B9-MAC-prism-heldout-1`; both completed 40 unique cases with
46 engine calls (42 prose, 4 structured), no generation failures. No new sealed-set or phone
experiment was performed in this phase. Recommended settings remain explicit opt-in.

## Compact prompt experiment

Owner requested shorter system instructions and a target of 9B latency/thermals near E4B,
with Bonsai 4B faster/cooler at comparable quality. New model-init opt-in:
`conversationPromptStyle: .bonsaiCompact`; eval environment
`TEST_RUNNER_ANGROVE_EVAL_PROMPT_STYLE=bonsaiCompact` (GGUF only). Default remains `.standard`.
This replaces long role/voice/annotation guidance and its soul/body example with concise rules
and truthful conversation model identity. Complete references, compacted context and explicit
corrections survive; history routing, latest-user wrapper, structured prompts and exact-authority
branch are unchanged. Tests verify size budget and evidence/authority preservation.

Held-out Mac runs, recommended sampler, fixed seed, scorer v2:

| Model | Full prompt | Compact prompt |
| --- | --- | --- |
| 4B | 34/40, 8.01 s | 34/40, 4.34 s |
| 9B | 38/40, 11.64 s | 36/40, 6.72 s |

Runs: `B4-MAC-compact-heldout-1`, `B9-MAC-compact-heldout-1`; both complete, 40 unique IDs,
zero generation failures, 46 engine calls each. Input tokens fell ~47%, prefill time ~55%,
generated tokens 24–29%. Native decode rate did not improve. Median first-pass input is
2,444 → 1,236.5 tokens; response-time medians fell 42–46%. New 9B Mac median is below
historical E4B 7.67 s, but this is not matched phone/thermal evidence or quality equivalence.

Manual review: 4B still loses the virtue follow-up. 9B also loses it again in compact mode,
but the scorer passes its unrelated answer because it mentions charity/love. Some other
score differences are wording, so aggregate scores cannot establish safe promotion.

**Immediate next quality experiment:** inspect underspecified follow-up grounding before
adding compensating prompt prose. Code inspection shows groundingQuery can use the latest
question alone when followUpDependsOnContext does not recognize its dependence on the prior
topic, even though conversationRequest retains chat history. Test generic comparisons and
superlatives across several subjects, then separately compare context-aware retrieval with
the same prompt and sampler. Do not silently change retrieval during a prompt A/B run.

## Next: reproducible physical-phone baseline

Repair the disposable ModelProbe build configuration: derive a distinct bundle ID per app and
extension target instead of overriding PRODUCT_BUNDLE_IDENTIFIER globally. Keep the visible
special-build name required by Development-Workflow.md and inspect the exact signed app.
Audit probe entitlements and startup so it cannot mutate production App Group/widget state.
Never install or launch the production phone bundle without separate owner authorization.

Use Release optimization in ModelProbe, on the base iPhone 17, one runtime/model at a time.
Compare caller/greedy and recommended sampling with the same public fixtures. Record cold
load, warm first turn, short and long follow-ups, per-pass prompt/decode timings, generated
length, memory, thermal state, and generation failures. Include a short raw decode benchmark
and real retrieval-backed Angrove turns to locate the integration cost. Repeat after warm-up;
record device/OS/runtime build, seed, model hash, context, batch and KV settings. Validate cancel,
background/foreground, reload and sustained multi-turn behavior before proposing a default.
Compare full/compact Bonsai and E4B under matched workload, spacing, charging and starting
thermal conditions. Record thermal-state transitions and throttling, plus energy evidence
where available. Thermal state is not a direct temperature measurement. Prompt shortening
targets prefill/answer work, not the cold cost of reading/loading model weights.

## Highest-value runtime work to test independently

1. **Prompt and history correctness.** Capture rendered prompts only for public eval fixtures,
   compare with the embedded Jinja template, and check that coreference follow-ups retain the
   actual roles/history. The shared system instruction currently calls every model Gemma 4;
   add a truthful model identity through the runtime/model boundary as its own measured change.
   Do not attribute observed context failures solely to model capacity before isolating routing,
   prompt assembly and sampling.
2. **Prefix reuse.** The adapter currently clears the entire context for every generation.
   Measure a stable system-prefix boundary, then implement a bounded in-memory checkpoint for
   that prefix and re-evaluate the changing retrieval/history suffix. Qwen3.5 has recurrent
   hybrid state: restore complete compatible state, not just KV entries or token positions.
   Compare restore against full recomputation with identical batch boundaries; validate no
   cross-conversation leakage, cancellation invalidation, model unload and memory limits.
   Keep cold vs warm measurements separate. Never persist personal prompt caches without a
   deliberate privacy/storage design. [Prism cache guidance](https://github.com/PrismML-Eng/Bonsai-demo/blob/main/PROMPT-CACHE.md).
3. **Metal/prefill configuration.** Inspect actual device logs and benchmark flash attention,
   batch/ubatch and tensor kernels one setting at a time. Pinned e3de715 auto-enables tensor
   API on supported M5/M6/A19/A20 devices; it normally disables it on M4. Confirm the actual
   XCFramework and device path rather than assuming a missing toggle. Source:
   [Metal device initialization](https://github.com/PrismML-Eng/llama.cpp/blob/e3de715/ggml/src/ggml-metal/ggml-metal-device.m).
4. **Prompt size and extra passes.** Use per-call timings to decide whether to reduce repeated
   instructions or reorder stable vs dynamic evidence. Preserve source quality and structured
   validation; measure quality after every change. Avoid weakening retrieval merely to improve
   a speed number. Examine unnecessary retries and answer length as well as raw decode speed.
5. **Speculative decoding.** Start with the integrated MTP-head pack on a bounded fixture set;
   record acceptance rate, added prefill/memory, and total time. Compare with plain decoding for
   actual conversational prompts before adding a separate DFlash drafter. A fast copy benchmark
   is not evidence of a fast philosophical conversation. Preserve correct verification and one
   process-scoped engine/queue; don't add a cloud/server dependency for this work.

## What the paper's speed targets actually mean

Whitepaper Table 3 (tg128, batch 1) reports iPhone 17 Pro Max plain decode: 2B 89.9,
4B 39.8, 9B 22.3 tokens/sec. Table 4 reports 9B 89 tokens/sec for copy-heavy speculative
work; plain is fastest for its everyday phone workload. M5 Pro numbers are a different
hardware target from this M4 Pro. The phone throughput method uses Metal tensor ops on,
flash attention, five repeats; first-token testing uses a 512-token prompt. Our earlier phone
app prompts were around 2.3–2.7K tokens. Match those conditions before claiming a runtime gap
or expecting 90 tokens/sec from ordinary 9B phone conversations.

## Changes and validation

- Recommended sampler is an explicit runtime-init/eval opt-in; existing flags and normal app
  default behavior retain caller sampling.
- Native sampler tests verify presence penalty applies once per token and expires after 64
  tokens, and structured requests stay greedy. The Mac test target links the existing llama
  package directly for these regression tests.
- Eval-only generation recording is disabled for normal runtime use and drained per eval case.
- Results and next experiment selection belong in Angrove-Eval/RESULTS.md and the Bonsai handoff.
