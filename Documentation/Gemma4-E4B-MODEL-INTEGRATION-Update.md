# Proposed Foundations model-integration update — review draft

> Updated 2026-09-27 after C9. This replaces the earlier promotion draft, which described E4B
> as shipped before its phone gate had passed. **Do not apply the old promotion text.**
> `../Aquinas-Foundations/MODEL-INTEGRATION.md` has owner edits; reconcile with that file's
> current work before changing it. This draft is for Claude's review, not evidence of promotion.

## Suggested dated checkpoint

Add a dated checkpoint to Foundations once the owner is ready to reconcile its uncommitted edits:

```markdown
### Gemma 4 E4B evaluation checkpoint — September 27, 2026

The standard LiteRT Community Gemma 4 E4B package
(`gemma-4-E4B-it.litertlm`, 3,659,530,240 bytes, SHA-256
`0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`)
was evaluated as a text-only, GPU, 4,096-context replacement for the fine-tuned E2B package.
Its QAT provenance remains unconfirmed; label it “LiteRT Community,” not “QAT.” The smaller
GPU-only E4B package was rejected after phone jetsam at 2K and 4K context.

On the 40-case held-out set, simulator CPU scoring favored standard E4B: mean accuracy
3.85 versus 3.05 for E2B; critical failures 1 versus 9 after the owner-delegated review.
The held-out set has not been repeated on the phone GPU. The standard E4B package passed the
early phone memory screen, but **failed** the frozen sustained gate at its first valid cold
phone trial: load 12.824 s versus a 12 s limit, and short answer completion 21.910 s versus
a 4 s limit. One trial is enough to make the planned five-trial nearest-rank p95 fail, but
no five-sample p95 is claimed. Peak physical footprint was 1.088 GB in that trial; thermal
state stayed nominal. Sustained turns, OS background recovery, and phone GPU quality remain
unverified.

The E4B branch was not merged or promoted. Main still declares the fine-tuned E2B model.
An earlier owner-approved E4B build remains on the owner's phone only as a personal trial.
The iOS migration ledger and `Gemma4-E4B-Post-C9-Diagnostics.md` contain the run IDs,
commands, frozen criteria, known limits, and follow-up plan. A new promotion decision needs
new criteria declared before its own run; the failed C9 result remains on record.
```

## Current model decision in §2

Keep §2's active language-model decision on the fine-tuned E2B while `main` still uses it.
Mention the E4B evaluation checkpoint as an unpromoted trial if useful. Do **not** replace
§2's active model with E4B based on the branch manifest or phone installation.

## Historical `dynamic_wi8_emb4_afp32` paragraph

The old paragraph still calls the E2B `dynamic_wi8_emb4_afp32` export a candidate that must
pass gates before the manifest changes. It later became B0, the model declared by `main`.
Correct that historical tense independently of any E4B promotion decision. For example:

```markdown
The `dynamic_wi8_emb4_afp32` E2B export later became the app's fine-tuned E2B baseline.
Gemma 4 E4B was evaluated in September 2026 but did not pass its first physical-device
promotion gate; see the E4B evaluation checkpoint.
```

## Do not carry forward from the superseded draft

The previous version claimed E4B was the app's promoted model and said to add sustained
numbers after C9. Both statements are obsolete. A future successful promotion should update
Foundations again with its own candidate identity, phone quality result, complete stability
measurements, and explicit decision.
