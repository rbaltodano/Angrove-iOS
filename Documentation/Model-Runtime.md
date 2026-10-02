# iOS model runtime and recovery

Read the cross-repository [`MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md)
first. This document records iOS-specific runtime boundaries and validation rules.

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

On `feature/gemma4-e4b-qat`, `LiteRTModelManifest.angrove` selects the standard LiteRT Community
Gemma 4 E4B package, not a fine-tune. It runs text-only on the GPU with a 4,096-token KV cache.
An earlier owner-approved build from this branch remains installed on Ry as a personal trial.
**The migration is not promoted:** C9 failed the frozen physical-device latency gate, C10 is
blocked, and `main` still selects the fine-tuned E2B package. Do not infer a release decision
from the branch manifest or the phone installation. The manifest comment records B0 rollback
values. Evidence, exact hashes, and the next diagnostic plan are in the
[E4B migration ledger](Gemma4-E4B-QAT-Progress.md) and
[post-C9 diagnostics](Gemma4-E4B-Post-C9-Diagnostics.md).

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
