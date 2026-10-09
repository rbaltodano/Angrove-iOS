# iOS model runtime and recovery

Read the cross-repository [`MODEL-INTEGRATION.md`](https://github.com/rbaltodano/Angrove-Foundations/blob/main/MODEL-INTEGRATION.md)
first. This document records iOS-specific runtime boundaries and validation rules.

## Launch model

- **Weights:** Stock instruction-tuned Gemma 4 E4B LiteRT Community package, `gemma-4-E4B-it.litertlm`
  (3,659,530,240 bytes, SHA-256 `0b2a8980…`), F32 GPU activations, MTP off, native thinking off.
  The weights are **not fine-tuned**.
- **Voice:** the default Scholarly personality prompt (the "learned friend" voice) in
  `LiteRTAngroveModel.personalityInstruction`.
- **Identity:** conversation and internal task prompts identify the model as Google's open-weight
  Gemma 4 running through the Angrove harness. Angrove supplies the study role and app context;
  it is not a separate proprietary model. Identity is explained when relevant or requested.
- **Historical phone observations:** sealed set 2, 36/40, and held-out, 35/40, on an iPhone 17
  (2026-10-01), recorded in the private eval kit’s session summary. The original raw run folders
  were lost, so these are not the public case study’s headline evidence or a fresh release gate.
  [The public evaluation report](Evaluation.md) uses four preserved simulator comparison runs.
- **Fine-tuned voice (post-launch):** a LoRA tune keeps accuracy at INT8 (6.6 GB, too large),
  but every phone-sized conversion so far lost speed, memory headroom, or accuracy. Next step:
  quantization-aware fine-tuning. See `Aquinas_Backend` `docs/Aquinas-Voice-Dataset.md`.

## Runtime selection

`AngroveApplicationRuntime` selects `LiteRTAngroveModel` when a verified local package is
available and injects the same `LiteRTAngroveRuntime` into `ModelTaskQueue`. There must be one
process-scoped live engine and queue. When no verified package is installed, the runtime uses
`UnavailableAngroveModel`, which fails every action explicitly. There is no network fallback:
a failed local generation surfaces as a failure and offers retry. `MockAngroveModel` is restricted
to previews and tests.

On-device conversation decoding is deterministic (greedy). That policy dates from the earlier
4-bit E2B checkpoint, which sampling corrupted; the E4B package passed a sampled check in C8, but
the policy hasn't changed. Local decoding currently yields completed text rather than reliable token
deltas. When a caller passes `onThought`, `streamText` sends `extraContext: ["enable_thinking":
true]`, which makes the Gemma 4 chat template prepend `<|think|>`; LiteRT-LM then streams the
model's reasoning in each chunk's `channels["thought"]`, separate from the answer text. Only the
first conversation-answer pass can enable it; retries, audits, and structured calls do not.
`LiteRTAngroveModel.usesNativeThinking` gates it and is **off** by default: on held-out and
sealed-1 it left accuracy unchanged (74/80 either way) and roughly doubled answer time (23 s to
44–48 s median in the simulator; Angrove-Eval runs `T2-*`, 2026-10-02). DEBUG builds opt in with
`--litert-native-thinking`; the eval batch's `--litert-eval-thinking` implies it.

## Insight Tree runtime

Conversation trees are seeded on-device: after a completed answer, a background
`.updateInsightTree` task asks the local model for the turn's subject, and bundled MiniLM
similarity decides whether it becomes a new Node Concept. Saved Insights cluster around those
seeds in the same pass.

## History: the development backend

Earlier builds could call a Mac-hosted FastAPI/MLX service (`Aquinas_Backend`) for generation,
Insight Tree persistence, and Home discovery cards. That client code has been removed; the app
makes no network requests for model or tree work. `Aquinas_Backend` remains offline tooling for the
grounding corpus, model conversion, and evaluation.

## Model package and device safety

Current `main` selects `gemma-4-E4B-it.litertlm` in `LiteRTModelManifest.angrove`. The stock
LiteRT Community package is not an Angrove fine-tune. Production settings use the GPU with
F32 activations, a 4,096-token context, greedy decoding, native thinking off and MTP off.
The manifest is authoritative for the exact byte count and SHA-256; see
[development setup](Development-Setup.md).

The September 27 C9 latency gate failed under its frozen protocol. Later E4B/F32 integration
and quality fixes do not retroactively turn that trial into a pass or certify all release gates.
The dated [migration ledger](Gemma4-E4B-QAT-Progress.md) and
[post-C9 diagnostics](Gemma4-E4B-Post-C9-Diagnostics.md) preserve that history. Keep current
model selection separate from historical promotion criteria and physical-device observations.

Lifecycle rules the runtime enforces (see the C7 evidence):
- The stall watchdog ignores time the process spent suspended.
- After a stalled or failed generation, new native work waits (bounded) for the abandoned native
  stream to end; it is never cancelled natively.
- A new engine loads only after the previous engine's native delete has finished (bounded wait).

The local package is a large, gitignored artifact. Do not commit models, generated corpora, or
device data. Simulator inference is useful for iteration but does not replace real-device
memory, thermal, lifecycle, latency, or quality validation. The bundled framework supports arm64
simulators only; use a concrete arm64 destination.

Before device model experiments, back up the app's data. Do not use `devicectl` with
`--remove-existing-content true` against the production bundle.
