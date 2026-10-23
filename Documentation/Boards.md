# Boards (macOS)

Called Boards everywhere a person sees them. In code the feature keeps its original name:
`Worktree*` types, `macOS/Features/Worktree/`, `MacDestination.worktree`, and the
`angrove.worktrees.v1` store, so saved Boards still open.

A free-form canvas page for exploring ideas with notes, questions, headings, photos and commands.
Mac only, opened from the sidebar (`MacDestination.worktree`). Code lives in
`macOS/Features/Worktree/`.

The page opens on saved Boards shown as cards (`MacWorktreeHomeView`); a card opens its
canvas. `WorktreeLibrary` holds the saved documents and the open `WorktreeBoard`. Boards save about
a second after each change, when leaving, and at quit, to the encrypted file-backed personal store
(`WorktreeStore`, under `Aquinas/Worktree`). Model work still in progress is not saved.

Design intent: every action can be reached however a person's instincts lead them — typing,
short commands, shortcuts, clicking a tool, or dragging — and it should just work.

## Files

| File | Owns |
| --- | --- |
| `WorktreeLibrary.swift` | Saved documents (`WorktreeDocument`), the store, and the open board |
| `MacWorktreeHomeView.swift` | The page: Board cards, empty state, New Board, opening and closing |
| `MacWorktreeView.swift` | One canvas: camera (pan, pinch, ⌘-scroll, ⌘= / ⌘− with nothing to resize, ⌘0), title, docked cards, placement, tool actions |
| `WorktreeKeyShortcuts.swift` | The canvas key monitor: typing, `/`, tool shortcuts, ⌘+ / ⌘− resize, zoom, undo, fast-typing keys |
| `WorktreeControlDock.swift` | The controls pill: Add, Tools, Model Tasks, Trash |
| `WorktreeBoard.swift` | All canvas state and actions: items, selection, command field, model work, resize, sidebar copy/replace |
| `WorktreeItemView.swift` | One item: note, question window, Insight card, summary, heading, photo; grip, label, selection lift |
| `WorktreeConversationSurface.swift` | A conversation’s native hosting surface, separating its layout graph from the canvas |
| `WorktreeTextBox.swift` | The Figma-style box (`WorktreeBoxChrome`, grip, press glow), note/heading resizing, `WorktreeCanvasPointer` |
| `WorktreePhotoPlacement.swift` / `WorktreePhotoResize.swift` | Photo placement preview; photo crop and scale |
| `WorktreeToolsCard.swift` | The Tools card and a picked-up tool's pointer preview (`WorktreeToolPlacement`) |
| `WorktreeTextEditor.swift` | Borderless `NSTextView` for canvas text, labels and the command field, with the command sweep |
| `WorktreeCommands.swift` | Command parsing, short forms, and `WorktreeTool` (tested in `MacWorktreeCommandTests`) |
| `WorktreeTrash.swift` / `WorktreeTrashCard.swift` | Trash storage and its docked card |
| `WorktreeHistory.swift` | Canvas undo and redo |
| `WorktreeConversationDrop.swift` | Sidebar ⇄ canvas drag payload and the conversation chip |

## Canvas basics

- **Typing anywhere** (outside a text field) starts a note 16pt right of the pointer, holding what
  was typed. Keys typed before a just-opened field takes focus (letters, Return, Delete, Esc) act
  on that field, so fast typing never loses a keystroke. Clicking only selects.
- **Return submits** everywhere; Shift-Return breaks the line.
- **Selection:** windows, Insight cards, headings and photos are selectable (double-click a heading
  to edit): hovering and selection keep their size fixed; selected items get accent-green borders.
  ⇧- or ⌘-click selects several. Esc closes a docked card or puts down a tool, then deselects.
- **Alignment:** while dragging, an item's left, centre or right (and top, centre or bottom) snaps
  to another item's within 8pt, and an accent-green guide draws from its centre, running 84pt past
  both items with faded ends. Guides fade on release (`WorktreeBoard.move`).
- **Box selection:** drag on empty canvas to select every item the rectangle touches. The box has
  an accent-green border and a 15% accent-green fill. Shift- or Command-drag adds to the original
  selection; shrinking the box removes items that leave it. Space-drag and scrolling still pan.
- **Dot grid:** the Insight Tree's grid with its drifting field off, so the dots rest invisible.
  One ripple marks selecting, something finishing, placing, removing an item, dismissing a command
  field, and pressing a resize edge.
- **Empty canvas:** an Insight Tree–style empty state explains typing, questions and Tools.
- **Controls:** Add, Tools, Model Tasks and Trash; their cards open one at a time. Add (+) is the
  conversation's menu: Insights and Passages place cards from the library; Photos… and Image
  File… place pictures.
- **Space to pan:** as in Figma, holding Space outside a text field turns the canvas into a grab
  tool (`WorktreePanSurface`): an open hand over everything, closing while you drag to pan. Clicks
  never reach items while it is held. Releasing Space, leaving the window or the page lets go. A
  just-opened field that has not taken focus yet still gets the space as text.
- **Place:** each Board remembers its pan and zoom across page changes and launches.

## Questions and windows

Text opened with a quotation mark, submitted, becomes a conversation window. It animates from the
note's chrome (8pt padding, no border) to a card (28pt, border), and is answered through the same
`MacConversationState` and `ModelResponseCard` as the conversation page (thinking, reveal,
Insights). These sessions set `savesConversation = false`, so they stay out of the sidebar.

Windows have sticky per-turn questions, a top fade under the pinned question and a bottom fade at
the window edge, follow-ups through the conversation composer (`MacCommandEditor`),
browser-style resizing (sides, bottom, bottom corners) and drag by the grip or top edge.

Completed answers on the open Board count as visible: they do not post an answer-ready
notification while the app is active on that Board. A completed definition notification or its
expanded docked Insight card can be dragged onto the canvas. Dropping places a persistent copy
at the pointer and dismisses that notification/card; cancelling leaves the dock untouched.
Placement uses the normal canvas undo/redo history and does not bookmark the Insight.

## Commands

Typing `/` opens a command field 32pt right of what it acts on: the hovered item (hovering within
a multi-selection keeps the group), else the selection, else (by the pointer) the whole Board.
With something selected, `/` opens even from another text field. `/rename` names each target;
`/define` and `/summarize` read them together. Submitting `/heading` emits only the heading’s arrival ripple. A lone `/` (or a lone quotation mark in a note) left
for three seconds fades away. Recognised commands turn green with the composer's sweep. Commands
can follow a question (`"…" /rename /summarize`) and queue behind its answer.

| Command | Short | Needs a target | Does |
| --- | --- | --- | --- |
| `/heading [Text]` | `/h` | Only without text | Adds a heading from the target or the supplied text; an existing heading cannot be targeted. |
| `/rename [Text]` | `/r` | No | Labels the target with the conversation-title prompt, or sets the typed label. With nothing targeted it names the Board. |
| `/summarize` | `/s` | Yes | Writes a brief summary (`AngroveModel.summarize`) beside the target as an editable note. |
| `/define [term]` | `/d` | Only without a term | Defines the target (inferring a short subject for a photo or long selection), or the typed term in its context. An existing Insight needs an explicit term. |
| `/file` | `/f` | No | Opens the file browser (pictures only for now); chosen pictures follow the pointer to be placed. |

Short forms, like full names, count only standing alone, so `and/or` stays text. `/help` is
retired; Boards that already hold its card still show it.

Unrecognised commands, misformed ones (bare `/define` with no target) and target-dependent
commands with nothing targeted are struck through in accent red, then blur away; nothing runs.

**Model work.** Labels are Libre Baskerville Italic 28 in accent green; headings and labels arrive
one word at a time, like page titles, and become editors when clicked. Pending work shows
**Labeling…**, **Summarizing…** or **Defining…**, breathing while queued and shimmering while
running (`WorktreeWorkStyle`). Summaries use the conversation's completed-answer word reveal, then
become ordinary notes; clicking during the reveal edits immediately, Reduce Motion shows the full
text, and saved notes and redo never replay it. Photo summaries, subjects, labels and definitions
send the real image through the shared model and task queue; engines without vision fail
explicitly. Definitions can recover a likely intended spelling (the Insight takes the corrected
title); a false "unrecognized term" gets one direct retry. A failed definition reveals
**Could not define <term>** in accent red in place, then blurs away 1.5s later; it never opens an
alert and is excluded from saving, Trash and undo. Queued work uses
`ModelTaskKind.labelWorktreeItem`, `.summarizeWorktreeItem` and `.defineInsight`. Pending requests
capture their targets, and an old dismissal cannot close a newly opened command field.

## Tools and shortcuts

**Tools** (⌘ symbol) opens a docked card listing Text, Question, Heading, Rename, Summarize and
Define with their commands and shortcuts. Rows highlight on hover like the "…" menu's. Add File is
in the "+" menu instead (Image File…, shown with ⇧⌘K); ⇧⌘K and `/file` still open it. Clicking
anywhere on the canvas while Tools, Trash or Model Tasks is open closes it.

| Tool | Shortcut |
| --- | --- |
| Heading | ⌘H |
| Rename | ⌘R |
| Summarize | ⌘S |
| Define | ⌘D |
| Add File | ⇧⌘K |

**Shortcuts** act on what is selected, else the item being edited, else the hovered item; unlike
`/`, hovering never overrides the selection. The command appears in the field as if typed, then
runs. With nothing to act on, it waits typed by the pointer (`/define `) for a term or text.
Shortcuts are taken even while typing. On the Board page they win over the menus: ⌘H adds a
heading instead of hiding the app (⇧⌘H is still Home). App-wide, Swap Panes is ⇧⌘S and Previous
Page has no shortcut for now.

**Clicking a tool** picks it up: a label like the controls' hover labels follows the pointer on a
spring, saying what a click does — **Click to add Text**, **Click to add Question**, **Click to add
Heading**, **Click to rename**, **Click to summarize**, **Click to define**. A click places it:

- Text, Question and Heading open an active note or heading where the preview sat. Question places
  the “ as if typed, so a lone quote fades as usual. An empty note or heading goes away when
  editing ends.
- Rename, Summarize and Define act on the clicked item, as their shortcut would. On empty canvas,
  Define opens `/define ` there; Rename and Summarize stay picked up.
Escape puts a tool down; dragging or scrolling pans; leaving the page puts it down.

## Boxes, moving and resizing

Notes, headings and photos draw a Figma-style box: a 1pt outline with a 7pt square at each corner
in accent green at 50%, constant on screen at any zoom. A photo's box hugs the picture; a note's or
heading's includes its 8pt padding. The box is invisible until the pointer is within 48 screen
points; then only the part of it inside a 48-point circle around the pointer shows (the rest stays
at 0%), at full strength to 24 points and fading out over a 24-point soft edge. It fades in over
0.15s. Pressing an edge or corner to resize fades the whole box up over 0.5s. An item's side grip is the same
accent green at 50%.

- **Move:** the canvas grip, turned on its side, sits centred 8pt above the top line, hidden until
  the box shows and glowing (100%, soft green shadow) while hovered or dragged. Dragging it, or
  anywhere along the top edge between the corners, moves the item — with snapping, Trash and the
  sidebar — and never resizes. Dragging anywhere inside a photo also moves it; its side and corner
  resize targets retain crop and proportional resize. Insight card bodies also move their cards;
  their action buttons remain clickable. Notes also keep their grip before the text. Move grips
  use 75% accent green, brightening to full opacity on hover or drag for the box's top grip.
- **Resize notes and headings:** side edges set the wrap width (the left edge keeps the right side
  fixed), the bottom sets a minimum height, and corners do both. Width is at least 40pt; height at
  least one line (28pt, or 56pt for a heading). Text never overflows: a box shorter than its text
  grows to fit. A resized heading wraps while revealed and while editing.
- **Resize photos:** side and bottom edges crop; the image fills the shape, centred, and within 16
  screen points of the original aspect ratio the edge snaps to it. Corners scale the crop and image
  proportionally, keeping the opposite corner fixed. Cropping preserves the original image data.
- **Press glow:** pressing a resize edge or corner ripples the dot grid from the press and lights
  the outline to 75%: a soft-edged circle grows from the press over 0.15s (instantly with Reduce
  Motion), holds while dragging, and fades over 0.3s on release.
- **⌘+ and ⌘−** grow or shrink what is selected, else being edited, else hovered, by 10% about its
  centre, even while typing: notes and headings change their box, photos scale with their crop,
  and windows that have a size resize. Insight cards keep their size. With nothing to resize they
  zoom the canvas, as before; ⌘0 still resets the zoom.
- Sizes save with the item; each drag or key press is one undoable action.

`WorktreeCanvasPointer` tracks the pointer in canvas space. It publishes `nearIDs`, which changes
when the pointer crosses a box's 48-point line, and `nearWorld`, which follows the pointer only
while some box is near and is read only by near boxes (for their spotlight). Elsewhere, moving the
mouse re-renders nothing.

## Photos

Photos… and Image File… (or `/file`) prepare pictures for placement. A 120pt thumbnail follows the
pointer, its top-left 24pt right of and below it, with a spring trail and overshoot and a 2°
clockwise tilt; horizontal motion adds ±1°, settling back to 2°. Reduce Motion removes the trail
and changing tilt. A click anywhere, including over an item, places the next picture on release;
scrolling and dragging pan instead (⌘-scroll and pinch zoom). Escape cancels the remaining
pictures; leaving the page clears placement.

Placed photos are upright (the picker's decorative rotation is discarded), keep their
proportions, fit inside 1000 × 1000 canvas points without enlarging smaller originals, scale in
from 0.98 and pulse the grid from their centre. Each placement is one undoable action; only placed
photos are saved.

## Sidebar ⇄ canvas

- **Sidebar → canvas:** drag a sidebar conversation onto the canvas. It lands as the sidebar chip,
  then opens into a window sized like the last selected or made window, labelled with its title.
  The window holds a **copy**: it shows the last 5 turns and loads 5 more when scrolled to the top.
  `/summarize` and `/define` still read the whole conversation, trimmed to the newest turns that fit
  the on-device context behind any compacted summary (`WorktreeBoard.fitting`).
- **Canvas → sidebar:** drag a window by its grip over the sidebar; it becomes the chip (drawn at
  window level, since the canvas is clipped). On drop the window springs back and the sidebar gets
  a **copy**, named by the window's label or, without one, by the model. A window that came from
  the sidebar asks to **Replace** that conversation or **Keep Both**, which names the new one
  **(Copy) Title**. A newly copied window remembers its sidebar destination, so later drops
  offer Replace/Keep Both for that copy too.

Before later normal chat tasks run, a sidebar transfer queues `Update Insight Tree` on the same
process-scoped runtime, checking eligible completed turns across all branches in transcript order.
A first transfer maps the completed Board conversation and carries its manually saved Insight
memberships into the new conversation. **Replace** keeps the original conversation UUID, seeds,
Node IDs, saved Insights, and per-conversation canvas state; it never clears or reconstructs the
tree. Only genuinely new subjects are appended using the normal MiniLM similarity threshold.
**Keep Both** creates a separate conversation and maps its own tree.

The Board stores `sourceMappedTurns` (branch/response locations and SHA-256 content fingerprints)
when a sidebar conversation is placed. This optional field survives Board saves and supports old
Board documents. Legacy windows capture their source baseline on their first return. A separate
encrypted per-conversation ledger in InsightTree/CanvasState records successfully checked turns,
including turns covered by an existing subject. Later returns check only new or changed turns;
normal chat mapping writes the same ledger. Existing tree positions need no Board-side copy,
since they remain associated with the original conversation UUID.

Failed or cancelled mapping does not acknowledge a turn, so a later return can retry it. Jobs
recheck the persisted conversation and turn after model/embedding awaits and discard stale or
deleted results. Removing the exported Board window does not cancel its sidebar tree update.
Transfer mapping is foreground queue work before subsequently submitted questions; ordinary chat
mapping remains background work. Explicit queue reordering and cancellation remain available.
Queued model jobs themselves still do not survive quitting, as with other on-device mapping.
Corpus-scope abstentions, failed/cancelled answers and model-only answers remain excluded.

Transfers wait for the current answer to finish, so a streaming fragment cannot be copied and
mapped as completed history.

Verification: 63 focused Mac tests pass, covering first transfer, all branches, repeated drops,
persisted checkpoint encoding, backwards-compatible Board decoding, return baselines, semantic
deduplication, edited turns, legacy embedding refresh, cancellation, failure/retry, stale results,
foreground preemption and explicit queue reordering, plus existing Board and conversation behavior.
Log: `/tmp/angrove-board-tree-transfer-tests.log`. The signed Release update was installed at
`/Applications/Angrove.app` with automatic launch disabled and left closed. Install log:
`/tmp/angrove-board-tree-transfer-install.log`.

Known limitation: replacing a conversation that is open on the conversation page leaves the page
showing its old copy until it is reopened.

## Trash

Drag an item by a grip onto the controls' Trash to delete it. Click Trash for a docked card (28pt
padding and corners) with a Trash heading and Empty action. Each Board keeps its ten newest
deleted items, newest first; the oldest is discarded when an eleventh arrives. Rows have 12pt
horizontal and 8pt vertical padding, 16pt corners, type icons with accessibility labels, two equal
columns with a 24pt gap, and a 50% primary-canvas hover background. Notes show their text,
headings title-cased text, and photos an original-aspect thumbnail with 8pt corners.

Drag a row onto the canvas to restore it there; cancelled drags leave it in Trash. Empty asks for
confirmation and discards everything. Undo cannot recover items discarded by overflow or Empty.
Pending model work and empty drafts never enter Trash.

## History

⌘Z undoes and ⇧⌘Z redoes up to 20 canvas actions per open Board: adding, deleting, moving,
resizing, renaming, completed definitions and summaries, and finished text edits. A drag, resize
or key-press resize is one action. Text fields use native undo while editing (also 20 deep); when
it runs out, the shortcuts reach canvas history. Camera movement never enters history. Closing a
Board clears its history, and redoing a model result never re-runs generation.


## Conversation rendering performance — October 19, 2026

Conversation cards use `WorktreeConversationSurface`, an `NSHostingController` boundary that
retains native scrolling and follow-up editing while separating each conversation’s layout graph
from the outer canvas. The current SwiftUI environment is forwarded into the hosted content;
response streaming and automatic height changes remain observed within it.

Response-word context menus on Boards use `MacContextMenuContainer`. One native anchor per
conversation replaces the native region view previously allocated for every word. Word hit
rectangles stay in conversation-local coordinates, outside SwiftUI published state. The registry
converts the click into that space on demand, preserving scroll clipping and current callbacks.
Other pages retain their existing menu implementation.

A repeatable Debug workload (`MacBoardsCameraMotionTests`) mounts 12 synthetic conversations
and performs 180 alternating pan/zoom updates, forcing layout/display after each update. CPU
samples identified word-menu geometry and view-graph work as hot paths. Average measured
main-thread work fell from 114.1 ms to 55.6 ms per update; the 95th percentile fell from 296.8 ms
to 87.0 ms. These are synthetic forced-update costs, not presented GPU frame rates or a claim of
60 FPS on the owner’s saved Boards. Further profiling remains appropriate for large canvases.

Focused regressions cover transformed and clipped word menus, refreshed callbacks, native
follow-up editing, growing automatic card heights, live responses, selection, board commands,
and light/dark renders. The FPS overlay remains available for checking real interactions.


## Hybrid canvas rendering — October 20, 2026

`WorktreeCanvasScene` retains a native scene independently of the SwiftUI camera updates.
Inactive items render as cached Core Animation image layers. Panning and zooming move the
cached world with one native bounds transform; they do not relayout every conversation.
The command field and editing, generating, revealing, or interacting items remain live.
Live item hosts use a separate viewport overlay so SwiftUI receives correct pointer and
text-editing coordinates even when zoomed. The initiating click or context-menu request
activates the real item before dispatch, and cached items expose an accessibility activation.

Offscreen items are culled with an overscan margin. Snapshots refresh one per run-loop after
movement settles, adapt their resolution to zoom, and share a 128 MiB bitmap budget with
hidden least-recently-used entries evicted first. Oversized surfaces remain native. Existing
snapshots remain visible during movement; native hosts and their state are retained for reuse.
Content, typography, appearance, selection and size changes invalidate the affected snapshot.
Transient notes and model work stay mounted until their tasks finish.

The same 12-conversation Debug camera workload, after waiting for initial caches, measured
8.7 ms average and 10.4 ms p95 per forced layout/display update, versus 55.6/87.0 ms after
the preceding native-card/menu optimization. Initial snapshot preparation is outside this
steady-state measurement. These CPU costs do not establish presented FPS or performance
on every saved Board. Tests cover cache invalidation and culling, snapshot reuse during camera
movement, initiating drags at 100%/200%, first word-menu requests, native follow-up editing,
generation, deletion, transient-note expiry, and light/dark rendering.


### Conversation item dragging

Conversation grips and the padded top edge now route to a native scene drag receiver when
a resting cached card is available. The moving item uses its existing image layer; its
transcript host stays detached. Editing and active generation retain the live interaction
path. Position-only changes no longer replace SwiftUI content or request a new snapshot;
roots synchronize their next gesture origin after movement settles. The native and SwiftUI
paths share snapping, destination handling, Trash/sidebar drops, and history completion.

The follow-up composer reads `item.followUp` from its narrow input and writes through
`board.update`. Previously its binding read `board.items` in the conversation body, making
all retained transcripts and word menus observe every item-origin change, even while their
hosts were detached. CPU sampling during a real drag confirmed that repeated work.

`MacBoardsItemMotionTests` posts real mouse events over a 12-conversation scene. A 120-update
sequence with 16 ms waits fell from 13.2 seconds with broad composer observation to about
2.1 seconds after narrowing it, with no snapshot rebuilds during movement. This is synthetic
event-processing cadence, not measured presented GPU FPS. Regressions cover repeated top-edge
drags at 100%/200%, undo, and grip dragging to Trash, in addition to the existing native
follow-up editing, height growth, cache, menu, selection, and appearance checks.


### Fixed bottom canvas fade — October 21, 2026

The Board owns its bottom edge fade as a fixed-height, bottom-aligned canvas overlay, matching
the top edge treatment. Its Model Controls configuration disables the shared stack-sized fade,
so opening or closing Model Tasks, Tools, Trash or an Insight card cannot stretch the gradient
upward. Cards retain their existing layout and animations above the controls.

Four focused Mac tests pass, including light/dark pixel comparisons of the gradient before and
after opening/closing Model Tasks and an Insight card. Rendered fixtures were inspected at
`/tmp/angrove-board-fixed-fade-light.png` and `...-dark.png`. Test log:
`/tmp/angrove-board-fixed-fade-tests.log`.
The signed Release update was installed at `/Applications/Angrove.app` with
`ANGROVE_MAC_LAUNCH_AFTER_INSTALL=0`; the app was left closed. Install log:
`/tmp/angrove-board-fixed-fade-install.log`.

### Global Insight dragging — October 21, 2026

Docked Insight and Node cards in every Mac tree, completed-definition cards and definition
notifications share the Board's Insight drag source. Drop on a sidebar conversation to open it
with the Insight attached as a quote, or on Recents' + to start a new quoted conversation.
Dropping directly into an open conversation also attaches the quote without sending a question.
Completed-definition cards remain in the workspace dock when switching pages or conversations.

Hold an Insight over Boards in either sidebar for 0.5 seconds to open the Board list (saving
and closing an already-open Board). Hold over a saved Board card for another 0.5 seconds to
open its canvas, then release on the canvas to place the Insight at the pointer using that
Board's pan/zoom transform. Leaving a target cancels its timer; hovering alone places nothing.
Board placement preserves the existing copy, persistence and Undo behavior.

Insight drags advertise a private, process-only pasteboard type, keeping serialized content out
of text editors. Conversation and Trash canvas drops retain their existing string payloads.
Focused tests cover hover dwell/reentry/cancellation, payload identity, destination-only quoting,
card survival across page replacement, Board persistence/Undo and light/dark card rendering.

Verification: both native targets build and all 13 selected Mac drag/Board notification tests
pass (`/tmp/angrove-global-drag-tests.log`). Persistent-card light/dark renders were inspected.
The signed Release update is installed at `/Applications/Angrove.app`
(`/tmp/angrove-global-drag-install.log`). The first install attempt encountered another build's
database lock; retry succeeded after it cleared. Native automation opened a global tree card,
but its point-to-point drag attempts did not confirm a drop, and it exposes no held multi-stage
hover gesture. Full live drag-through navigation remains unverified. No test quote or Board
item was committed; Home was restored and the app quit normally.


### Complete text snapshots and stable scrolling — October 22, 2026

Bitmap padding now includes the card's upward chrome offset and the full label above it.
The previous 64pt margin could crop glyph ascenders in 28pt labels; the 96pt margin keeps
those pixels without changing the visible card layout. Snapshot preparation waits for first
appearance/reveal and a settled native draw. During cached-to-live activation, the previous
image stays underneath until the reattached native scroll view has drawn once.

Each retained conversation reports SwiftUI scroll phase/offset activity and observes its
native clip view's bounds. Its native host stays mounted through scrolling and settling,
including simultaneous camera movement. Active cards are measured as needed but are not
repeatedly rasterized. Cache ownership clears when a card becomes inactive, so subsequent
zoom/content refreshes can build a fresh snapshot. Native bounds observers and pending
presentation/scroll work are removed when the item or scene is torn down.

`MacBoardsScrollRenderingTests` compares cached/live label pixels, exercises native scroll
changes with camera updates, checks that answer pixels survive recaching, and verifies that
the reading position survives reactivation. It renders light/dark variants and a fractional
170% zoom. The old bounds lost about 5% of the tested label's ink; the corrected dark render
retains over 99.9%. Separate drag/camera workloads continue to check the performance path.

### Grip, hover, and selection interaction (October 22, 2026)

Heading side grips align with the box's top-left corner, with an 8-screen-point gap
from its left outline. Top grips include their complete target above the box in native
hit testing and use the native scene drag receiver, including notes, headings and photos.
Hovering a cached item reattaches only that item's native host and invalidates its cursor
rectangles, restoring text, resize and move cursors before a click. Leaving a native grip
or cancelling a native drag restores the ordinary pointer.

Dragging a selected item moves all selected items by the same snapped delta; selected
items do not snap against one another. The group keeps its internal spacing and one
undo action restores the entire move. Dragging an unselected item moves that item alone.
Command-N creates a new board throughout the Boards page, including from an open board.
The same shortcut creates a Study Topic on Study Topics and a conversation on other pages.

### Drag image sharpness (October 22, 2026)

Resting caches no longer impose a 3-pixel-per-world-point ceiling below the current
zoom and display resolution. Native pickup promotes undersized caches for the dragged
item and selected companions once, using display backing scale times canvas zoom.
While a newly attached host finishes drawing, its previous image stays visible and the
host stages transparently. The sharper replacement blends in over 100ms; Reduce Motion
uses an atomic swap. Live input activation still presents the real controls. The resulting
sharp cache is reused throughout movement.
Preparation is cancelled on release or scene teardown. The 128 MiB cache budget and
16-megapixel capture limit remain; items that cannot fit stay live during dragging.

### Pan gesture ownership (October 22, 2026)

Native scroll routing chooses its owner on the first event, rather than hit-testing
every event. A canvas pan continues across conversation windows and through momentum
until the gesture ends. A gesture started inside a native conversation scroll view
keeps its own scrolling; the next gesture chooses again. Phase-less wheel input keeps
the same owner within a burst, resetting after a 180ms pause. Cancellation, view
teardown, and window changes clear the routing state.

### Hover chrome and scaled controls (October 22, 2026)

Snapshots exclude transient move grips and hover outlines. Live grips also follow the
canvas pointer's proximity, so a missed native hover-exit cannot leave them lit. Native
resize cursors cover the visible side and corner targets, including their overhang
outside an item's frame. Conversation transcripts share their item's hosting hierarchy
so Insight buttons receive clicks at their drawn position at all zoom levels; their
equatable boundary and cached scene surfaces still isolate transcript work from motion.
The Boards FPS overlay is removed for demo recording; its implementation is retained.

### Native hover lifetime (October 22, 2026)

Resize illumination uses one native canvas tracking area across child hosting surfaces.
Leaving the canvas, deactivating its window/app, and teardown clear pointer proximity.
Camera changes recompute the world position beneath a stationary screen pointer.
Transient outlines and grips require a current nearby pointer, so stale per-control
hover or press state cannot leave an area illuminated after departure.

### Rendered snapshot hover regression (October 22, 2026)

Hiding chrome and capturing in the same run-loop turn can still capture the previous
SwiftUI/CALayer frame. Snapshot preparation now hides transient chrome ahead of capture
and allows the rendered update to settle before reading pixels. Leaving hover releases
the interaction host so a clean cache can finish. Regression coverage lights an outline,
forces the camera/cache path, leaves, and asserts the actual cached bitmap contains zero
accent pixels. Grip visibility is checked against each grip's location, not the entire
nearby item's bounds; adjacent large items no longer reveal distant grips together.
