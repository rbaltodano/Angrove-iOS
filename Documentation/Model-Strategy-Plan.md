# Angrove on-device model strategy: biggest reliable model in about 4 GB

> Status: proposal, 2026-09-28. Written after reviewing open-source practice and published
> benchmarks, with nothing about the current E4B work treated as fixed. Sources are at the end.
> Third-party benchmark numbers (blogs, aggregators) are marked **(secondary)** and must be
> re-measured on our eval before any decision rests on them.

## TL;DR

1. **Biggest win available today, no model change:** turn on Gemma 4's built-in multi-token
   prediction (MTP). Our E4B file already contains the drafter. Google reports up to **2.2×
   decode on E4B**; we ship it switched off (`enable_speculative_decoding: false`).
2. **Prompt size:** about **2,300 tokens per question** (corrected; an earlier draft
   double-counted and said about 4,000). About 1,500 of that is standing instructions. Trimming
   them saves roughly 1–1.5 s of an 8.2 s answer on the phone, so it's worth doing after launch
   rather than before.
3. **Pin down memory before choosing models.** Google's own card lists E4B on an iPhone 17 Pro
   GPU at **3.38 GB**; we measured 1.1–1.2 GB with `phys_footprint`. The truth decides whether
   a bigger model can fit at all. Measure it with the system's jetsam counters on a release
   build.
4. **Then run a model bake-off, cheaply, on the Mac.** We already recorded every C8 prompt
   exactly as rendered, so candidate models can replay the same 40 held-out prompts through
   llama.cpp or MLX and be scored by our existing scorer, with no app integration. Candidates:
   Gemma 4 E4B (control), Qwen3.5-4B, Qwen3.5-9B at about 3 bits, Gemma 4 12B at about 2–3 bits.
5. **Only integrate a new runtime if a candidate clearly beats E4B on our eval.** LiteRT-LM is
   the fastest and leanest engine on iPhone in independent tests, so leaving it costs speed and
   memory. That bar should be high.
6. **Fine-tune last,** on the winner, with a recipe that re-quantizes carefully (QAT or
   distillation-aware), because naive LoRA-then-quantize discards Google's QAT benefit.

## What the field does to fit big models in small memory

| Technique | What it buys | Maturity on iPhone | Relevance to us |
| --- | --- | --- | --- |
| **Quantization-aware training (QAT)** | 2–4 bit weights with little loss; Google's E4B "mobile" mix scores 98.8% top-1 agreement with bf16 (secondary) | Shipped by Google for Gemma 4 | We already use it: our E4B package's INT2/INT4/INT8 mix matches the published E4B mobile scheme |
| **Speculative decoding / MTP** | 1.6–3× decode with *identical* output | In LiteRT-LM since v0.11; needs a post-May-2026 package | **Unused, already in our file.** Top priority |
| **Mixed-precision 2/3-bit PTQ (llama.cpp IQ/K-quants, MLX mixed-bit, DWQ)** | 8–12B models in 3.5–4.5 GB | Works; IQ quants run slowly on Apple GPUs (codebook lookups); MLX DWQ recovers about 0.6 bit of quality | Route for a 9–12B candidate |
| **Distillation-aware quant (MLX DWQ)** | "4-bit behaves like about 4.6-bit" | MLX-native | Best way to re-quantize after a fine-tune |
| **Rotations (QuaRot, SpinQuant, PolarQuant)** | Remove outliers so 4-bit (and KV) quantize cleanly | Used by Meta for Llama 3.2 mobile | Useful if we produce our own quants |
| **Ternary / 2-bit QAT (ParetoQ, BitNet)** | 2-bit ties or beats 4-bit at equal memory | Needs training from scratch or heavy QAT | Research-grade for us; not a first move |
| **KV-cache quantization (INT8/INT4, TurboQuant)** | 50–75% smaller KV cache | Engine-dependent | Small win at 4K context; matters if we grow context |
| **Hybrid linear attention (Qwen3.5 Gated DeltaNet)** | About 75% of layers keep no growing KV cache | llama.cpp and MLX support; LiteRT-LM has Qwen3.5 0.8–4B only | Makes 9B-class context cheap |
| **Per-layer embeddings, memory-mapped (Gemma 4 E-series)** | Big embedding tables stay on flash, not RAM | Built into Gemma 4 E2B/E4B | Why E4B is "8B total, 4.5B effective" but RAM-light |
| **Dropping unused modalities** | Our E4B file carries about 390 MB of audio, vision and drafter we don't use (keep the drafter for MTP) | Container rewrite | About 340 MB off download size; little RAM effect (loaded on demand) |
| **Engine choice** | Same model: LiteRT-LM 61 tok/s at 497 MB vs MLX 49 tok/s at 3.0 GB vs llama.cpp 39 tok/s (E2B, iPhone 17 Pro) (secondary) | — | Stay on LiteRT-LM unless a model it can't run wins big |
| **Apple Foundation Models + adapter** | About 3B system model, **zero app memory**, LoRA adapter about 160 MB | iOS 26+ | Useful baseline and fallback; likely weaker than E4B |

## Candidate models for a 4 GB memory budget

| Candidate | Weights in memory (est.) | Why consider | Main risk |
| --- | --- | --- | --- |
| **Gemma 4 E4B (current, Google mobile QAT)** | About 2.3 GB decoder; embeddings memory-mapped | Proven in our app; C8 quality win; faithful grounding; LiteRT-LM speed; MTP ready | Reasoning benchmarks trail Qwen3.5-4B (secondary) |
| **Qwen3.5-4B** (LiteRT-LM artifact exists) | About 2.3 GB at INT4 | Reported MMLU-Pro 79 vs E4B 69, GPQA 76 vs 59 (secondary, likely with thinking on) | Advantage may need long "thinking" (2–5× tokens, slower); new template and parsing work; Gemma may ground more faithfully |
| **Qwen3.5-9B at about 3 bits** | About 3.6–4.0 GB | Beats Gemma 4 12B on MMLU-Pro/GPQA (secondary); linear attention keeps KV small | Not in LiteRT-LM; needs llama.cpp or MLX Swift (slower, heavier); decode maybe 8–12 tok/s (estimate) |
| **Gemma 4 12B at about 2–3 bits** | About 3.5–4.5 GB | Largest Gemma; same family, template and prompts | No Google mobile QAT for 12B; our own 2–3 bit PTQ loses quality; the earlier 12B research was shelved for size |
| **Apple on-device model + adapter** | 0 (system-owned) | No memory cost, no download | Smaller model; adapters retrain per OS model update |

**Budget math (rule of thumb).** On an 8 GB iPhone, the increased-memory-limit entitlement
(which we have) lets a foreground app use roughly 6 GB before jetsam. A 4 GB model target
leaves about 2 GB for the app, MiniLM, KV cache and the OS's other apps, which is what keeps
music playing. Decode speed is bound by memory bandwidth, so every extra GB of weights costs
speed: a 4 GB model decodes about half as fast as a 2 GB one on the same engine.

## Plan

### Phase 0: quick wins on the current model (about 1–2 days, low risk)

1. **Resolve the memory truth.**
   - Install the ready Release build (it skips the DEBUG model hash, the likely cause of the
     "music stops" report).
   - Measure the jetsam resident count and `phys_footprint` side by side, with music playing.
   - Outcome: the real footprint of E4B, which sets the budget for everything below.
2. **Enable MTP.**
   - Set speculative decoding in `EngineConfig` (LiteRT-LM advanced settings), confirm the
     drafter section loads on Metal, and check outputs are unchanged under greedy decoding.
   - Measure decode tok/s on the phone.
   - Expected: about 20 → 35–45 tok/s decode.
3. **Put the prompt on a diet** (model-independent; coordinate with the owner's system-prompt
   work on `main`).
   - Move standing rules into the system preface once, rather than re-sending them per turn.
   - Trim register examples.
   - Cap retrieved passages by relevance score instead of a fixed count.
   - Target: at most 1,500 tokens for a first-turn short question.
   - Gate: the C8 held-out objective score doesn't drop.
4. **Optional cleanups:**
   - KV-cache INT8, if LiteRT-LM exposes it for this package.
   - A text-only repackage (drop audio and vision, about 340 MB), if a container rewrite tool
     exists.

Expected result (revised): MTP could cut decode time roughly in half on the phone GPU. The
prompt trim saves about 1–1.5 s. About 2.8 s of each answer is still unattributed and needs a
phone benchmark run before promising a number.

### Phase 1: model bake-off on the Mac (about 3–4 days, no app changes)

1. Build a small Python harness. It replays the 40 recorded held-out prompts
   (`C8-*-held-2/litert-generations.jsonl` holds each exact rendered prompt, re-rendered per
   model's chat template) through llama.cpp and MLX, then runs our existing `score_objective.py`.
   The blind rubric review covers only the top two.
2. Candidates:
   - E4B (control, same prompts);
   - Qwen3.5-4B, with thinking off and a separate thinking-on arm (reported with its token cost);
   - Qwen3.5-9B at about 3 bits (MLX DWQ or llama.cpp Q3_K);
   - Gemma 4 12B at about 2.5–3 bits.
3. Record quality, output tokens, and Mac-side memory. Phone speed matters only for survivors.
4. **Decision rule** (frozen before runs): a challenger must beat E4B by a clear margin on the
   held-out objective score and critical errors to justify a runtime change. Otherwise E4B
   stays and the effort goes to Phase 3.

### Phase 2: integrate a challenger only if it wins (about 1–2 weeks)

1. Add a second runtime behind the existing `ModelRuntimeDriver`/`AngroveModel` seam (MLX
   Swift is likely the better iPhone path for a hybrid 9B). Keep one process-scoped engine, per
   AGENTS.md.
2. Rerun C6 (contracts), C7 (lifecycle) and the P2 phone checks: music keeps playing, warm
   answer time, memory, background and memory-warning recovery.
3. Keep E4B as the rollback.

### Phase 3: fine-tune the winner (after it's in the app)

1. LoRA on the Angrove voice and behavior data.
2. Re-quantize carefully:
   - Gemma: QAT-aware fine-tune (train on the QAT checkpoint, then export with the LiteRT-LM
     mixed recipe). Naive QLoRA on a QAT checkpoint discards its calibration.
   - MLX: follow the LoRA with DWQ distillation against the fine-tuned bf16 teacher.
3. Gate: beat the un-tuned winner on held-out quality with no latency or memory regression.

## What carries over from the E4B work

Everything useful carries over:
- the eval set and scorer;
- the lifecycle fixes and trace harness;
- the phone runners;
- the memory and latency methodology.

What doesn't carry over is C9's latency budgets, now superseded by the P2 gate. Nothing here
requires starting from scratch unless Phase 1 finds a clearly better model.

## Sources

- Apple-silicon LLM benchmarks across LiteRT-LM, MLX, llama.cpp, Core ML (iPhone 17 Pro):
  https://github.com/john-rocky/apple-silicon-llm-bench
- Gemma 4 E4B LiteRT-LM model card (iPhone 17 Pro GPU: 1,189 prefill / 25.1 decode tok/s,
  3,380 MB; MTP needs packages after May 5, 2026):
  https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
- LiteRT-LM MTP speedups (E2B 1.6×, E4B 2.2×): https://www.infoq.com/news/2026/06/google-litertlm-gemma4/ ,
  https://ai.google.dev/gemma/docs/mtp/overview
- Gemma 4 QAT and mobile mixed-precision schemes:
  https://blog.google/innovation-and-ai/technology/developers-tools/quantization-aware-training-gemma-4/ ,
  https://unsloth.ai/docs/models/gemma-4/qat (secondary),
  https://huggingface.co/google/gemma-4-E2B-it-qat-mobile-transformers
- Gemma 4 12B LiteRT-LM files (6.55 GB): https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm
- Gemma 4 vs Qwen3.5 benchmarks (secondary): https://gemma4all.com/blog/gemma-4-vs-qwen-3-5-benchmarks
- Qwen3.5 hybrid attention: https://huggingface.co/blog/mlabonne/qwen35
- MLX quantization incl. DWQ (secondary):
  https://medium.com/@michael.hannecke/mlx-quantization-on-apple-silicon-dynamic-quant-vs-awq-vs-gptq-vs-dwq-8b2a5af2b53f
- llama.cpp IQ quants slow on Apple Silicon: https://github.com/ggml-org/llama.cpp/discussions/5617
- ParetoQ / 2-bit QAT: https://arxiv.org/pdf/2606.10531 , https://export.arxiv.org/pdf/2502.02631
- KV-cache quantization on Apple Silicon: https://arxiv.org/pdf/2605.05699
- iOS increased-memory-limit entitlement: https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en
- Apple Foundation Models adapters: https://developer.apple.com/apple-intelligence/foundation-models-adapter
- QLoRA on QAT checkpoints loses calibration: https://github.com/unslothai/unsloth/discussions/6389
