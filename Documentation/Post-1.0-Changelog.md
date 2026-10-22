# Post-1.0 changelog

Everything added after the 1.0 build submitted to App Review on 2026-10-15. Add one entry per
change, newest first, under the date. Tag each entry by platform:

- **[iOS]** or **[Shared]**: touches the iPhone app. Write it so it can become patch notes: what
  changed for the person, why, and any model, storage, privacy, or performance effect.
- **[macOS]**: Mac-only. Keep it brief.
- **[Tooling]**: diagnostics, evaluation, conversion; ships in neither app.

1.0 baseline: repository `main` at `8ff5713` plus the working tree used for the submitted
archive. The submitted 1.0 build is build 6 (October 17, 2026).

## Mobile patch notes (draft)

Collected from the [iOS] and [Shared] entries below.

- Updated the on-device AI runtime (Google LiteRT-LM 0.14 → 0.17.1). Answers, model and
  privacy are unchanged; this prepares for larger models on Mac. The app download grows by
  about 17 MB. *(Pending iPhone device validation before release.)*
- New Search in the side menu. Find any conversation, saved Insight or Study Topic by its name,
  or a conversation by something said in it, and filter to one kind with All, Conversations,
  Insights or Study Topics. Matching words are highlighted; tap a result to open it.

## 2026-10-22

- **[Shared] Global search (side menu on iPhone, sidebar and ⌘K on Mac).** A Search row under
  the logo opens search over the page (on Mac, over the content area beside the sidebar): a canvas
  veil grows from the top on the website menu's curve while the field fades in from a blur and
  settles from 105% scale. A downward swipe lowers the keyboard. The selected sidebar row now uses
  Canvas Primary (half strength in dark mode). Results are ranked (whole title, title start,
  word start, anywhere, then message passages) and blur away or slide into place as you type.
  Search fields, results and sidebar selections use a 16 pt corner radius, and every search
  field's magnifying glass is accent green. The global search bar is a Model Controls–style
  capsule, and a search with no results shows the standard “No Matches Found” empty state. It matches conversation titles, then the questions and
  answers inside a conversation (shown as an italic passage), saved Insight titles and Study Topic
  titles, ignoring case and accents; every match is set in bold accent green. All /
  Conversations / Insights / Study Topics filter the list. Choosing a result opens the
  conversation, selects the Insight on the Insights canvas, or opens the Study Topic. Search runs
  on-device over data already stored; nothing new is saved. On Mac, ⌘K toggles it, arrow keys
  move the selection, Return opens and Escape closes. Code: `Shared/Features/Search/`; tests in
  `GlobalSearchTests`.

- **[Tooling] Public documentation reorganized; no app change.** Added a documentation index,
  moved dated handoffs, checklists and release audits into `Documentation/Engineering-Log/`,
  stated the public TestFlight beta in the README and case study, and removed device identifiers
  and home-directory paths from development records.

- **[Tooling] Local checkouts renamed to Angrove; no app change.** The canonical folders are now
  `~/Developer/Angrove-iOS-main`, `Angrove-Foundations` and `Angrove-Backend`, matching the GitHub
  repositories. Documentation, agent instructions and the Debug-only Mac model lookup
  (`MacModelTier`) use the new paths. Bundle IDs and stored-data keys keep the Aquinas name.

## 2026-10-17

- **[Shared] Plain data models moved into AngroveCore; no iPhone behavior change.**
  `ConceptDefinition`/`InsightDefinition`, `HomeQuestionOfTheDay`, `DailyQuestionDraft`,
  `LibraryWork`, `LibraryPassage` and `stableUUID` now live in `Packages/AngroveCore` with public
  initializers matching the old automatic ones; Question of the Day's conversation request stays
  in `Shared` as an extension. Same encoding, same IDs. Verified: both app builds, 12 package tests,
  30 focused Mac tests, and the signed iPhone suite (535 passed before the known photo-layout
  stall; every failing suite not already failing on `main` passed when run alone, 53/53).

- **[Shared] Model controls, completion notifications and Insight cards (committed from another
  session's work).** A persistent global model-controls dock on the Mac (`MacGlobalModelControls`),
  completed-definition notifications that open after their conversation unmounts
  (`MacCompletionNotifications`), and layout changes to the Insight sheet, library and docked
  cards plus `CurrentConversation` on iPhone. Verified: iPhone simulator and Mac builds and the 8
  new card, notification and controls tests. **Owner:** the iPhone-facing parts need patch-note
  wording from whoever wrote them.

- **[Shared] AngroveCore package and platform policy; no iPhone behavior change.** Encryption
  (`LocalDataCipher`, `LocalDataKeychain`), `AngroveAppGroup`, the widget's question store and
  link, and the model manifest and pack types moved from `Shared/Widgets` and `Shared/Services`
  into `Packages/AngroveCore`, linked by both apps and both widgets and tested with `swift test`.
  `ModelPlatformPolicy` replaces the Mac branches in the model store and delivery code; the
  iPhone's policy keeps its storage paths, Debug-only local model and E4B-only packs. One edge:
  a non-E4B manifest on an iPhone Release build now reports the model missing instead of trying
  the E4B pack (no shipping code uses one). Verified: iPhone simulator and Mac builds, 8 package
  tests (`swift test`), 29 focused Mac tests, and the full signed iPhone suite: 587 passed; the 12
  failures are timing tests that also fail on unchanged `main` under full-suite load, or pass
  when their suites run alone (30/30). The full iPhone suite also stalls at a photo-layout test
  on unchanged `main`.

- **[macOS] Question of the Day widget.** New `AngroveMacWidgets` extension (small and medium,
  desktop and Notification Center) built from the iPhone widget's source. Clicking it starts the
  saved question's conversation, or opens Home before there is one. The Mac app and widget now
  share the App Group `group.com.ryanbaltodano.Aquinas-iOS`; the widget's key lives in the data
  protection keychain on the Mac so the extension can read it. Delete All App Data also removes
  the widget's question and key.

- **[macOS] Apple-hosted model delivery.** The Mac app ships for the Mac App Store with managed
  asset packs, as on iPhone: Standard (E4B, `AssetPacks/Mac-Gemma4-E4B.json`) is essential at
  install, Large (12B, `AssetPacks/Mac-Gemma4-12B.json`) downloads on demand from Settings ›
  Model. New `AngroveMacModelDownloader` extension. Settings › Model and Home show download
  progress, verification, retry and failures. A verified local copy (development, or this Mac's
  pre-hosting files) is still used first. Delivery is keyed by pack, so another desktop model needs
only a pack, a tier and a manifest (`Mac-Port.md` › Adding a desktop model). Development builds
never call Background Assets (it trapped in one); `scripts/package_model_asset.py` takes
`--pack mac-e4b|mac-12b` or any `--manifest` with its pinned size and digest.

- **[macOS] Sandboxed local install.** `Tools/install-local-mac.sh` now builds with Xcode's
  automatic signing, so the installed app runs sandboxed with its profiles, App Group and
  extensions. The first sandboxed launch moves the pre-sandbox data into the container
  (`macOS/Resources/container-migration.plist`); the installer copies personal data (not models)
  to `build/mac-data-backups/` first and stops if a container already exists.

- **[Shared] Model delivery code moved to Shared; no iPhone behavior change.**
  `AppleHostedModelDelivery.swift` and `ModelDeliveryState.swift` moved from `iOS/Services/` to
  `Shared/Services/` and take a pack (`AngroveModelAssetPack`), defaulting to the iPhone's E4B
  pack, ID, path and receipt key. `LiteRTModelStore.preparedModelURL()`, the widget source and
  widget typography gained Mac-only branches; the keychain's shared access group adds the data
  protection keychain on the Mac only. Verified: iPhone simulator build (arm64) and the iPhone
  delivery, delivery-state and settings-typography tests pass.

## 2026-10-16

- **[macOS] Board Tools polish.** Tools rows highlight on hover; a picked-up tool shows a hover-style
  label ("Click to add Heading", "Click to summarize"); Add File moved to the "+" menu (with ⇧⌘K
  shown); clicking the canvas closes an open Tools, Trash or Model Tasks card.

- **[macOS] Worktree is now called Boards.** The sidebar, page heading, "New Board" button, empty
  state, delete prompt, Trash and command copy say Board; the docs are `Documentation/Boards.md`.
  Code names and storage keep `Worktree`, so saved Boards still open. Pressing a box edge to resize
  fades the whole box up over 0.5s.

- **[macOS] Worktree box spotlight.** Boxes on notes, headings and photos reveal within 48pt (was
  84pt), and only the part inside a 48pt circle around the pointer shows, with a 24pt soft edge. Item side grips are accent
  green at 50%, matching the boxes.

- **[macOS] Compile fixes for the Worktree Tools commits (b9a52e4…14658c9).** `WorktreeTextEditor.lineHeight`
  is `nonisolated` so `WorktreeTextBoxResize.frame` can use it as a default; the undo shortcut test
  places an Insight now that the `/help` card is gone. No behavior change.

## 2026-10-15

- **[macOS] Worktree page (scaffold).** New sidebar entry opening a blank, pannable canvas (no dot
  background) with its own controls pill (Add, Type, Commands, Trash). Commands toggles a
  Getting Started card. The Type tool (T) places bare text where you click, with a drag grip
  before it; quoted text committed with ⌘Return becomes a bordered, resizable card answered by
  the model, with follow-ups and the latest question pinned. Pinch or ⌘= / ⌘− / ⌘0 zoom; Escape
  puts the Type tool down; dragging an item onto Trash deletes it. Items also move by their top
  edge, and the page has a conversation-style title named from its first question. Conversation
  windows use the conversation page's session and response card (thinking, reveal, Insights)
  with sticky per-turn questions; `MacConversationState.savesConversation` keeps them out of the
  sidebar. Follow-ups send on Return and scroll their question to the top; a clicked window
  becomes active (2.5% larger, shadowed, above others). The page has its own Model Tasks control.
  First command: `/rename` names the selected item with the conversation-title
  prompt, or with text typed after it; "/" opens a command field beside the selection, and
  commands typed after a quoted question queue behind its answer. With nothing selected,
  `/rename` names the whole Worktree. `/define term` turns the command into an Insight card;
  `/define` alone, or any unrecognised command, is struck through and dismissed. Labels are
  editable in place; Insight cards are selectable; "/" opens 16pt from the selection or pointer.
  The Type tool is gone: typing anywhere starts text beside the pointer, and clicking only selects.
  `/summarize` writes a brief summary of the selection beside it; it and `/define` are object
  dependent and invalid with nothing selected. Labels are green
  italic Baskerville; pending model work breathes while queued and shimmers while running.
  Return submits everywhere. Sidebar conversations drag onto the canvas as their chip and open
  into a window holding a copy (last 5 turns, more on scroll up), labelled with their title.
  Dragging a window onto the sidebar saves a copy there (named by its label, or by the model);
  one that came from the sidebar asks whether to replace that conversation or keep both.
  Conversation windows fade out at their bottom edge instead of cutting off.
  Worktrees now save: the page lists them as cards and opens each canvas. New `/heading`
  command; headings and labels reveal word by word. The canvas has the dot grid, invisible at
  rest, pulsing once on selection or completion, and an empty state. `/help` places an accordion card
  of every command, replacing the Commands control. The + control is a menu (Note, Question,
  Heading, Commands). Fixed fast-typed commands losing their Return. Dragged items snap to each other with
  Figma-style alignment guides; headings are selectable. Commands act on the hovered item;
  ⇧/⌘-click selects several. The + menu matches conversations (Insights, Passages, Photos, Image
  File). Lone "/" or quotation marks fade away. Faster canvas rendering while panning.
- **[Shared] `AnimatedDotGridBackground.showsIdleField`.** Defaults to the existing drifting field;
  no iPhone behavior change.
- **[Shared] `ModelTaskKind.labelWorktreeItem` / `.summarizeWorktreeItem` and
  `AngroveModel.summarize`.** Mac-only task kinds and a new `SUMMARIZE_SELECTION` prompt (plain
  prose, no structured output); no iPhone behavior change. Worktree content is not saved yet.

- **[macOS] Switch models without relaunching; Model Tasks lists the real models.** The Model
  Tasks dropdown (formerly placeholders) and Settings › Model list the models this Mac can run
  (Gemma 4 E4B, Gemma 4 12B). A switch applies after the current task: the engine unloads, and
  the next task loads the new package. Verified: 117 Mac tests pass, and an opt-in live test
  answered on E4B, switched to 12B in the same process, and answered correctly (21.5 s including
  verification and load).
- **[Shared] `LiteRTAngroveRuntime.replaceModelStore` and a `modelSwitch` unload reason.** Used
  only by the Mac; no iPhone behavior change.

- **[Tooling] Mac eval batch and 12B results.** `MacModelEvalBatchTests` (opt-in) runs an
  Angrove-Eval set through the Mac model path, in the iPhone probe's results format. Gemma 4 12B
  scored 73/80 against E4B's 72/80 on the same Mac (held-out plus sealed-1, scorer v2). Answers
  took 19.7 s median against 7.5 s. No measurable accuracy gain; see Angrove-Eval `RESULTS.md`.
  New frozen acceptance set `sealed-3` (Angrove-Eval `2a356aa`), unused.

- **[macOS] Model tiers: Standard (E4B) and Large (Gemma 4 12B).** Settings › Model picks the
  tier, gated by installed memory (Large: 24 GiB placeholder). The choice applies at the next
  launch and falls back to Standard when the chosen tier isn't installed. Each tier has its own
  checksum, and inactive tiers' GPU caches are removed at launch. Large is unevaluated and opt-in;
  the default stays Standard. Details are in `Mac-Port.md` › Model tiers. Verified: 115 Mac tests
  pass. The opt-in live test ran 12B through the production model path: 15.6 s cold load,
  1.7 s warm, about 18 s per answer, and the John chapter count correct. One early cold-load run
  stalled with idle native threads and did not reproduce; watch for it.
- **[Shared] `LiteRTAngroveRuntime` takes its context size as an init parameter** (default
  4,096). No iPhone behavior change.

- **[Shared] Mac parity batch: shared Home, Library, Settings and Study Topics code.** Work
  from parallel agents, committed together. iPhone Home dashboard, Library, User Guide,
  Licenses and Settings components moved from `iOS/` into `Shared/` (for example
  `HomeDashboardSections`, `LibraryReaderComponents`, `BundledLicenses`, `UserGuideTopic`,
  `BugReportSubmission`, `SharedFormControls`). Mac Settings, page headings, shortcuts,
  Model Controls hover labels, image attachments and Study Topics were added. The details are
  in `Mac-Port.md` (October 14–15 sections). **Owner:** confirm whether any of this was already
  in the 1.0 archive. The iPhone parts are intended as moves; check them for visible changes
  before writing patch notes.

- **[Shared] LiteRT-LM runtime upgraded 0.14.0 → 0.17.1** (`Vendor/LiteRTLM`). Required for the
  Mac Large tier (Gemma 4 12B cannot load on 0.14).
  - **What changed:** the Swift wrapper is upstream 0.17.1. The binaries are the upstream
    v0.17.0 archives that 0.17.1 references: the iOS checksum matched, and the Mac binary is
    pinned by checksum. The Apple Foundation Models adapter target was dropped (unused).
  - **Patches carried forward**, same behavior as 1.0: F32 `activationDataType`;
    `NativeActivityMonitor`; engine and conversation creation off the cooperative thread pool;
    detached native deletes, with the conversation keeping its engine alive; native-stream
    begin/end tracking; Bazel `BUILD` naming. The full diff against upstream 0.17.1 is
    `Vendor/LiteRTLM/angrove-patches.diff`. Re-apply it for any future LiteRT-LM upgrade.
  - **iPhone effect:** no app source changes. Same model, prompts, F32 precision, 4,096 context
    and greedy decoding. The device framework grows from 43.2 to 60.5 MB. The privacy manifest
    is unchanged, and the re-audit found no new required-reason or network surface (see
    `LiteRT-Privacy-Crypto-Audit.md`). The framework now also embeds Google's `LICENSE` and
    `third_party_licenses.bundle`.
  - **Verified:** Mac and iOS-simulator builds pass. The Mac runtime/queue tests pass (23), as do
    the iOS `LiteRTProductionRuntimeTests`, `LiteRTProbeHarnessTests` and
    `ModelRuntimeLifecycleTests` (90). Mac smoke runs with the vendored package: E4B and 12B
    both answered "21 chapters" for John.
  - **Not yet verified:** physical iPhone (latency, memory, vision, lifecycle stress, F16
    regression set: John 14, Psalm 23, John 11), the full test suites, and an eval run.
    Required before this ships in an iOS update.

- **[Tooling] Gemma 4 12B Mac smoke test: `MAC-12B-GPU-1`.** Stock
  `litert-community/gemma-4-12B-it-litert-lm` package `gemma-4-12B-it.litertlm`
  (6,883,278,368 bytes, SHA-256 verified `58fd31b7…a8b6`), stored in
  `Angrove-Backend/models/LiteRT-Stock/`, outside the app bundle. Host: M4 Pro, 24 GiB.
  Raw diagnostic only (`Tools/MacRuntimeSmoke.swift` plus memory reporting): GPU, 4,096 context,
  F32 activations, greedy, one question. Evidence: `output/mac-runtime/MAC-12B-GPU-1/`.
  - LiteRT-LM 0.14.0 (the app's version) **cannot load it**: `No KV cache inputs found`.
  - LiteRT-LM 0.17.1 loads and answers. The answer to "What is prudence?" was fuller than
    E4B's. Generation took 3.1–4.7 s, versus 1.3 s for E4B. Load took 19–21 s on a cold cache and
    2.0 s with the compiled cache, which uses **5.6 GB of disk**.
  - E4B on 0.17.1 gave the same answer as on 0.14 (6.1 s load, 1.3 s generation).
  - Memory is not settled. The process footprint peaked at 2.6 GB, and the system-wide sampled
    increase was 3.9 GB, while other agents were running. Neither number captures memory-mapped
    weights reliably, and the model card reports about 7.9 GB of GPU memory. A 16 GB Mac
    measurement is still needed.
  - 0.17.1 drops the app's local LiteRT-LM patch: the F32 `activationDataType` flag, the
    native-activity tracking in `Engine.swift`, and the teardown handling in `Conversation.swift`.
    A runtime upgrade must carry these patches forward and re-validate iPhone behavior.
  - No app code or app model selection changed.
