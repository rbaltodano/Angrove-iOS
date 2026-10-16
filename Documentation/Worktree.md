# Worktree (macOS)

A free-form canvas page for exploring ideas with notes, questions, headings, photos and commands.
Mac only, opened from the sidebar (`MacDestination.worktree`). Code lives in
`macOS/Features/Worktree/`.

The page opens on saved Worktrees shown as cards (`MacWorktreeHomeView`); a card opens its
canvas. `WorktreeLibrary` holds the saved documents and the open `WorktreeBoard`. Boards save about
a second after each change, when leaving, and at quit, to the encrypted file-backed personal store
(`WorktreeStore`, under `Aquinas/Worktree`). Model work still in progress is not saved.

Design intent: every action can be reached however a person's instincts lead them — typing,
short commands, shortcuts, clicking a tool, or dragging — and it should just work.

## Files

| File | Owns |
| --- | --- |
| `WorktreeLibrary.swift` | Saved documents (`WorktreeDocument`), the store, and the open board |
| `MacWorktreeHomeView.swift` | The page: Worktree cards, empty state, New Worktree, opening and closing |
| `MacWorktreeView.swift` | One canvas: camera (pan, pinch, ⌘-scroll, ⌘= / ⌘− with nothing to resize, ⌘0), title, docked cards, placement, tool actions |
| `WorktreeKeyShortcuts.swift` | The canvas key monitor: typing, `/`, tool shortcuts, ⌘+ / ⌘− resize, zoom, undo, fast-typing keys |
| `WorktreeControlDock.swift` | The controls pill: Add, Tools, Model Tasks, Trash |
| `WorktreeBoard.swift` | All canvas state and actions: items, selection, command field, model work, resize, sidebar copy/replace |
| `WorktreeItemView.swift` | One item: note, question window, Insight card, summary, heading, photo; grip, label, selection lift |
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
  to edit): 2% lift on hover (photos 5%), 5% when selected, with the Insight card's drop shadow.
  ⇧- or ⌘-click selects several. Esc closes a docked card or puts down a tool, then deselects.
- **Alignment:** while dragging, an item's left, centre or right (and top, centre or bottom) snaps
  to another item's within 8pt, and an accent-green guide draws from its centre, running 84pt past
  both items with faded ends. Guides fade on release (`WorktreeBoard.move`).
- **Dot grid:** the Insight Tree's grid with its drifting field off, so the dots rest invisible.
  One ripple marks selecting, something finishing, placing, removing an item, dismissing a command
  field, and pressing a resize edge.
- **Empty canvas:** an Insight Tree–style empty state explains typing, questions and Tools.
- **Controls:** Add, Tools, Model Tasks and Trash; their cards open one at a time. Add (+) is the
  conversation's menu: Insights and Passages place cards from the library; Photos… and Image
  File… place pictures.
- **Place:** each Worktree remembers its pan and zoom across page changes and launches.

## Questions and windows

Text opened with a quotation mark, submitted, becomes a conversation window. It animates from the
note's chrome (8pt padding, no border) to a card (28pt, border), and is answered through the same
`MacConversationState` and `ModelResponseCard` as the conversation page (thinking, reveal,
Insights). These sessions set `savesConversation = false`, so they stay out of the sidebar.

Windows have sticky per-turn questions, a top fade under the pinned question and a bottom fade at
the window edge, follow-ups through the conversation composer (`MacCommandEditor`),
browser-style resizing (sides, bottom, bottom corners) and drag by the grip or top edge.

## Commands

Typing `/` opens a command field 32pt right of what it acts on: the hovered item (hovering within
a multi-selection keeps the group), else the selection, else (by the pointer) the whole Worktree.
With something selected, `/` opens even from another text field. `/rename` names each target;
`/define` and `/summarize` read them together. A lone `/` (or a lone quotation mark in a note) left
for three seconds fades away. Recognised commands turn green with the composer's sweep. Commands
can follow a question (`"…" /rename /summarize`) and queue behind its answer.

| Command | Short | Needs a target | Does |
| --- | --- | --- | --- |
| `/heading [Text]` | `/h` | Only without text | Adds a heading from the target or the supplied text; an existing heading cannot be targeted. |
| `/rename [Text]` | `/r` | No | Labels the target with the conversation-title prompt, or sets the typed label. With nothing targeted it names the Worktree. |
| `/summarize` | `/s` | Yes | Writes a brief summary (`AngroveModel.summarize`) beside the target as an editable note. |
| `/define [term]` | `/d` | Only without a term | Defines the target (inferring a short subject for a photo or long selection), or the typed term in its context. An existing Insight needs an explicit term. |
| `/file` | `/f` | No | Opens the file browser (pictures only for now); chosen pictures follow the pointer to be placed. |

Short forms, like full names, count only standing alone, so `and/or` stays text. `/help` is
retired; Worktrees that already hold its card still show it.

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

**Tools** (⌘ symbol) opens a docked card listing Text, Question, Heading, Rename, Summarize, Define
and Add File with their commands and shortcuts.

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
Shortcuts are taken even while typing. On the Worktree page they win over the menus: ⌘H adds a
heading instead of hiding the app (⇧⌘H is still Home). App-wide, Swap Panes is ⇧⌘S and Previous
Page has no shortcut for now.

**Clicking a tool** picks it up: a 50% preview follows the pointer with the photo placement's
spring trail and tilt, styled like what it makes — “Text” and an opening “ as a note, “Heading” in
the heading's font, size and color (scaled with the zoom), and **Click on something to …** for
Rename, Summarize and Define. A click places it:

- Text, Question and Heading open an active note or heading where the preview sat. Question places
  the “ as if typed, so a lone quote fades as usual. An empty note or heading goes away when
  editing ends.
- Rename, Summarize and Define act on the clicked item, as their shortcut would. On empty canvas,
  Define opens `/define ` there; Rename and Summarize stay picked up.
- Add File opens the file browser.

Escape puts a tool down; dragging or scrolling pans; leaving the page puts it down.

## Boxes, moving and resizing

Notes, headings and photos draw a Figma-style box: a 1pt outline with a 7pt square at each corner
in accent green at 50%, constant on screen at any zoom. A photo's box hugs the picture; a note's or
heading's includes its 8pt padding. The box is invisible until the pointer is within 84 screen
points, then fades in over 0.15s, and stays while resizing.

- **Move:** the canvas grip, turned on its side, sits centred 8pt above the top line, hidden until
  the box shows and glowing (75%, soft green shadow) while hovered or dragged. Dragging it, or
  anywhere along the top edge between the corners, moves the item — with snapping, Trash and the
  sidebar — and never resizes. Notes also keep their grip before the text.
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

`WorktreeCanvasPointer` tracks the pointer in canvas space but publishes only `nearIDs`, which
changes when the pointer crosses a box's 84-point line, so moving the mouse re-renders nothing
until a box should appear or disappear.

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
  **(Copy) Title**.

Known limitation: replacing a conversation that is open on the conversation page leaves the page
showing its old copy until it is reopened.

## Trash

Drag an item by a grip onto the controls' Trash to delete it. Click Trash for a docked card (28pt
padding and corners) with a Trash heading and Empty action. Each Worktree keeps its ten newest
deleted items, newest first; the oldest is discarded when an eleventh arrives. Rows have 12pt
horizontal and 8pt vertical padding, 16pt corners, type icons with accessibility labels, two equal
columns with a 24pt gap, and a 50% primary-canvas hover background. Notes show their text,
headings title-cased text, and photos an original-aspect thumbnail with 8pt corners.

Drag a row onto the canvas to restore it there; cancelled drags leave it in Trash. Empty asks for
confirmation and discards everything. Undo cannot recover items discarded by overflow or Empty.
Pending model work and empty drafts never enter Trash.

## History

⌘Z undoes and ⇧⌘Z redoes up to 20 canvas actions per open Worktree: adding, deleting, moving,
resizing, renaming, completed definitions and summaries, and finished text edits. A drag, resize
or key-press resize is one action. Text fields use native undo while editing (also 20 deep); when
it runs out, the shortcuts reach canvas history. Camera movement never enters history. Closing a
Worktree clears its history, and redoing a model result never re-runs generation.
