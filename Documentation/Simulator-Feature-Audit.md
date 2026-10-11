# Simulator feature audit

Running log of a hands-on pass through every user-facing feature in the iOS Simulator. Other
agents: read this before touching a feature listed here; append new findings rather than
rewriting old ones, and mark items **Fixed (<commit>)** when resolved.

## Setup (2026-10-11)

- Build: `main` @ `f89144f`, Debug, iPhone 17 simulator (iOS 27.0).
- Launched with `--litert-force-cpu` (GPU path fails in the simulator), so live answers are slow
  (~35 s+); latency here is not representative of device.
- Existing simulator app data was kept (backed up first). Keyboard prediction/autocorrect off.
- Simulator is not final validation for model quality, thermal, or memory behavior.

Severity: **Bug** = broken or wrong behavior · **Adjust** = works but needs polish ·
**OK** = works as specified.

## Top issues (fix first)

1. **Global Insights "Update?" → Yes does nothing** — the Global tree never fills; reproducible.
   See "Global Insights — update prompt (retest)".
2. **Conversation tree lost its Node Concepts after the conversation was added to a Study Topic**
   (empty state, then only a generic hub after relaunch). See "Cross-feature".
3. **Branch → parent Node Concept no longer visible** in the conversation tree.
4. **Color Scheme (Dark/Light) is not persisted** across launches (`ContentView.swift:81` `@State`).
5. **Library search keyboard stays up over the reader** and can't be dismissed by scrolling.
6. Copy bugs: "Theo's map" hardcoded name in the tree empty state; "Search Study Topcis" typo.

Most core flows work: live answers with sources and thinking, definitions, save, read-aloud,
Branch, Study rotation, slash commands, Library reading/listening, conversation management,
Study Topic creation, Settings, and dark mode rendering.

## Findings by feature

### Home

- **OK** — Greeting, date, activity grid, stats, Question of the Day card, Getting Started card,
  Where You Left Off, Midpoint to Explore, and Read Material all render with existing data.
- **Adjust** — Scrolled content passes under the status bar and the floating side-menu button with
  no top fade/backdrop (e.g. "Where You Left Off" heading is cut by the menu button).
- **Adjust** — "Midpoint to Explore" body copy lacks a final period ("…Who knows what you'll learn").
- **Adjust** — Read Material subtitles ("Referenced 5 times across your conversations.") use very
  loose serif line spacing compared with the title above them.
- **Question** — Stats show "0 Open" next to "7 Conversations"; unclear what "Open" counts.
- **Adjust** — Navigating sidebar → Home briefly shows a blank page with the Insights page's Search
  pill still visible before Home appears.
- **Retest** — Tapping "Summa Theologica" in Read Material appeared to open the Global Insights page
  instead of the Library reader (tap may have landed during scroll momentum; see retest below).
- Not shown with this data: Today in History, Loose Thread, Terms You Glossed Over, Your Quote
  (expected to be absent when nothing qualifies).

### Side menu

- **OK** — Opens from the menu button; Home/Library/Insights/Conversations/Study Topics, Recents,
  Settings gear, New Conversation; Insights badge shows "1".
- **Adjust** — Study Topics row icon renders blurred/soft compared with the other icons.

### Global Insights (Insight Library canvas)

- **Bug** — "Insights will gather here… Theo's map of connected ideas." Empty-state copy hardcodes
  a person's name ("Theo") — `InsightTreeView.swift` `EmptyInsightTreeView`. Should use the
  preferred name or neutral copy.
- **Adjust** — Empty state says "Save insights…" while 7 Insights already exist (the tree is just
  waiting on the "Update Global Insights Tree?" prompt). Copy should point at the prompt instead.

### Conversation — composer and attachments

- **OK** — Plus menu (Insights / Passages) opens; Insight picker sheet with This Conversation /
  All segments, empty state, paging 1/7, and quoting an Insight into the draft all work.
- **Adjust** — Insight picker card titles truncate ("Christian Sacrament…") because the three
  action icons take the row; consider wrapping to two lines.
- **Adjust** — Insight picker empty-state icon briefly renders blurred during the sheet animation.
- **Adjust** — After quoting an Insight, the draft scrolls to the very top so the attachment chip
  sits underneath the top-right tree button and the Question of the Day header is scrolled away.
- **Adjust** — Conversation content scrolls under the floating header buttons and compact title
  with no backdrop; the compact title "How does the tens…" overlaps the large "Question of the
  Day" heading during scroll.
- **Adjust** — The scroll-to-bottom arrow is shown even when there's nothing below (empty draft).
- **Adjust** — Draft placeholder "Ask a question…" is right-aligned in an empty conversation,
  which reads oddly on first view.

### Conversation — live answer, thinking, sources

- **OK** — Live question with a quoted Insight answered in 38 s (CPU sim). Status moved
  Loading → Thinking → Writing Response; approach line and sources streamed first; "Thought for
  38s" disclosure, Show/Hide Thinking, "Corpus Grounded" note, expandable source passage, and an
  inline citation chip all render. Tree mapping (2/2 Mapping…) queued automatically afterwards.
- **OK** — Model Tasks card opens from the dock (User Question, 0 of 1, stop control).
- **Adjust** — Two retrieved sources both read just "Summa Theologica" with no article/question
  label, so they look like duplicates until expanded.
- **Adjust** — "Corpus Grounded" uses a question-mark-in-circle icon, which reads as "unknown"
  rather than "grounded".
- **Adjust** — "Hide Thinking" shows a right-pointing chevron; the opener uses a down chevron.
- **Adjust** — Inline citation chip renders as a large block ("Summa Theologica, FIRST PART OF THE
  SECOND PART") in all caps, on its own line, with the sentence's period stranded after it.
- **Adjust** — The context gauge beside "Idle" is a small partial arc that reads like a loading
  spinner at a glance (initially mistaken for one during this audit).
- **Adjust** — With the Model Tasks card open, the scroll-to-bottom arrow floats over source rows.
- **Adjust** — The "Updated" pill on the tree button collides with the compact conversation title
  ("How does the tens..").
- **Adjust** — Dock status labels vary (Loading…, Thinking…, Mapping…, Parsing…); spec only
  documents Idle/Thinking. Fine if intentional, but update FUNCTIONALITY.md §4.

### Definitions (aq:// links)

- **OK** — Tapping "grace" breathes the link, queues a Define task, shows a "Grace" completion
  pill; tapping the pill opens the definition card. Save (bookmark fills, tree shows "Updated"),
  read-aloud with per-word highlight, and collapse after reading all work.
- **Adjust** — Expanded definition card still shows the "…" more pill after the full text is
  visible; after reading collapses, the sheet leaves a large empty band below the card.
- **Adjust** — Docked/tree card text ends with "natural law…." (period + ellipsis).
- **Note** — Taps on links during scroll momentum just stop the scroll (expected iOS behavior, but
  the long reveal fade means users may tap while content is still settling).

### Conversation Insight Tree

- **OK** — Opens from the tree button with Back + Search/Idle dock. New Node Concept (from
  automatic analysis) and the saved "Grace" Insight appear; tapping Grace hovers it and docks its
  card with Select / Ask / Study.
- **Adjust** — Tree opens blank for ~1–2 s, then content appears without being fit to the
  viewport: the Node Concept ("…logical Freedom") is clipped off the left edge.
- **Adjust** — Insight-to-concept connector is nearly invisible at default zoom.

### Study (3D) and Branch

- **OK** — Study opens from a hovered Insight: Exit capsule, ring, Ask/Branch dock. Branch shows
  the tool card, count selector, and Loading; flashing Insight placeholders with connectors appear.
- **Bug** — Entering Study from a hovered Insight leaves the parent Node Concept off-screen left
  (only "…edom" visible) instead of flying it into the 300×300 slot above the ring
  (Study-Tool.md "Entry and exit" step 3).
- **Adjust** — Branch count control is "+ 2 New Insights −" (plus on the left, minus on the right),
  the reverse of the usual stepper order.
- **Adjust** — First frame of Branch shows the promoted "Grace" label half-clipped with a
  placeholder Insight icon on top of the node; settles a moment later.
- **OK** — Branch (3) completed in ~25 s: "Grace" promoted to a Node Concept with children Vicious
  Customs, Corrupt Habits, Natural Law; ring drag rotates; Exit returns to the tree with the new
  node hovered; its docked card lists the three children.
- **Adjust** — Right after Branch, one child ("Natural Law") sits directly in front of the node,
  hiding the lower half of its icon and label, and another child is hidden behind the tool card
  until the ring is rotated.
- **Bug (likely)** — After Branch and Exit, the original parent Node Concept ("…logical Freedom")
  is no longer visible anywhere in the conversation tree, even at minimum zoom; only a lone blue
  "new" dot remains near where it was. Study-Tool.md says the new node keeps a visible
  connection to its old parent.
- **Adjust** — Pinch-zooming out hides all labels, leaving only icons and blue dots; minimum zoom
  is reached quickly, so a small tree can't be zoomed out further than this.

### Context card and slash commands

- **OK** — Context gauge opens the Context card (442 / 4.1k tokens, Compact, Clear).
- **OK** — Typing "/" lists all seven commands; `/rename <name>` renamed the conversation
  (header + Recents updated); `/insights` opened the Insights sheet (1/4 in This Conversation).
- **Adjust** — The slash menu sits behind the dock and scroll arrow; "/topic" and "/insights" are
  partly covered.
- **Adjust** — Header truncates short titles ("Grace and Freedo…") even though there is room.
- **Adjust** — Insights sheet card icon (speech bubble) renders blurred.
- **Not tested** — `/compact`, `/clear`, `/new`, `/topic` (destructive or covered elsewhere).

### Library

- **OK** — Catalog (Recently Opened, categories), search ("Summa" → Summa Theologica), loading
  state with leaf + "Loading", reader with Contents sheet, section jumps, prev/next section pill,
  Listen → Pause with per-word highlight and "Last listened here" marker after pausing.
- **Bug** — Library search keyboard stays up after opening a result; it covers the reader and
  isn't dismissed by scrolling. It persisted until returning to the Library and pressing Search.
- **Adjust** — Reader shows raw source artifacts: long underscore rules ("_____") between headings,
  which also get read aloud/highlighted as words.
- **Adjust** — Opening heading splits mid-parenthesis: small caps "FIRST PART (FP" over large italic
  "QQ 1-119)". Headings also duplicate (large italic heading, then the same text again in caps).
- **Adjust** — Section pill labels Summa *Parts* as "Article 1 / Article 2 / Article 3".
- **Adjust** — Table of Contents only lists the five Parts (no questions/articles) and truncates
  long entries with no wrap; tapping outside doesn't dismiss it (only the Contents button does).
- **Adjust** — Listen takes ~5 s to start with no loading feedback, so the first tap looks dead;
  a second tap then pauses immediately.
- **Adjust** — Background "Consolidating…" status pill floated over the search results.

### Open Conversations

- **OK** — Search field, Recent/Pinned/Date Created tabs, cards with preview + Insight chips,
  "…" menu (Rename, Pin/Unpin, Add to Study Topic, Delete); Pin shows the pin glyph and the
  conversation under Pinned; Unpin restores it.
- **Adjust** — Background conversations below the first card render faded/low-contrast (looks
  disabled) — confirm intended.
- **Adjust** — Leaving the Library while read-aloud is paused keeps a speaker button in the dock on
  other pages (Conversations shows "🔊 + New Conversation"), with no label explaining it.

### Study Topics

- **OK** — Empty state, New Study Topic (inline editable title, description placeholder,
  scoped search), Add Existing Conversation sheet with multi-select "Add 1 Conversation",
  "Update Tree for Audit Topic?" prompt, topic tree opens with a "Related Insights" hub.
- **Bug** — Typo in search placeholder: "Search Study Topcis".
- **Adjust** — Empty-state copy mentions "files", but file attachments are deferred post-launch
  (FUNCTIONALITY.md §3).
- **Adjust** — After adding a conversation, the "+ New Conversation / + Add Conversation" pill
  floats over the middle of the conversation card, hiding two of its Insight chips, and the
  "Update Tree for Audit Topic?" prompt overlaps the card's title row.
- **Adjust** — Adding a conversation re-focuses the topic title field and raises the keyboard
  (first time this also triggered the iOS swipe-typing tutorial sheet).
- **Adjust** — Topic tree: "Related Insights" hub label is very low contrast; the tree initially
  shows only one Insight while mapping runs ("1/2 Mapping…") with two stray blue "new" dots.

### Cross-feature: Study Topic membership vs. conversation tree

- **Bug (high, needs repro)** — After adding "Grace and Freedom" to a new Study Topic and
  answering Yes to "Update Tree for Audit Topic?", the conversation's own Insight Tree changed:
  1. Immediately after, it showed the empty state ("Insights will gather here…") even though the
     conversation had a Node Concept, the Branch-promoted "Grace" Node Concept, and three child
     Insights minutes earlier.
  2. After an app relaunch it shows only a generic brain-icon hub with three Insight chips; the
     "Grace" Node Concept and the automatic "…logical Freedom" Node Concept are gone.
  Repro: conversation with a Branch result → Study Topics → New Study Topic → Add Conversation
  → Yes on the update prompt → open the conversation → tree button. Data stores are encrypted,
  so it is not yet confirmed whether this is lost data or a display/scope bug.

### Appearance / theme

- **OK** — Settings → Appearance: Color Scheme (System/Light/Dark), Conversation and Insight Tree
  background pickers with live preview. Dark mode renders cleanly on Settings, side menu,
  conversation, and tree.
- **Bug** — Color Scheme = Dark does not survive an app relaunch; the app returns to System
  (Light on this simulator). Root cause: `colorSchemeOverride` is a plain `@State` in
  `App/ContentView.swift:81` and is never persisted. (Background choices do persist per spec.)
- **Adjust** — Side menu "Current Topic" still reads "Question of the Day" after the conversation
  was renamed "Grace and Freedom".
- **Adjust** — Question of the Day text is wrapped in straight quotes and contains nested straight
  quotes (`"How does … define "good" shape …?"`); use curly quotes or drop the outer pair.

### Settings

- **OK** — Settings index (General / Conversation / Model / Support, version footer), Personalization,
  App Experience (start screen, haptics, Reset Settings), Privacy & Data (App Lock, export/import,
  delete actions), Import opens the system file picker, Report a Bug form (required/optional
  fields, clear privacy copy), User Guide index with blue unread dots that clear after a topic is
  opened, topic page with an animated example.
- **Adjust** — On-device Model page shows only explanatory text — no readiness/status row
  (ready, size on disk, verify/repair) even though the row subtitle promises "Download,
  readiness, and recovery".
- **Adjust** — "Delete all Clipped Passages" capitalization differs from sibling rows
  ("Delete All Conversations", "Delete All App Data").
- **Adjust** — User Guide hero title briefly renders blurred ("Step by Step.") during its entrance.
- **Not tested** — Clear Insight Tree / Delete * actions (destructive), Export (share sheet),
  App Lock (needs device auth), Audio, Text & Display, Conversation Defaults, Notifications,
  Licenses, Privacy Policy link (external).

### Global Insights — update prompt (retest)

- **Bug (high)** — "Update Global Insights Tree?" → **Yes** does nothing: 4 attempts across two
  launches (including after a relaunch and with a flush tap), the prompt stays, the canvas stays
  on the "Insights will gather here" empty state, and the side-menu badge stays at 7. Other
  buttons on the same screen respond normally. Code path: `ContentView.updateGlobalInsightTree()`
  (`App/ContentView.swift:1859`). Suspects: (a) the post-reconcile guard
  `globalTreeInsights == existingSnapshot && collectedDefinitions == incomingSnapshot` fails because
  `collectedDefinitions` is rewritten in place by the `LocalInsightTreeSeedStore.didChange`
  observer (`ContentView.swift:838`) while reconciliation runs, which silently re-shows the
  prompt; or (b) the Yes button's hit area is covered by the Search dock. Add logging or a
  focused test before fixing.

### Response actions

- **OK** — Long-press a plain word → Copy / Define / Read from here; Define fades the word and
  queues the definition ("Parsing…").
- **OK** — Thumbs-down opens the response-specific Report a Bug sheet with the "Include this
  response and the question before it" opt-in **off** by default and Send disabled until a note
  is typed (matches the privacy rule in AGENTS.md).
- **Retest by hand** — The opt-in toggle did not flip from simulator taps (twice), so the preview
  of the attached text could not be verified. May be a tooling issue; confirm on device.

## Not yet covered

Midpoint (multi-select + weights), Make Node in the Global tree, Ask from the tree, Clouds
backgrounds, Today in History / Loose Thread / Terms You Glossed Over / Your Quote cards (no
qualifying data), `/compact` `/clear` `/new` `/topic`, App Lock, Export, all Delete/Clear
actions, Notifications, Audio / Text & Display / Conversation Defaults settings pages, small-phone
(iPhone SE-class) layouts, landscape lockout, Reduce Motion, VoiceOver.
