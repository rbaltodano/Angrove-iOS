# Worktree (macOS)

A free-form canvas page for exploring ideas with questions and slash commands. Mac only, opened
from the sidebar (`MacDestination.worktree`). Code lives in `macOS/Features/Worktree/`.

Worktree content is held in memory by `MacWorkspaceView` (one `WorktreeBoard`), so it survives
page changes but **not relaunch**. Nothing on the canvas is persisted yet.

## Files

| File | Owns |
| --- | --- |
| `MacWorktreeView.swift` | Canvas camera (pan, pinch, ⌘-scroll, ⌘= / ⌘− / ⌘0), keyboard routing, title, controls pill, Commands card |
| `WorktreeBoard.swift` | All canvas state and actions: items, selection, command field, model work, sidebar copy/replace |
| `WorktreeItemView.swift` | One item: plain text, question window, Insight card, summary; grip, resize edges, label, selection lift |
| `WorktreeTextEditor.swift` | Borderless `NSTextView` for canvas text, labels and the command field, with the command sweep |
| `WorktreeCommands.swift` | `/rename`, `/define`, `/summarize` parsing (tested in `MacWorktreeCommandTests`) |
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
- **Selection:** windows and Insight cards are selectable: 0.5% lift on hover, 1% when selected,
  with the Insight card's drop shadow (hidden when unselected). Esc closes a card, then deselects.
- **Trash:** drag an item by its grip onto the controls' Trash to delete it.

## Commands

Typing `/` opens a command field 16pt right of the selection, or of the pointer with nothing
selected. With something selected, `/` opens it even from another text field. Recognised commands
turn green with the composer's sweep. Commands can follow a question
(`"…" /rename /summarize`) and queue behind its answer.

| Command | Needs a selection | Does |
| --- | --- | --- |
| `/rename` | No | Generates a label with the conversation-title prompt; `/rename Text` sets it. With nothing selected it names the Worktree. |
| `/define term` | Yes | The field becomes an Insight card defined in the selection's context. |
| `/summarize` | Yes | Writes a brief summary (`AngroveModel.summarize`) of the selection beside it, as editable text. |

Unrecognised commands, misformed ones (`/define` with no term), and selection-dependent commands with
nothing selected are struck through, then blur away; nothing runs.

Labels are Libre Baskerville Italic 28 in accent green, editable in place. Pending model work
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
