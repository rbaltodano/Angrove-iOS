# iOS application architecture

This document describes iOS-owned composition and state. Cross-repository model and persistence
contracts remain in [`MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md).

## Composition and ownership

`ContentView` owns the app shell: global navigation, settings, the global Insight Library canvas,
and handoff into `CurrentConversationView`. It conditionally mounts the conversation screen, so
state that must survive changing pages belongs at the shell level and is passed down through a
binding or durable store—not local `@State` in `CurrentConversationView`.

`CurrentConversationView` owns active conversation and branch presentation, the visible model-task
experience, conversation-scoped definition flow, slash-command handling, and on-device Insight Tree seeding
after each completed response. Its `ConversationSession` owns the conversation list, active
branches, rename/save operations, and ID-addressed response reconciliation. The view retains
presentation state and callbacks into the shell. `NewConversationRequests` is a shell-owned
mailbox of complete typed requests (including prompt metadata, topic, and optional quoted
Insight); consuming a request clears it, so recreating the page cannot replay a handoff.
`ModelTaskQueue` serializes questions, contextual
definitions, tree updates, and Question of the Day consolidation. Cancellation must keep the
visible pending/breathing state in sync.

Submitting a question persists its response placeholder before enqueueing generation. Each job
captures its model and original conversation/branch IDs. Navigation never cancels a question:
a result from an unmounted column is written to its existing persisted slot by those IDs, without
checking the newly displayed thread's message count. The currently mounted conversation reconciles
completed slots from persistence while preserving composer drafts. Snapshot saves also preserve
already completed answers when a stale page still holds an empty slot for the same question.
Streaming, compaction, and
cancellation callbacks may touch a view binding only while that column is visible and still has
the original branch identity. Cleared/deleted response slots are not recreated by late results.


Every Insight Tree is built on-device. The global Insight Library canvas is an in-memory semantic
experience. The conversation tree asks the local model for each turn's subject
(`insightTreeSeedCandidate`), stores accepted subjects in `LocalInsightTreeSeedStore`, and clusters
saved Insights around them with the bundled MiniLM `EmbeddingProvider`. `NLEmbeddingProvider` is a
degraded last resort only when the MiniLM assets fail to load.

Both canvases pass the app's shared `ModelTaskQueue` into `InsightTreeViewModel`. Cluster and
suggestion labels use background `labelInsightTree` jobs (displayed as `Update Insight Tree`),
separate from response-seeding and persisted-refresh deduplication. A cluster's generated
definition stays inside its label job. Blank title/definition placeholders are excluded from
label input; an entirely blank cluster queues nothing. In-flight cluster deduplication survives
foreground preemption, while explicit cancellation releases it and discards late output.

Automatically named Nodes use the nearest useful broader concept, including single-Insight
clusters. `NodeConceptLabelPolicy` rejects normalized member-title copies, superficial wrappers,
and vague catch-all labels; the live model gets one corrective attempt. Conversation seed
prompts use the same broader-concept relationship. On rebuild, an existing cached or seeded Node
whose name repeats a member is relabelled through the queue with its ID, membership, and position
preserved. The new label overrides the seed's presentation and receives a fresh definition.
Explicit Make Node promotions and placed Midpoints retain their intentional titles.

Response formatting is split by responsibility: `ResponseParsing` and `LiveResponseParsing`
prepare completed and incremental text; `ResponseFlowLayout` lays out words;
`CompletedResponseSegments` and `LiveFormattedResponseView` render them; `StreamingMessageView`
coordinates reveal progress and completion. `ResponseTextFormatting` shares Insight-markup
removal while retaining the different emphasis policies for previews and definition context.

The tree canvas retains geometry-dependent interactions and physics. `InsightTreeRevealState`
owns reveal membership and animation tasks, and `InsightTreeSelectionState` owns transient
selection effects. `InsightTreeSelectionOverlay` receives resolved screen positions so rendering
selection lines does not depend on the full graph or physics state.

## Persistence boundaries

Conversation branches and chat blocks are persisted as one Codable snapshot in
`Application Support/Aquinas/ConversationStore/conversations-v1.json`. The file store writes
atomically, keeps up to five rotating JSON backups, and migrates either prior conversation
snapshot from `UserDefaults` on first successful load. `InquiryPersistenceStore` is the
process-facing boundary; `CurrentConversationsStore` is its compatibility name at existing call
sites. All snapshot I/O runs on one serial background queue (`SerializedInquiryStore`): saves
return immediately, loads and imports wait behind queued writes, and the shell flushes the queue
when the scene moves to the background. Saved Insights and identifiers-only coordination stores remain in `UserDefaults`, including
conversation-to-global-Insight membership. See
[`PERSISTENT_MEMORY_IMPLEMENTATION_PLAN.md`](../../Aquinas-Foundations/PERSISTENT_MEMORY_IMPLEMENTATION_PLAN.md)
for the planned SwiftData migration.

There is no server-side persistence. Conversations, Insights, and tree state live only on the
device. (An earlier development topology mirrored tree content to a Mac-hosted SQLite backend; the
app no longer contains that client.)

## Important seams

| Area | Primary location |
| --- | --- |
| App shell and page handoff | `Aquinas-iOS/App/ContentView.swift` |
| Conversation orchestration | `Features/Conversation/CurrentConversation.swift` |
| Transcript and response lifecycle | `Features/Conversation/ConversationComponents.swift` |
| Visible model tasks | `Features/Conversation/ModelTaskQueue.swift` |
| Model status and context controls | `Features/Conversation/ModelControls/`: one app-wide bar (`ModelControlsHost.swift`, mounted by the shell). Pages publish their buttons to it (`InquiryControlDock`, `PageModelControls`, `LibraryModelControls`) and never render a bar of their own. |
| Model boundary and local implementation | `Services/AquinasModel.swift`, `Services/LiteRTAquinasModel.swift` |
| Runtime ownership | `Services/AquinasApplicationRuntime.swift`, `Services/LiteRTAquinasRuntime.swift` |
| On-device tree seeds | `Persistence/LocalInsightTreeSeedStore.swift` |
| Home discovery cards | `Features/Home/HomeDiscoveryCards.swift`, `TodayInHistoryEntries.swift`, `Persistence/GlossedTermStore.swift`, `Persistence/FlaggedQuoteStore.swift` |
| No-model fallback | `Services/UnavailableAquinasModel.swift` |

## Current product constraints

`/compact`, `/clear`, and `/rename` are supported slash commands. A cached contextual definition must
open immediately even while model work is active; queue a definition only on cache miss. The
context control is a non-spinning gauge, while Model Status describes active work. Question of the
Day generation is background consolidation work and remains queued when an active conversation is
opened.
