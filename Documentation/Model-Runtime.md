# iOS model runtime and recovery

Read the cross-repository [`MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md)
first. This document records iOS-specific runtime boundaries and validation rules.

## Runtime selection

`AquinasApplicationRuntime` selects `LiteRTAquinasModel` when a verified local package is
available and injects the same `LiteRTAquinasRuntime` into `ModelTaskQueue`. There must be one
process-scoped live engine and queue. When no verified package is installed, the runtime uses
`UnavailableAquinasModel`, which fails every action explicitly. There is no network fallback:
a failed local generation surfaces as a failure and offers retry. `MockAquinasModel` is restricted
to previews and tests.

On-device conversation decoding is deterministic (greedy). That policy dates from the earlier
4-bit E2B checkpoint, which sampling corrupted; the E4B package passed a sampled check in C8, but
the policy hasn't changed. Local decoding currently yields completed text rather than reliable token
deltas. The app may present a safe, question-specific approach summary, but it must never expose
provider scratch work or chain-of-thought.

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

`LiteRTModelManifest.aquinas` selects the standard LiteRT Community Gemma 4 E4B package, not a
fine-tune (merged to `main` in PR #8, 2026-09-29). It runs on the GPU with a 4,096-token KV cache.

- **Activations are forced to F32.** The package's default F16 misread multi-digit numbers on the
  phone GPU ("John 14" answered as John 4). `--litert-f16` restores the default in DEBUG.
- **Vision is on.** The vision encoder loads on the same backend as the main executor, and image
  turns are sent as image content. `--litert-no-vision` turns it off in DEBUG, and image turns
  then become text notes.
  - Simulator CPU evidence (`V1-vision-sim-3`, `-4`): 15/15 diagnostics, and the model read the
    probe picture correctly ("PRUDENCE", red circle). One earlier run (`V1-vision-sim-2`) exited
    without a result or crash report during a later text case; it didn't repeat.
  - **Not yet validated on the phone GPU** (plan step C12): load, memory, real images, and
    whether F32 still holds with vision loaded.
- Audio input isn't wired into the app.
- MTP speculative decoding is off (`--litert-mtp` enables it in DEBUG).

The old fine-tuned E2B package (B0) is retired. Evidence and exact hashes are in the
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
