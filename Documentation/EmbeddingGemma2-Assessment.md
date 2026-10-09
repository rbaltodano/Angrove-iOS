# EmbeddingGemma 2 assessment for Angrove

Assessed October 7, 2026. Scope: announcement and documentation review, current app source and
asset inspection. No model download, benchmark, runtime upgrade, or production behavior change.

**Status: deferred until after launch by the owner on October 7, 2026.** Evaluation and
implementation are post-launch work; retain MiniLM for the launch checkpoint. Tracked in
[Post-Launch Features](https://github.com/rbaltodano/Angrove-Foundations/blob/main/POST-LAUNCH-FEATURES.md#embeddinggemma-2-semantic-retrieval-upgrade).

Post-launch recommendation: evaluate the **270M text-only model** as a replacement for MiniLM
grounding retrieval. Ship only after an app-specific quality and device comparison. Decide Insight
Tree migration separately. Defer the multimodal packages until a concrete media feature needs them.

## What Google released

Google announced EmbeddingGemma 2 on October 6. It is an on-device embedding model for retrieval
and similarity, complementary to the Gemma 4 conversation model. The full model supports text,
images, audio, and video. Google says its multilingual text performance largely matches the
first EmbeddingGemma; the headline improvement is multimodality and code retrieval. There is no
published comparison against our MiniLM deployment on theological/philosophical questions.
[Announcement](https://blog.google/innovation-and-ai/technology/developers-tools/embeddinggemma-2/)

The model is Apache 2.0 licensed, supports more than 100
languages and an 8,192-token input window, and produces 768-dimensional vectors with supported
128/256/512-dimensional truncation. Full-precision multilingual MTEB scores are 61.36 versus
61.15 for its predecessor; those scores do not establish quantized app quality.
[Google model card](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2)

| Published LiteRT package | Parameters | Download | Fit for current app |
| --- | ---: | ---: | --- |
| Text | 270M | 165 MB | First candidate |
| Text + vision | 440M | 388 MB | Future image/document search |
| Full multimodal | 740M | 485 MB | Future audio/video search |

The text package uses QAT int4 transformer and embedding weights. Its published iPhone 18 Pro
results are 11.6 ms GPU / 41.8 ms CPU for text, with about 85 MB / 84 MB measured footprint.
These use the 128-token signature, five-iteration averages and cached loading; they are not
cold-start, longer-input, base-iPhone-17, or simultaneous-E4B results.
[LiteRT text package and benchmark methodology](https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm)

## Where it could help us

The live app shares one Core ML MiniLM embedder between grounding and semantic features through
`SemanticAssetService`. Query inference currently uses a fixed **128-token input** and returns
384 values (`MiniLMEmbedder.swift`). The bundled corpus has **51,836 passages**, verified from
the JSON and binary size, rather than the older approximate 41k in a source comment. Its vector
file occupies 79,620,096 bytes. The MiniLM source package occupies 89,938,306 bytes; that is a
source asset measurement, not installed compiled size or RAM.

| Use | Potential benefit | Confidence before testing |
| --- | --- | --- |
| Answer grounding | Better matching of paraphrases and conceptual questions could deliver more relevant primary-source evidence | Worth evaluating; improvement unmeasured |
| Longer questions and follow-ups | More input capacity can reduce the current query truncation problem | Capability confirmed; quality and latency need measurement |
| Insight Tree and Home relationships | Better conceptual separation could improve membership, deduplication, connections and candidate selection | Uncertain; broader associations can also merge distinct concepts |
| Multilingual questions | Cross-language retrieval over the existing corpus | Promising future use; domain-language accuracy unmeasured |
| Image/audio/video retrieval | Search study materials or recordings across media | Valuable only with corresponding product features |

The September 30 quality triage and later source changes establish that evidence delivery is a
material part of answer quality. However, our failures include absent evidence, incomplete
article context, mistaken referents, and generated-answer errors. An embedding replacement can
improve ranking; it cannot supply missing sources or guarantee that Gemma reads evidence correctly.
See `Gemma4-E4B-Quality-Triage.md`.

Keep the existing retrieval layers: curated aliases, scripture chapter lookup, authority and
subject sections, named-source constraints, and Summa answer reconstruction. Those solve exact
source and evidence-assembly problems independently of the semantic model. The main opportunity
is improving the semantic ranking that fills remaining slots.

## Integration scope and risks

1. **Runtime compatibility first.** We vendor LiteRT-LM 0.14.0, with local lifecycle changes.
   Neither its Swift sources nor exported headers expose an embedding engine. Google released
   Swift EmbeddingGemma 2 support in 0.18.0. Evaluate upgrading the existing runtime while
   preserving our patches and the single generation-engine ownership rule. A managed embedding
   engine is a separate semantic service; its resource scheduling needs an explicit design.
   [0.18.0 release](https://github.com/google-ai-edge/LiteRT-LM/releases/tag/v0.18.0)
2. **Generalize the semantic boundary.** `EmbeddingProvider` is already replaceable and versioned,
   but `SemanticAssetService` and `MiniLMGroundingProvider` depend directly on `MiniLMEmbedder`.
   Add an internal embedding interface with explicit retrieval-query and symmetric-similarity
   roles. Keep one shared embedding model and bounded caches. Preserve generation queue/lifecycle
   behavior and test memory contention with E4B.
3. **Rebuild the corpus vectors.** Re-embed all 51,836 passages offline using the chosen model,
   document format and output dimension. Preserve passage order, IDs, chunk locators, source
   metadata and citation behavior. Replace the store's hardcoded 384 with validated manifest
   metadata including model revision, runtime/quantization, task formatting and dimension.
4. **Calibrate retrieval.** The current distance floor 0.45 and corroboration policy belong to
   MiniLM. Re-select them using relevant and irrelevant questions rather than copying numbers.
   Keep legitimate abstentions when evidence is absent.
5. **Migrate tree vectors separately.** If tree quality wins, change the embedding version and
   recompute cached Insights, seeds and centroids. Recalibrate membership, seed equivalence,
   connections and candidate selection. Preview changed groupings and migration duration on real
   saved data; do not compare MiniLM vectors with EmbeddingGemma vectors.
6. **Update documentation and verification.** Update Foundations' model/tree contracts, the app's
   dimension-specific guide text, corpus export tooling and focused tests when implementing.

Task formatting needs a compatibility check: Google's model card specifies distinct query and
document formats, plus symmetric clustering/similarity formats. The new LiteRT guide currently
shows different prefix strings. Verify the selected package's actual preprocessing against the
reference implementation, freeze it in the manifest, and use the same pipeline for corpus export
and phone queries. Do not assume retrieval embeddings are interchangeable with tree embeddings.
[Model formatting](https://huggingface.co/google/embeddinggemma-2),
[LiteRT embedding guide](https://developers.google.com/edge/litert-lm/embedding_models)

Prefer the existing LiteRT integration over adding MediaPipe initially. Google also documents a
[MediaPipe iOS embedder](https://developers.google.com/edge/mediapipe/solutions/retrieval/universal_embedder/ios),
but introducing a second framework can complicate dependency and native-runtime ownership.
Do not assume shared tokenizer architecture automatically shares memory with our current E4B engine.

## Evaluation and decision

Start with unchanged passage boundaries and generation settings to isolate embedding quality.
Compare MiniLM with quantized EmbeddingGemma 2 at 256d and 768d; use 768d as the quality reference.
At unchanged float32 storage, 256d makes our vector file 53,080,064 bytes; 768d makes it
159,240,192 bytes. The advertised reduction is relative to EmbeddingGemma's native 768d, whereas
our baseline is 384d. At 256d, adding the 165 MB model and removing the approximately 90 MB
MiniLM source package gives a rough net source-asset increase of **49 MB**, before compiled-model,
framework, manifest, and packaging differences. Measure actual installed size.

Reuse existing retrieval cases for development and add fresh held-out topic families. Include
prudence, conscience/synderesis, essence/existence, justice, scripture narratives, councils,
named citations, ambiguous follow-ups, false premises and irrelevant topics. Judge passage
relevance and whether the delivered evidence includes the actual answer, not merely a related
heading. Compare raw semantic recall/ranking and final layered retrieval, then generation quality
with identical prompts and settings. Evaluate tree pairs and grouping independently.

Proposed promotion criteria, to freeze before running:

- At least a 5 percentage-point gain in held-out answer-bearing evidence delivery, with no
  increase in confidently irrelevant grounding and no named-source/citation regression.
- No regression in blind end-to-end answer quality or unsupported claims.
- Base iPhone 17 p95 warm semantic requests within 100 ms and no more than 100 ms additional
  time-to-first-token versus MiniLM; separately report cold preparation and migration costs.
- No crash, jetsam, duplicate generation engine, abandoned-call/reload overlap or lifecycle
  regression with E4B resident. Measure peak combined footprint, sustained thermals, cancellation,
  background/resume and memory-warning behavior. Set the numerical memory margin from a current
  measured baseline before testing.
- Tree adoption additionally requires equal or better held-out relationship judgments, stable
  persisted-data migration and no unacceptable merging of distinct philosophical concepts.

Planning estimate, not a commitment: **2–4 engineering days** for a useful comparison and device
spike, **another 3–6 days** for production grounding integration if it passes, and **2–4 additional
days** for tree calibration/migration. Runtime incompatibility or generation regressions could
extend this. Stop after evaluation if the improvement is marginal.

Owner decision, October 7, 2026: **defer evaluation and implementation until after launch.** The
scope above is retained for a future text-only evaluation, conditional grounding implementation,
and a separate Insight Tree decision. This is a plausible quality upgrade, not a launch requirement
or a fix for every remaining model issue.
