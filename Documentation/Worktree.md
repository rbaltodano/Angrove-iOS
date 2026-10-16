# Worktree (macOS)

A free-form canvas page for exploring ideas with questions and slash commands. Mac only, opened
from the sidebar (`MacDestination.worktree`). Code lives in `macOS/Features/Worktree/`.

The page opens on saved Worktrees shown as cards (`MacWorktreeHomeView`); a card opens its
canvas. `WorktreeLibrary` holds the saved documents and the open `WorktreeBoard`. Boards save about
a second after each change, when leaving, and at quit, to the encrypted file-backed personal store
(`WorktreeStore`, under `Aquinas/Worktree`). Model work still in progress is not saved.

## Files

| File | Owns |
| --- | --- |
| `WorktreeLibrary.swift` | Saved documents (`WorktreeDocument`), the store, and the open board |
| `MacWorktreeHomeView.swift` | The page: Worktree cards, empty state, New Worktree, opening and closing |
| `MacWorktreeView.swift` | Canvas camera (pan, pinch, ⌘-scroll, ⌘= / ⌘− / ⌘0), keyboard routing and tool shortcuts, title, controls pill |
| `WorktreeTextBox.swift` | A note's Figma-style text box: resize edges and corners, shown near the pointer |
| `WorktreeToolsCard.swift` | The Tools card and a picked-up tool's pointer preview (`WorktreeToolPlacement`) |
| `WorktreeBoard.swift` | All canvas state and actions: items, selection, command field, model work, sidebar copy/replace |
| `WorktreeItemView.swift` | One item: plain text, question window, Insight card, summary; grip, resize edges, label, selection lift |
| `WorktreeTextEditor.swift` | Borderless `NSTextView` for canvas text, labels and the command field, with the command sweep |
| `WorktreeCommands.swift` | Command parsing, short forms, and `WorktreeTool` (tested in `MacWorktreeCommandTests`) |
| `WorktreeConversationDrop.swift` | Sidebar ⇄ canvas drag payload and the conversation chip |

## Interaction

- **Typing anywhere** (outside a text field) starts a text item 16pt right of the pointer, holding
  what was typed. Keys typed before it takes focus are added to it. Clicking only selects.
- **Return submits** everywhere; Shift-Return breaks the line.
- **Questions:** text opened with a quotation mark, submitted, becomes a conversation window. It
  animates from the text's chrome (8pt padding, no border) to a card (28pt, border), and is answered
  through the same `MacConversationState` and `ModelResponseCard` as the conversation page
  (thinking, reveal, Insights). These sessions set `savesConversation = false`, so they stay out of
  the sidebar.
- **Windows:** sticky per-turn questions, a top fade under the pinned question and a bottom fade at
  the window edge, follow-ups through the conversation composer (`MacCommandEditor`), browser-style
  resizing (sides, bottom, bottom corners), drag by the grip or top edge.
- **Alignment:** while dragging, an item's left, centre or right (and top, centre or bottom)
  snaps to another item's within 8pt, and an accent-green guide draws from its centre, running
  84pt past both items with faded ends. Guides fade on release (`WorktreeBoard.move`).
- **Selection:** windows, Insight cards and headings (double-click a heading to edit) are selectable: 2% lift on hover, 5% when selected,
  with the Insight card's drop shadow (hidden when unselected). Esc closes a card, then deselects.
- **Trash:** drag an item by its grip onto the controls' Trash to delete it.
- **Dot grid:** the Insight Tree's grid with its drifting field off, so the dots rest invisible.
  Selecting something, or something finishing, sends one Insight-hover pulse from it.
- **Empty canvas:** an Insight Tree–style empty state explains typing, questions and the Tools card.
- **Controls:** Add, Tools, Model Tasks and Trash. Add (+) is the conversation's menu: Insights and
  Passages place cards from the library; Photos… and Image File… place pictures.
- **Fast typing:** keys typed before a just-opened field takes focus (letters, Return, Delete,
  Esc) act on that field, so a quickly typed command still runs.

## Commands

Typing `/` opens a command field 32pt right of what it acts on: the selection, else the hovered
item, else (by the pointer) the whole Worktree. With something selected, `/` opens it even from
another text field. ⇧- or ⌘-click selects several: `/rename` names each, while `/define` and
`/summarize` read them together. A lone `/` (or a lone quotation mark in a note) left for three
seconds fades away. Recognised commands
turn green with the composer's sweep. Commands can follow a question
(`"…" /rename /summarize`) and queue behind its answer.

| Command | Needs a selection | Does |
| --- | --- | --- |
| `/rename` | No | Generates a label with the conversation-title prompt; `/rename Text` sets it. With nothing selected it names the Worktree. |
| `/define [term]` | Only without a term | Defines the targeted material, or the typed term in its context. Existing Insights need an explicit term. |
| `/summarize` | Yes | Writes a brief summary (`AngroveModel.summarize`) of the selection beside it, as editable text. |
| `/heading [Text]` | Only without text | Adds a heading from the target or supplied text; existing headings cannot be targeted again. |
| `/file` | No | Opens the file browser (pictures only for now); chosen pictures follow the pointer to be placed. |

Each command has a one-letter short form: `/h`, `/r`, `/s`, `/d`, `/f`. Like the full names, they
only count standing alone, so `and/or` stays text. `/help` is retired; Worktrees that already hold
its card still show it.

Unrecognised commands, misformed ones (bare `/define` with no target), and selection-dependent commands with
nothing selected are struck through, then blur away; nothing runs.

Labels are Libre Baskerville Italic 28 in accent green. Headings and labels arrive one word at a
time, like page titles, and turn into editors when clicked. Pending model work
breathes while queued and takes the "Thinking..." shimmer once running (`WorktreeWorkStyle`).
Queued work uses `ModelTaskKind.labelWorktreeItem`, `.summarizeWorktreeItem` and `.defineInsight`.

## Sidebar ⇄ canvas

- **Sidebar → canvas:** drag a sidebar conversation onto the canvas. It lands as the sidebar chip,
  then opens into a window sized like the last selected or made window, labelled with its title.
  The window holds a **copy**: it shows the last 5 turns and loads 5 more when scrolled to the top.
  `/summarize` and `/define` still read the whole conversation, trimmed to the newest turns that fit
  the on-device context behind any compacted summary (`WorktreeBoard.fitting`).
- **Canvas → sidebar:** drag a window by its grip over the sidebar; it becomes the chip (drawn at
  window level, since the canvas is clipped). On drop the window springs back and the sidebar gets a
  **copy**, named by the window's label or, without one, by the model. A window that came from the
  sidebar asks to **Replace** that conversation or **Keep Both**.

Known limitation: replacing a conversation that is open on the conversation page leaves the page
showing its old copy until it is reopened.


## Place and history

Each saved Worktree remembers its pan and zoom, including across page changes and app launches.
Older documents open at the default view. Camera movement does not enter undo history.

⌘Z undoes and ⇧⌘Z redoes up to 20 canvas actions per open Worktree. Adding, deleting, moving,
resizing, renaming, completed definitions/summaries and finished text edits enter history. A drag
or resize is one action. Text fields use native text undo while editing, also capped at 20;
when their text history is exhausted, the shortcuts reach canvas history. Closing a Worktree
clears its undo history. Undoing model results does not re-run generation on redo.

Choosing **Keep Both** for a window copied from the sidebar names the new sidebar conversation
**(Copy) Title**. Replace retains its existing naming behavior.


## Photo placement

Photos… and Image File… prepare photos for placement instead of adding them immediately. A
120-point thumbnail follows the pointer with its top-left corner 24 points right and below the pointer, a spring trail
and overshoot, and a 2° clockwise tilt. Horizontal motion adds +1° clockwise to the right or
-1° to the left, then settles back to 2°. Reduce Motion removes the trail and changing tilt.
Click anywhere on the canvas, including over an existing item, to place the next selected
photo. Escape cancels the remaining photos; leaving the page also clears placement.

Placed photos retain their proportions, fit inside 1000 × 1000 canvas points without enlarging
smaller originals, scale from 0.98 to 1, and pulse the dot grid from their centre. Each placement
is one undoable action. Only placed photos are saved.


Placed photos are upright: the attachment picker's decorative rotation is discarded for Worktrees.
Drag a side edge to crop horizontally or vertically; the image fills the shape, centered on both
axes, and scales as needed when the shape expands. Within 16 screen points of the original aspect ratio, the dragged edge snaps to
that ratio at any canvas zoom. Drag any corner to scale the current crop and its image together
proportionally, keeping the opposite corner fixed. Crop state saves with the photo, and each
edge or corner drag is one undoable action. Cropping preserves the original image data.


## Object commands — October 16, 2026

Slash targets any hovered object, including photos, notes, headings, Insights and the help card.
Hovering an object outside the current selection targets that object; hovering within a multi-
selection keeps the group. A lingering text-field focus does not prevent targeting another object.
`/define term` works with or without a selection; selected material provides context. Bare
`/define` defines the selected material (inferring a short subject for a photo or long selection).
Bare `/define` on an existing Insight is invalid; provide an explicit term instead. Without a
selection or term it uses the existing strike-through dismissal. `/heading` takes its text from
selected material when omitted, but targeting an existing heading is invalid.

Photo summaries, inferred subjects, labels and definitions send real image attachments through
the shared model and task queue. Engines without vision fail explicitly. Pending requests capture
their selection, and an old invalid-command dismissal cannot close a newly opened command field.


Submitted `/summarize` shows **Summarizing…** instead of the slash command, breathing while
queued and shimmering while running. Completed summaries use the conversation's completed-answer
word reveal, then become ordinary editable notes. Clicking during the reveal opens editing
immediately. Reduce Motion shows the full result immediately. Saved notes and redo do not replay
the initial reveal; complete summary text is saved even while its presentation is animating.


During photo placement, scroll/trackpad input pans the canvas (⌘-scroll and pinch still zoom),
and mouse dragging pans without placing. A click places the photo on release. Photos grow 5%
on hover, retaining that scale when selected. Definitions can recover a likely intended spelling
through the shared model; corrected Insights use the corrected title, and unresolvable words
produce a clarification error rather than an invented definition.


## Trash

Click Trash to open a docked card with 28-point padding and corners, a Trash heading and Empty
action. Each Worktree persists its ten newest deleted items, newest first. Rows have 12-point horizontal and 8-point vertical
padding, 16-point corners, type icons with accessibility labels, and two equal columns with a 24-point gap, and a 50%-opacity primary-canvas
hover background. Notes show their text, headings show title-cased text, and photos show an
original-aspect-ratio thumbnail at the preview row’s height with 8-point corners.

Drag a row onto the canvas to restore it at the drop point and remove it from Trash. Canceled
drags leave it in Trash. The oldest item is permanently discarded when an eleventh is deleted.
Empty requires confirmation and permanently discards all Trash items. Undo cannot recover items
purged by overflow or Empty; unrelated undo history remains available. Pending model work and
empty transient drafts do not enter Trash. Model Tasks and Trash open one at a time.


Definition requests display **Defining...** (queued breathing, running shimmer). If generation
fails, the same item reveals **Could not define <term>** using the summary/answer animation;
1.5 seconds after reveal it blurs/fades away. Definition failures do not open an alert and
are excluded from saving, Trash and undo. False “unrecognized term” results receive one direct-
definition retry through the shared model before surfacing a failure.


Canvas-item removal and command-field dismissal emit a dot-grid ripple at their former centre,
including invalid commands, lone slash/quote drafts and inline definition errors. Invalid command
text and its strike-through use accent red. Definition error text reveals in accent red and
remains for 1.5 seconds after its reveal before the blur/fade dismissal.


## Tools — October 16, 2026

**Tools** (⌘ symbol) in the controls opens a docked card listing Text, Question, Heading, Rename,
Summarize, Define and Add File with their commands and shortcuts. Tools, Model Tasks and Trash open
one at a time.

| Tool | Short | Command | Shortcut |
| --- | --- | --- | --- |
| Heading | `/h` | `/heading` | ⌘H |
| Rename | `/r` | `/rename` | ⌘R |
| Summarize | `/s` | `/summarize` | ⌘S |
| Define | `/d` | `/define` | ⌘D |
| Add File | `/f` | `/file` | ⇧⌘K |

**Shortcuts** act on what is selected, else the item being edited, else the hovered item. A
hovered item never overrides the selection, unlike `/`. The command appears in the command field
as if typed, then runs. With nothing to act on, the command waits typed by the pointer
(`/define `) for a term or text. Shortcuts are taken even while typing in a field. On the Worktree
page they win over the menus: ⌘H adds a heading here instead of hiding the app (⇧⌘H is
still Home). App-wide, Swap
Panes moved to ⇧⌘S and Previous Page lost ⌘R for now.

**Clicking a row** picks the tool up. A 50% preview follows the pointer with the photo
placement's spring trail and tilt, styled like what it makes: “Text” and an opening “ as a note,
“Heading” at the heading's font, size and color, scaled with the canvas zoom. Rename, Summarize
and Define show **Click on something to …**. A click places the tool and puts it down:

- Text, Question and Heading open an active, editable note or heading where the preview sat.
  Question places the “ as if it were typed there, so a lone quote fades as usual. An empty note
  or heading goes away when editing ends.
- Rename, Summarize and Define act on the clicked item, as their shortcut would. On empty canvas,
  Define opens `/define ` there for a term; Rename and Summarize stay picked up.
- Add File opens the file browser instead of following the pointer.

Escape puts a picked-up tool down, then closes the Tools card. Dragging or scrolling pans as
during photo placement; leaving the page puts the tool down.


## Note text boxes

Plain notes draw a Figma-style text box: a 1pt frame with a 7pt square at each corner, in accent
green at 50%, both constant on screen at any zoom. It is invisible until the pointer is within 84
screen points of the note, then fades in (0.15s); it stays while resizing. Side edges set the
wrap width (the left edge keeps the right side fixed), top and bottom set a minimum height, and
corners do both. Width is at least 40pt and height one line; text never overflows, so a box
shorter than its text grows to fit. The size saves with the note and each drag is one undoable
action. The pointer's canvas position lives in `WorktreeCanvasPointer`, observed only by these
boxes. Headings, windows, Insights and photos keep their own chrome.
