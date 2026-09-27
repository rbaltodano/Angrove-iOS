# Pending `MODEL-INTEGRATION.md` update (plan C10 step 4)

`../Aquinas-Foundations/MODEL-INTEGRATION.md` has uncommitted owner edits, so the promotion
session didn't touch it. Apply these three edits there when E4B merges, then delete this file.

## 1. New checkpoint (after "On-device inline key-term annotation checkpoint — August 8, 2026")

```markdown
### Gemma 4 E4B promotion checkpoint — September 2026

The app's model is now Gemma 4 E4B instruction-tuned, the LiteRT Community standard package
`gemma-4-E4B-it.litertlm` (3,659,530,240 bytes, SHA-256
`0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`). It is not fine-tuned. Its
weights are mixed INT4/INT2/INT8, consistent with quantization-aware training, but Google hasn't
confirmed the provenance, so it's labelled "LiteRT Community", not "QAT". It runs text-only on the
GPU with a 4,096-token KV cache. Evidence: the iOS repo's
`Documentation/Gemma4-E4B-QAT-Progress.md`.

| Measurement (base iPhone 17 unless noted) | E4B | Previous fine-tuned E2B |
| --- | --- | --- |
| Peak physical footprint, 4K context | about 1.15 GB (0.165 × operating cap) | about 2.04 GB |
| Decode speed | about 19–20 tokens/s | — |
| Held-out accuracy, 40 cases (simulator CPU, blind) | 3.85 / 5 | 3.05 / 5 |
| Held-out critical errors | 1 | 9 |
| Structured contracts (C6 diagnostics, latest run) | 14 / 14 | 12 / 14 (both quote-notability cases return truncated JSON; Make Node was malformed in the first run) |

The Google GPU-only package (`gemma-4-E4B-it-gpu`) was rejected: it was jetsammed at 2K and 4K
context on the phone. Rollback is a manifest change back to the E2B values above.
```

Add the sustained-gate (C9) numbers to this table once C9 has run on the phone.

## 2. §2 Current decisions, "Language model" bullet

```markdown
- **Language model:** Gemma 4 E4B (LiteRT Community standard package, `gemma-4-E4B-it.litertlm`,
  not fine-tuned) running on-device through LiteRT-LM, text-only. It replaced the fine-tuned E2B
  in September 2026; see the E4B promotion checkpoint. Fine-tuning E4B is future work under §8.
  The earlier MLX-VLM + LoRA configuration ran only in the retired development backend.
```

## 3. Stale `dynamic_wi8_emb4_afp32` text (around line 209)

The paragraph still presents the `dynamic_wi8_emb4_afp32` E2B export as a candidate that "must pass
… gates before the app manifest or bundled development seed is changed". That package was deployed
and has now been superseded. Append:

```markdown
That package became the deployed E2B model and was superseded in September 2026 by Gemma 4 E4B
(see the E4B promotion checkpoint).
```
