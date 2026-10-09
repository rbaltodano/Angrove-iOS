# iOS application architecture

This document describes iOS-owned composition and state. Cross-repository model and persistence
contracts remain in [`MODEL-INTEGRATION.md`](https://github.com/rbaltodano/Angrove-Foundations/blob/main/MODEL-INTEGRATION.md).

`LibraryListeningStore` owns encrypted per-work listening bookmarks and the most recent work ID
under `aquinas.library.listening.v1` in `PrivatePreferences`. `ResponseSpeechPlayer` checkpoints
the complete-reader word index on pause/stop and every five seconds during playback. Finishing
a page advances the bookmark to the next paragraph, or the end of the edition. A cached
`LibraryListeningIndex`, built alongside the document off the main actor, translates sparse
paragraph/word IDs into progress across the whole edition. Library navigation carries the saved
word and an explicit start-listening intent; opening a bookmark alone never starts audio.

## Composition and ownership

`BootPresentation` keeps the shell mounted beneath a launch mask while startup stores and the
selected destination are restored. The dots fade in while the initial painted-leaf sprite
fades in from blur over 0.5 seconds. It then plays the five sprites once, with the transparent
dotted background rotating behind them. The app title is centered 24 points below the dot
grid and shares the marks’ entrance and exit fades. Once ready, the grown leaf fades out into blur and
the dots fade out together over 0.5 seconds, then it reveals the whole destination
from top to bottom through a gradient spanning 120% of the viewport. During the 1.5-second
reveal, the destination rises 32 points into place using the `(0.55, 0, 0.17, 1)` timing curve
shared by the wipe. Readiness is UI restoration, not completion of background model tasks.
The launch presentation does not replay on navigation or foregrounding. Reduce Motion uses
a static grown leaf and a uniform fade. The system launch screen uses `LaunchCanvas`, whose
light/dark values mirror `AngroveTheme.Colors.canvas` to avoid a pre-render background flash.

`ContentView` owns the app shell: global navigation, settings, the global Insight Library canvas,
and handoff into `CurrentConversationView`. It conditionally mounts the conversation screen, so
state that must survive changing pages belongs at the shell level and is passed down through a
binding or durable store—not local `@State` in `CurrentConversationView`.

The departing conversation receives `isConversationPageDeparting` until the shell removes it.
Question editors pause UIKit styling writes and command display links; question and response
geometry reporters pause presentation updates. The shell composites the thread before applying
its fade/offset and prevents that outer animation from animating internal thread state.
Model generation and persistence continue through the shared queue.

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
Branch pages use bindings resolved by conversation and branch IDs. Writes from a removed page
(including delayed response reveals and editor blur) cannot replace a new conversation's branch
or a different branch at the same array position.


Automatic conversation naming shares the first answer's tree-update job. Once seed processing
finishes, `AngroveModel.conversationTitle(for:)` names the initial question. `ConversationSession`
rechecks persisted conversation/branch identity, question, and title eligibility before saving
only the title, keeping composer drafts and manual renames intact even after navigation. Stale
page saves preserve an already generated title just as they preserve completed answers.

Completed-turn tree analysis captures immutable work directly in the shared queue, independently
of page-local state. Multiple completed turns retain separate jobs. Persisted seed change
notifications refresh a currently mounted conversation tree even when the generating page
instance has gone away. Saved Insight content and IDs override older copies in response markup;
a matching Node label does not hide the saved chip.

Every Insight Tree is built on-device. The global Insight Library canvas is an in-memory semantic
experience. The conversation tree asks the local model for each turn's subject
(`insightTreeSeedCandidate`), stores accepted subjects in `LocalInsightTreeSeedStore`, and clusters
saved Insights around them with the bundled MiniLM `EmbeddingProvider`. `NLEmbeddingProvider` is a
degraded last resort only when the MiniLM assets fail to load.

Both canvases pass the app's shared `ModelTaskQueue` into `InsightTreeViewModel`. Cluster and
suggestion labels use background `labelInsightTree` jobs (displayed as `Update Insight Tree`),
separate from response-seeding. Local bookmark/seed snapshot refreshes bypass the generative queue
and await matching-provider embeddings before advancing the canvas presentation revision. Cluster
ownership is persisted per tree scope; a seed remains a membership anchor as its members change.
Initial label and child
generation starts from the mounted tree's `.task`; constructing the tree during SwiftUI rendering
must never enqueue work or mutate the shared task queue. A cluster's generated
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

Response presentation metadata persists optional `thinkingDurationSeconds`, measured from
generation start to the first nonempty answer text (or completion when no text update arrives).
The disclosure reads “Thought for Xm Ys”, omitting minutes below one minute; older saves
without timing read “Thought”. The thinking footer shows elapsed time only during loading
and animates out with the loading view before the answer starts its reveal.

Question fields scale to 105% during finger contact, returning to their normal size on release
or cancellation. A passive UIKit contact recognizer preserves native editing gestures.

Conversation question and response fonts use the exact point sizes selected in app settings;
iOS Dynamic Type does not rescale them. Settings-driven paragraph text follows the same policy.
Settings subpage labels and explanatory text use semantic fonts relative to iOS text styles,
so they follow the iPhone's Text Size setting independently of conversation font sizing.

Settings → User Guide displays a self-contained copy of the website's `guide.html` in
`UserGuideWebsiteView`. `Resources/UserGuide.html` includes the website CSS, artwork, fonts,
and four example scripts; it performs no network requests and uses an ephemeral WebKit data
store. The index's topic buttons push native Settings destinations, each showing only that
topic. Back returns to the guide index; edge swipes follow the existing Settings navigation.
Technical diagrams and practice examples match the website. Practice bookmarks live in
Settings-owned state shared across guide pages, and never enter the user's Insight Library;
practice tasks never enter the model queue. Native Settings navigation remains outside the web
view. Page text, demo cards, canvas drawings, SVG icons, and technical diagrams resolve their
light/dark colors from `AngroveTheme`. Appearance changes recolor the current page without
reloading it or losing practice state.
Guide typography follows the website's responsive sizes. Refresh the resource from a local
website checkout with `python3 scripts/sync_user_guide.py --website-root '/path/to/site'`.
The script embeds local assets only and leaves the website checkout unchanged. Its app adapters
live in `scripts/user_guide_app.css` and `scripts/user_guide_app.js`.

Appearance stores independent `CanvasBackgroundOption` preferences for the conversation thread
and Insight Tree in `@AppStorage`. Both default to System, following the app's color scheme;
Light and Dark override only their surface. Clouds bundles the website's `thinking-sky.jpg`
with its dark tint and cream palette. `CanvasBackground` stays stationary beneath scrolling
or camera movement. `canvasAppearance` preserves the inherited app scheme through nested
surfaces, so a System tree never picks up the thread's independent override. The tree setting
applies to the global library, conversation trees, and Study Topic canvases. Reset Settings
removes both background keys.

Response formatting is split by responsibility: `ResponseParsing` and `LiveResponseParsing`
prepare completed and incremental text; `ResponseFlowLayout` lays out words;
`CompletedResponseSegments` and `LiveFormattedResponseView` render them; `StreamingMessageView`
coordinates reveal progress and completion. Completed answers reveal Copy, Regenerate, and Branch
icons with the Insight controls’ shared 0.10-second stagger and 0.28-second blur/fade/scale
entrance. Disclaimer words and the next composer begin alongside the buttons. Disclaimer
and composer entrances settle over 0.35 seconds. The
composer's saved availability is set at model completion; body-reveal completion gates only its
presentation and is skipped for restored answers and Reduce Motion. Body-reveal completion
hides response metrics independently of footer completion. `ResponseTextFormatting` shares Insight-markup
removal while retaining the different emphasis policies for previews and definition context.

The tree canvas retains geometry-dependent interactions and physics. `InsightTreeRevealState`
owns reveal membership and animation tasks, and `InsightTreeSelectionState` owns transient
selection effects. `InsightTreeSelectionOverlay` receives resolved screen positions so rendering
selection lines does not depend on the full graph or physics state.

## Insight Tree canvas structure

`Features/InsightTree/InsightTreeCanvasView.swift` owns canvas inputs, SwiftUI state, and the
composition of the global and conversation tree. Its implementation is divided by responsibility:

| File | Responsibility |
| --- | --- |
| `InsightTreeCanvasRendering.swift` | Project graph items and compose connectors, selection overlays, and hit targets |
| `InsightTreeCanvasConceptNode.swift` | Node Concept label, discovery dot, suggested-node dismissal, and entrance appearance |
| `InsightTreeCanvasChip.swift` | Insight loading/revealed content, selection border, and discovery dot |
| `InsightTreeCanvasGraphEdge.swift` | Animated graph connectors and suggested-edge line styling |
| `InsightTreeCanvasLifecycle.swift` | Appearance, topology, scene lifecycle, and incoming request observers |
| `InsightTreeCanvasGestures.swift` | Tree pan/zoom, chip rotation, and camera focus/restore |
| `InsightTreeCanvasLayout.swift` | Insight placement, graph edge resolution, label footprints, and depth projection |
| `InsightTreeCanvasSimulation.swift` | Body reconciliation, overlap relaxation, and settled-position reporting |
| `InsightTreeCanvasMidpoint.swift` | Midpoint geometry, weights, loading/reveal, and source bond reangling |
| `InsightTreeCanvasStudy.swift` | Study framing, transitions, pivoting, rotation, and momentum |
| `InsightTreeCanvasDiscovery.swift` | Persisted-tree entrance sequences and seen/undiscovered tracking |
| `InsightTreeCanvasTypes.swift` | Shared canvas geometry and simulation support types |

The three visual components accept the values they render and callbacks, without owning a
second camera, model runtime, or persistence store. The behavior files are extensions of the same
canvas view: they share its existing state and animation transactions. Cross-file implementation
members have module visibility; members used within only one file remain private. This is a
structural refactor, not a change to graph layout, gesture policy, discovery storage, or generation.

## Persistence boundaries

Conversation branches and chat blocks are persisted as one Codable snapshot in
`Application Support/Aquinas/ConversationStore/conversations-v1.json`. The file store writes
atomically with AES-256-GCM encryption and Complete File Protection, keeps up to five rotating
encrypted backups, and migrates either prior conversation
snapshot from `UserDefaults` on first successful load. `InquiryPersistenceStore` is the
process-facing boundary; `CurrentConversationsStore` is its compatibility name at existing call
sites. All snapshot I/O runs on one serial background queue (`SerializedInquiryStore`): saves
return immediately, loads and imports wait behind queued writes, and the shell flushes the queue
when the scene moves to the background. Saved Insights, global and Study Topic tree snapshots,
conversation-to-Insight membership, and canvas topology/presentation state use separate atomically
written encrypted files under `Application Support/Aquinas/InsightTree/CanvasState`. Existing
`UserDefaults` payloads migrate on first successful read. A file or legacy payload that fails
decoding is retained and reported; subsequent saves cannot replace an undecodable payload with an
empty tree. See
[`PERSISTENT_MEMORY_IMPLEMENTATION_PLAN.md`](https://github.com/rbaltodano/Angrove-Foundations/blob/main/PERSISTENT_MEMORY_IMPLEMENTATION_PLAN.md)
for the planned SwiftData migration.

There is no server-side persistence. Conversations, Insights, and tree state live only on the
device. (An earlier development topology mirrored tree content to a Mac-hosted SQLite backend; the
app no longer contains that client.)

Startup validates keys and migrates personal data before mounting the app interface.
`PrivatePreferences`, `EncryptedPersonalFile`, and `EncryptedStringStorage` are the encrypted
storage boundaries. See [Data Encryption](Data-Encryption.md) for coverage, recovery, and exports.

## Important seams

| Area | Primary location |
| --- | --- |
| App shell and page handoff | `Angrove-iOS/App/ContentView.swift` |
| Conversation orchestration | `Features/Conversation/CurrentConversation.swift` |
| Transcript and response lifecycle | `Features/Conversation/ConversationComponents.swift` |
| Visible model tasks | `Features/Conversation/ModelTaskQueue.swift` |
| Model status and context controls | `Features/Conversation/ModelControls/`: one app-wide bar (`ModelControlsHost.swift`, mounted by the shell). Pages publish their buttons to it (`InquiryControlDock`, `PageModelControls`, `LibraryModelControls`) and never render a bar of their own. |
| Model boundary and local implementation | `Services/AngroveModel.swift`, `Services/LiteRTAngroveModel.swift` |
| Runtime ownership | `Services/AngroveApplicationRuntime.swift`, `Services/LiteRTAngroveRuntime.swift` |
| On-device tree seeds | `Persistence/LocalInsightTreeSeedStore.swift` |
| Home discovery cards | `Features/Home/HomeDiscoveryCards.swift`, `TodayInHistoryEntries.swift`, `Persistence/GlossedTermStore.swift`, `Persistence/FlaggedQuoteStore.swift` |
| No-model fallback | `Services/UnavailableAngroveModel.swift` |

## Current product constraints

`/compact`, `/clear`, `/rename`, `/new`, `/tree`, `/topic`, and `/insights` are the supported slash
commands. A cached contextual definition must
open immediately even while model work is active; queue a definition only on cache miss. The
context control is a non-spinning gauge, while Model Status describes active work. Question of the
Day generation is background consolidation work and remains queued when an active conversation is
opened.

## Lock Screen question widget

`AngroveWidgets` is a WidgetKit extension supporting the rectangular Lock Screen family.
It shows **Question of the Day:** and up to two lines of the latest saved question. Tapping
opens the latest saved question in the answer composer using `angrove://question-of-the-day`.
The URL handler waits for shell startup to complete and uses the same conversation request as
the Home card, preserving the reason and Insight prompt context. The existing App Lock overlay
still protects the destination. Before a question exists, the link opens Home.

`WidgetShared/DailyQuestionWidgetStore.swift` shares only question text through the App Group
`group.com.ryanbaltodano.Aquinas-iOS`. The shared text is AES-256-GCM encrypted with a separate App Group Keychain key accessible
after the first unlock. `HomeQuestionOfTheDayStore` publishes on save and load
(the latter migrates an existing question on the first app launch after upgrading), requesting
a widget timeline reload when the text changes. App startup also reloads the timeline so an
existing widget picks up navigation changes after an app update. The widget deliberately retains the
latest question after answering or expiration; the Home card keeps its existing lifecycle.
The extension does not load the model or generate questions. Both targets require the same
App Group in their signing profiles.
