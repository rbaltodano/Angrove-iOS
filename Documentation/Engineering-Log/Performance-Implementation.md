# Performance implementation — October 6, 2026

This implements the source-audit improvements for the canonical `main` checkout. The owner's
subsequent direction takes precedence: retain the background and decorative animations, and
reveal words twice as fast without imposing a one-second duration cap.

## Changes

| Audit area | Implementation |
| --- | --- |
| Launch assets | The live shell constructs lightweight semantic providers. One serial asset worker loads MiniLM, the corpus, and its indexes. Simultaneous first requests wait behind the same preparation. Preparing, ready, embedding fallback, and grounding fallback are distinct diagnostic states. |
| Embeddings and grounding | Live Core ML predictions, tokenization, and retrieval execute on the worker. Grounding and clustering share one MiniLM instance. Exact-text vector and question/limit caches hold at most 256 and 32 entries. Cancellation skips obsolete queued requests; revision checks reject obsolete graph results. |
| Tree and personal preferences | A serialized persistence worker provides immediate in-memory replacement reads, coalesces pending saves per key, and skips identical encoded tree writes. The startup encryption gate warms reads, conversation seeds, and preferences. Reset and recovery drain/invalidate caches before removing stores. Encryption, schema validation, atomic replacement, migrations, and protected files remain in the existing file stores. |
| Conversation persistence | The process repository preloads a snapshot after encryption validation. Ordinary feature reads use the optimistic cache instead of waiting behind disk writes. Detached completions and stale-page merges follow the existing stable-ID and question-prefix rules. Export/import run off the main actor. Background scene transitions request asynchronous flush barriers under an iOS background task. |
| Graph computation | Live clustering, merging, spanning-tree construction, and overlap relaxation run on a worker from immutable input values. The last visible graph remains until a current revision is ready. Merge pair scores survive until one of the participating clusters changes. Dense Prim retains the best frontier edge per node, reducing spanning-tree work to quadratic selection. Equal-distance edges have a deterministic index tie policy. Identical graph inputs reuse the previous result. |
| Active physics | A spatial grid supplies candidate chip/node pairs. The original nearby overlap/force rules, midpoint pinning, settling, sibling angular forces, and animation cadence remain. Very large/invalid-scale footprints fall back to all pairs rather than omitting valid collisions. Existing title measurement caching remains. |
| Answer presentation | Four words still reveal per batch; the interval changes from 55 ms to 27.5 ms. Initial delay, fade, term underline, footer sequencing, restoration, and reduced-motion behavior remain. Automatic seed/title/quote analysis is background work, behind explicit questions. |
| Exact retrieval | The vector scan iterates existing indices and retains only the best k candidates. It no longer allocates a corpus-sized similarity array or sorts the entire accepted set. Lexical priorities, required terms, source routing, thresholds, corpus indices, and encounter-order distance ties remain. |
| Streaming guards | Script counts and completed 10/16/24-word windows are retained across chunks. Only the unfinished token is rescanned. Adjacent sentence checks retain the last two sentences and the current suffix. The original batch guard remains the reference implementation for chunk-by-chunk parity tests. |
| Attachment previews | UI previews decode with ImageIO on a serial worker, apply image orientation, and choose a bounded aspect-aware thumbnail size for the existing crop. The cache has a 16 MiB cost budget and 64-entry count limit. Original attachment bytes and export/storage formats remain intact. |
| Measurement | `com.angrove.performance` / `AppPipeline` signposts cover asset preparation, embeddings, grounding/ranking, graph computation, relaxation, tree/seed saves, and thumbnails without recording personal text. |

## Audit corrections and boundaries

`runSemanticLayout` has no active caller in this checkout. Its MDS solver was not enabled or
rewritten. The canvas already cached title measurement, so another title cache was unnecessary.

This change does not alter Gemma weights, LiteRT settings, native thinking, speculative decoding,
accuracy thresholds, or the shared runtime's ownership. It does not revive shelved research.
Storage remains the existing encrypted Codable format. A normalized database, external attachment
blobs, approximate retrieval, alternate MDS, lower simulation cadence, and model-setting
experiments were conditional proposals requiring measurements; they are not prerequisites to this
implementation and would introduce separate behavior or migration decisions.

Cold compatibility reads outside the normal startup gate still use a synchronous queue barrier.
A flush cannot guarantee completion after iOS expires its background execution allowance.
The UI keeps original images only through the compatibility image API; both live preview sites use
the bounded thumbnail worker. Per-node sibling angular forces still consider all attached bonds
because spatial culling would change their behavior.

## Verification

Behavior-oriented regressions cover batch/streaming guard parity over different chunk boundaries,
exact retrieval ranking and ties, broad-phase overlap coverage and candidate deduplication,
attachment pixel bounds and reuse, optimistic/durable write ordering, detached conversation merges,
semantic fallback identity, cancellation, and stale graph revisions. Existing queue unit fixtures
select synchronous geometry so they test scheduling independently; a separate regression exercises
the production background graph path.

The first broad parallel run exposed shared process-state interference: corruption fixtures close
`PersonalDataProtection` for subsequent unrelated tests, and heavy work delayed timing fixtures.
Persistence fixture cleanup and the encryption suite's test scope now reopen only empty,
removed test fixtures' protection gates. Use a
clean disposable simulator and `-parallel-testing-enabled NO` for verification involving that
process-wide gate. Keep intentional corruption tests separate from owner app data.

The full serial suite passed 409 tests in 66 suites. Final focused guard/persistence checks
and device handoff are recorded below. Simulator timings
are not evidence of physical-device FPS, inference speed, thermal behavior, or energy savings.
Those require sustained Instruments runs on the base supported iPhone with representative
10/50/100-node libraries and short/long responses, including cancellation, lifecycle transitions,
lock/unlock, and memory pressure. Compare median and tail latency, frame intervals, and peak memory;
retain the current quality gates and encryption protections throughout.

### Final results

- Concrete arm64 iOS27 simulator build succeeded.
- Full serial suite: 409 tests in 66 suites passed (137.859s test execution).
- After the final Unicode boundary and seed-integrity corrections, 94 focused tests in 5 suites passed (2.047s test execution).
- Physical iPhone Debug build and deep/strict code-signature verification succeeded. The exact signed app's display name is **Angrove**; deployment uses the canonical bundle identifier and retains the existing device data container.
- A disposable 375pt iPhone SE simulator showed the empty home and six-child study tree without visible clipping/overlap in light and dark appearance. DeviceInteraction/Simulator accessibility controls were unavailable, so tap navigation, actual attachment presentation, and physical sustained performance were not verified by that visual pass.
- Build products, test logs, result bundles, and screenshots remain local verification artifacts rather than committed application resources.
