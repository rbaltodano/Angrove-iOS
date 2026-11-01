# Mac QA tracker

The shared progress list for testing the Mac app (`/Applications/Angrove.app`) feature by feature.
Any session or agent can pick this up: update a row as soon as you test or fix it, and add a
dated line to the log at the bottom.

**Status:** ✅ works · ❌ broken · ⚠️ partly works · 🔧 fix in progress · ⏳ not tested yet

**Rules for testers**
- Test the installed signed app. Don't run unsigned Debug builds against personal data: they
  recreate `~/Library/Application Support/Angrove-macOS`, which blocks the next sandboxed install.
- Before any destructive check (Delete Everything, Clear tree, Import/Replace, Reset Settings),
  back up the container's App Support, Preferences and Documents (not Caches; see
  `Development-Workflow.md`), or skip the check and mark it ⏳ with a note.
- When a fix lands, give the file and test name in Notes, then reinstall with
  `bash Tools/install-local-mac.sh`.

## Automated checks

| Check | Status | Notes |
| --- | --- | --- |
| Mac build (Debug) | ✅ | 2026-10-26 fresh unsigned arm64 build passed; `build-output/qa/2026-10-26-release/mac-build.log`. |
| `Angrove-macOSTests` suite | ⚠️ | 2026-10-26 fresh run: 349 tests / 85 suites passed in 237s, unsigned and serial; `MacSidebarRenameFlowTests` excluded because of previously recorded focus hang. Inline rename verified live. Log: `build-output/qa/2026-10-26-release/mac-tests.log`. |

## Workspace and navigation

| Feature | Status | Notes |
| --- | --- | --- |
| Launch, single-window lock (second launch activates the first) | ⏳ | |
| Sidebar destinations: Home, Insights, Conversations, Library, Study Topics, Boards, Settings | ✅ | Codex UI pass 10-26: all seven open |
| Sidebar collapse/expand, collapsed labels | ❌ | 13:38 build retest: six compact scroll-area buttons still unnamed (`14 button (selected)`, `15–19 button`). Expanded names exist. Exact dump `build-output/qa/2026-10-26-release/retest-1338-sidebar-ax.txt`. No rebuild/reinstall. |
| Back/forward page history (⌘[ / ⌘]) | ⏳ | |
| Global search | ✅ | Codex: results and no-match state |
| Shortcuts: new conversation, new board, new topic, recent conversation ⌘1–9, open queue, Settings | ⚠️ | ⌘N conversation, ⌘1 most recent QA conversation, ⇧⌘H Home, ⌘M Model Tasks, ⌘, Settings and ⇧⌘S pane swap verified. Remaining shortcuts untested. Current source uses destination-dependent ⌘N; old ⇧⌘N docs need reconciliation. |
| Light and dark appearance | ⚠️ | 13:38 retest: all six requested User Guide articles viewed in light/dark; dark Library, Boards, global/conversation trees and Settings also viewed. Every page/sheet and minimum layout remain unverified. Original Light restoration is pending because the final Computer Use connection became stale; current last verified theme is Dark. |
| Minimum window size layout | ⏳ | 760×540 was not established. Earlier corner drag was inconclusive; final Computer Use session returned stale menu states/invalid element errors even after reconnect. Requires a fresh live session. |
| Shared menus: Escape, outside click, arrow keys, Return, type-to-select, submenu Back | ⚠️ | Conversation and Board options open; Escape dismisses Board Add; Settings Theme selection works. Keyboard traversal, outside-click dismissal and submenus still pending. |
| Normal quit/relaunch persistence | ⚠️ | Verified normal quit and installed-app relaunch earlier in this retest (PID 55567→56443). QA conversations/quoted-answer Home preview, QA topic sidebar, QA board original edited note and Dark theme retained. Evidence `retest-1338-after-relaunch-ax.txt`, `retest-1338-board-after-relaunch-ax.txt`, `retest-1338-settings-after-relaunch-ax.txt`. Not every preference or topic detail was rechecked. Later 17:40 quit attempt was not verified; do not count it as another relaunch. |

## Home

| Feature | Status | Notes |
| --- | --- | --- |
| Home dashboard content and empty state | ⚠️ | Populated Home renders greeting/calendar/QOTD/resume/discovery/Library links. Empty/fresh-install state and card actions untested. |
| Model download / status card | ⚠️ | Settings reports Standard Ready and runtime answers using existing local model. Hosted first-install download/progress/retry remain untested; local success does not validate TestFlight. |

## Conversations

| Feature | Status | Notes |
| --- | --- | --- |
| New conversation, ask, streamed answer | ✅ | Installed app: ⌘N; asked justice vs mercy in two paragraphs; local answer completed and follow-up composer appeared. QA conversation named `QA test`. No timing benchmark claimed. |
| Stop generation mid-answer | ⚠️ | Stopped active QA question from Model Tasks during Thinking; transcript shows Question canceled, runtime Idle, composer restored. Stop after first streamed tokens still untested. |
| Follow-up questions and reveal | ✅ | Asked Can mercy be compatible with justice? Answer in one sentence. Answer/reveal completed; conversation survived navigating away and reopening. |
| Slash commands | ⚠️ | Typing / shows Define/Summarize/Clear/Rename/New/Tree/Topic/Library suggestions; Escape dismisses. Command execution and arguments still pending. |
| Image attachments (plus menu, both paths) | ⚠️ | Image File → bundled BoardsMosaicFinal.png → preview → Describe the image in one sentence: model correctly described mosaic cubes. Photos path, attachment removal, unreadable file and saved-image relaunch still pending. |
| Quoted question editor | ❌ | MAC-QA-05: Justice chip and X still unnamed (`54 button`, `55 button`); X removes it. Reopened definition, bookmarked and sent a quoted follow-up; answer completed with chip attached. Evidence: `retest-1338-quote-ax.txt`, `retest-1338-quoted-answer.png` in build-output/qa/2026-10-26-release/. Library quote chip names do work; do not generalize that pass to Insight chips. |
| Thinking display, Show Thinking | ✅ | Codex: disclosure works |
| Rename (inline sidebar and sheet) | ⚠️ | Right-click QA conversation → Rename → typed QA test → Return commits; retained after navigation. Separate sheet, Escape rollback and empty-name behavior still pending. |
| Pin / unpin | ✅ | QA test context menu Pin adds sidebar pin icon; reopening menu offers Unpin; Unpin removes icon. Owner conversations untouched. |
| Delete conversation | ⏳ | |
| Right-click row menu | ✅ | QA conversation menu opens with Rename/Pin/Add to Study Topic/Delete; Rename targets QA conversation correctly. Each remaining action is tracked separately. |
| Conversation list page | ⏳ | |
| Topic picker | ⚠️ | Study Topic Add Existing Conversation picker selected QA test; Add filed it under QA topic, and conversation header reflects topic. Conversation-side reassignment/removal not exercised. |
| Thumbs-down feedback sheet (opt-in attachment preview) | ✅ | Codex: Send disabled when empty, Escape dismisses, attachment opt-in off by default |
| Read aloud | ⚠️ | QA response speaker enters Reading controls, second click stops. Audible quality, scrub, pause/resume and persisted positions remain unchecked. |
| Model queue: idle, one, many, cancel, reorder | ⚠️ | 13:38 retest: multiple question/definition/Update Insight Tree tasks observed, including queued C question and three definitions; navigate between QA conversations/Home and answers complete. Evidence `retest-1338-real-queue-before-ax.txt`, `retest-1338-three-definitions-ax.txt`. Production reorder, queued cancellation, cancellation after visible answer tokens and cross-task isolation remain unverified: tasks finished before actions could be verified. Prior Thinking cancellation still passes. |
| Response footer buttons (copy, regenerate, thumbs down, read aloud) | ❌ | MAC-QA-02 mixed: first natural-law answer in new QA Queue D exposes Copy response/Regenerate response/Bad response/Read response aloud and Stop reading while speaking (`retest-1338-new-conversation-speaking-ax.txt`). Subsequent justice/mercy answer in that same conversation returns to bare doc.on.doc/arrow.trianglehead.2.clockwise/hand.thumbsdown/speaker.wave.2 (`retest-1338-new-conversation-linked-terms-bottom-ax.txt`). Original QA also fails. Source fix is not uniformly effective; cause unestablished. |
| Edge: empty question, very long question, rapid repeated submit | ⚠️ | Blank Return left app Idle with no question (`retest-1338-empty-question-ax.txt`). Three rapid Returns on QA essay prompt produced one observed question/task. Requesting a 2500-word answer is not a very-long-input test; genuinely very long question remains untested. |
| Linked response term accessibility | ❌ | MAC-QA-04: new QA Queue D justice/mercy answer names single-word justice/mercy but leaves divine goodness blank. Original QA fresh answer also had unnamed single words; Library answer names earthly city/lust of rule. Single-word Justice opens a definition. Exact `retest-1338-new-conversation-linked-terms-bottom-ax.txt`, `retest-1338-fresh-answer-ax.txt`; full-term naming still fails by rendering path. |
| Edge: switching conversations while generating | ⚠️ | Regenerated QA image answer, observed Thinking, navigated Home with ⇧⌘H, returned using ⌘1, answer present and Idle. Switching to a different conversation during a sustained stream remains untested. |
| Conversation input / transcript AX after navigation | ⚠️ | Visible original QA transcript missing from AX after quoted follow-up, Settings/User Guide navigation and return; input attempts failed. Later fresh composer attempts also failed while Computer Use began returning stale menus/invalid element errors. Evidence `retest-1338-unresponsive-composer-ax.txt`/`.png`, `retest-1338-fresh-composer-no-input-ax.txt`. Suspected UI/AX issue only: control-connection failure prevents classifying keyboard behavior as an app defect. Reproduce manually before implementation. |

## Conversation Insight Tree

| Feature | Status | Notes |
| --- | --- | --- |
| Show/hide tree, floating panel | ✅ | Codex: opens and closes |
| Resize, collapse in one drag, minimum size | ⏳ | |
| Swap conversation and tree | ✅ | Swap control and ⇧⌘S exchange conversation/tree main and secondary positions in dark; swapped back and closed secondary tree. |
| Minimized update cue | ⏳ | |
| Node Concept context actions | ⏳ | |

## Insights (global tree)

| Feature | Status | Notes |
| --- | --- | --- |
| Global tree canvas | ⚠️ | Global Search Insights Justice returns 1/1 after accepting Update Insight Tree; saved Justice visible. Evidence `retest-1338-global-justice-search-ax.txt`. Tree pan/zoom and Study entry/exit remain unverified. |
| Insight cards, resizable width | ⏳ | |
| Insight Ask flow | ⏳ | |
| Manual definition save creates Insight | ✅ | Bookmarked generated Justice definition (control changed to Remove bookmark); Justice subsequently visible in original QA conversation tree and global tree (Justice search 1/1 after Update Insight Tree). Evidence `retest-1338-conversation-justice-tree-ax.txt`, `retest-1338-global-justice-search-ax.txt`. This validates this save scenario only. |

## Library

| Feature | Status | Notes |
| --- | --- | --- |
| Browse works | ✅ | Codex: Library search |
| Reader | ⚠️ | City of God Book 1→Book 2→Book 1 via chapter controls works (`retest-1338-library-book1-ax.txt`, `retest-1338-library-book2-ax.txt`, `retest-1338-library-previous-ax.txt`). Expanded answer source→Read More opens reader; Return to Conversation returns originating QA conversation (`retest-1338-source-library-return-ax.txt`, `retest-1338-return-to-conversation-ax.txt`). Exact passage jump, inline citation link, full corpus/outline remain unverified. |
| Selection: Ask, Clip, Read | ⚠️ | Selected public City of God paragraph; Clip opens saved passage with Remove bookmark. Ask→New Conversation→QA Library question completed with quoted passage attached. Correct Open City of God Library quote / Remove City of God labels. Evidence `retest-1338-library-clip-ax.txt`, `retest-1338-library-ask-answer-ax.txt`. Ask into existing conversation and Read from Here remain untested. |
| Listening | ⚠️ | Listen to this page enters playback; Reading controls show current work, Pause and Stop; Stop returns to Listen. Audible quality, exact resume, scrub and relaunch persistence not checked. |

## Study Topics

| Feature | Status | Notes |
| --- | --- | --- |
| Create, rename, delete topic | ⚠️ | Created QA test topic; keyboard title/description edits autosave; assigned QA conversation and reopened from sidebar. Delete and draft cleanup not exercised; retained QA fixture. |
| Topic detail header, cards | ✅ | Codex: topic detail opens |
| Drop a conversation onto a topic | ⏳ | |
| Topic options and image menu | ⏳ | |

## Boards

| Feature | Status | Notes |
| --- | --- | --- |
| Boards home, create, rename, delete | ⚠️ | Created QA board, added note, returned to home, renamed to QA test and reopened with note retained. Delete still untested; retained QA fixture. |
| Canvas pan/zoom | ⚠️ | QA board scroll pans notes offscreen and reverse scroll returns them (`retest-1338-board-before-pan.png`, `retest-1338-board-after-pan.png`). Zoom/reset not established; keyboard attempts were inconclusive. |
| Text boxes: add, edit, move | ⚠️ | QA original edited note persists. Added a second QA note, moved using Move grip and widened using edge drag; screenshots `retest-1338-board-note-moved.png`, `retest-1338-board-note-resized.png`. Second note is now Q after QA editing/undo attempts. Multiline remains untested. |
| Photos: place, resize | ⏳ | |
| Drop Insight, drop conversation | ⏳ | |
| Box selection, multi-move | ⚠️ | Box drag visibly selected both QA notes (gold borders), `retest-1338-board-box-selected.png`. Group movement was not verified; grip attempts instead edited/resized a note. |
| Undo/redo history | ⚠️ | Text undo/redo passed previously. QA second note dragged to Trash, Cmd-Z restored it, Shift-Cmd-Z removed it, Cmd-Z restored again (`retest-1338-board-undo-delete.png`). Creation/multi-move history and history persistence remain untested. |
| Trash card, restore | ⚠️ | QA second note Q moved to Trash; Trash lists Note, Q with Help: Drag onto the canvas to restore (`retest-1338-board-trash-ax.txt`). Drag-out attempt did not visibly restore it; file named `retest-1338-board-restored-ax.txt` records the unsuccessful attempt, not a pass. Undo restored it. Trash drag restore requires reproduction; Empty never pressed. |
| Tools card, control dock, key shortcuts | ⚠️ | Tools opens Text/Question/Heading/Rename/Summarize/Define actions and dismisses; Add menu opens. Tool placement/execution and other shortcuts pending. |
| Summary reveal, definition failure state | ⏳ | |

## Settings

| Feature | Status | Notes |
| --- | --- | --- |
| Read-aloud toggles | ⏳ | |
| Notifications: completed responses, Question of the Day | ⚠️ | Completed responses changed off→on in Settings. No completed-response Notification Center delivery/open was verified; final input/control session became unreliable before notification question submitted. QOTD remained off; timed delivery/open untested. Restore Completed responses to off after reconnect (pending at handoff). In-app model notifications are not Notification Center evidence. |
| App Lock | ⏳ | Not enabled in this retest. Lock/unlock/Cancel and Touch ID require an owner-assisted live session; do not infer success from the Settings toggle. |
| Model tier choice | ✅ | 13:38 live retest: Settings menu only `Standard`; Model Tasks `text Model Tasks Gemma 4 E4B`, visually no chevron; fresh justice/mercy answer completed. Evidence `retest-1338-model-choice-ax.txt`, `retest-1338-model-tasks-conversation-ax.txt` and .png under build-output/qa/2026-10-26-release/. |
| Export conversations | ✅ | Installed sandboxed app saved Angrove Conversations.json via native exporter to ignored local QA folder; valid JSON with activeConversationID and six conversations. File mode 0600; not a full app backup. |
| Import / Replace conversations | ⏳ | Skipped: destructive replacement of personal conversations. Verify in disposable backed-up profile; current export is conversation-only, not complete app backup. |
| Clear Insight Tree, delete conversations/passages/everything | ⏳ | Skipped: destructive against personal data; requires disposable profile or verified complete backup. |
| Report a problem sheet | ✅ | Codex: Send disabled when empty, Escape dismisses. Don't submit |
| Licenses | ⚠️ | Licenses sheet opens with model/software/font/Library entries; Done closes. Individual license text and complete distributed-artifact attribution audit pending. |
| Reset Settings | ⏳ | Reset action deliberately skipped: needs disposable profile. MAC-QA-03 label retest FAIL: Support area `83 button Report…`, `85 button View…`, `87 link Description: Privacy Policy, Value: angrove.app/privacy.html`, `89 button` (Reset). No description printed for Report/View/Reset. Exact formatted AX dump `build-output/qa/2026-10-26-release/retest-1338-settings-support-ax.txt`; raw AXTitle properties not exposed by available API. |
| User guide | ✅ | MAC-QA-06 installed 13:38 UI pass: Personalizing, Privacy, Model Tasks, Insight Tree, Organizing, Starting a Conversation all read in light/dark; Mac wording, no requested phone/tap/haptics/alignment/Face ID terms. Model Tasks demo hints remain Click after interaction. Evidence `retest-1338-guide-{personalizing,privacy,tasks,tree,organizing,conversation}-{light,dark}-ax.txt`; demo `retest-1338-guide-tasks-demo-dark-ax.txt`. Visited-state persistence remains untested. |
| Hot Keys page | ✅ | Rewritten 10-26 13:10 to match `MacWorkspaceCommands`, `WorktreeKeyShortcuts`, `MacActionMenu`; render in `build-output/hotkeys/`. Shortcuts not re-pressed in the UI after the rewrite |

## Widgets

| Feature | Status | Notes |
| --- | --- | --- |
| Question of the Day widget | ⏳ | Small/medium gallery install and open/closed-app deep links not exercised. Final Computer Use session became stale before system-widget testing; requires fresh live session. |

## Log

- 2026-10-26: Tracker created. Waiting on computer use to drive the UI; automated suite running.
  The working tree has uncommitted Mac changes from another agent; the owner said to test and fix on top of them.
- 2026-10-26: Codex read-only UI pass (not complete: generation, editing, destructive actions, dark mode,
  minimum window and widgets unchecked). Four findings, all fixed in source by Claude: collapsed-sidebar
  labels, response footer labels, Reset Settings label, Library citation spacing. The label fixes can't be
  verified in tests (SwiftUI builds no AX tree without an assistive client), so they need an AX recheck in
  the installed app.
- 2026-10-26: All 349 Mac tests pass (unsigned, serial, `MacSidebarRenameFlowTests` skipped). The iOS build
  and `LibraryTextFormatterTests` pass. Signed Release installed to /Applications/Angrove.app (app was
  idle, quit normally, reopened). Next: recheck the four 🔧 rows in the installed app, then the untested sections.

- 2026-10-26, release-readiness follow-up: fresh build and 349 selected tests passed; real Standard local generation, follow-up, cancellation during Thinking, inline rename, topic assignment, Board note/edit/undo/redo/reopen, Library Ask picker/playback controls, conversation export, dark Settings/conversation/tree swap checked. Three previously fixed AX issues still fail installed-app recheck; Library citation spacing passes its original example. New unnamed multiword-term/quoted-Insight controls and Mac guide mismatch recorded in [Mac-TestFlight-Readiness.md](Mac-TestFlight-Readiness.md). This is not complete feature certification or a TestFlight install test. Original Light theme restored; QA conversation/topic/board retained intentionally; no personal content deleted, no report sent, no app code changed or app reinstalled.
- 2026-10-26 pass summary: ✅ 14, ⚠️ 24, ❌ 3, 🔧 0, ⏳ 30. Counts describe tracker rows (a partial row may contain working subflows). Top three release gaps: Mac distribution processing/record unverified, hosted-model first install unverified, remaining fresh-profile/persistence/base-16-GB acceptance unverified. See prioritized handoff before implementing.
- 2026-10-26 final additional smoke: Image File attachment and vision answer succeeded using bundled mosaic artwork; QA Pin/Unpin, exact response Copy/paste, response speaker start/stop, regeneration and Home/⌘1 return checked. QA conversation now has three completed answers and one canceled question. Photos and sustained multi-conversation streaming still untested. Final row counts: ✅ 15, ⚠️ 27, ❌ 3, 🔧 0, ⏳ 26.
- 2026-10-26 13:12 (Claude): Hot Keys page updated to every Mac shortcut in code; signed build installed. Codex's AX recheck shows the 09:05 label fixes did not take for the response footer (MAC-QA-02) or Reset Settings (MAC-QA-03); its dump does show compact sidebar names, so MAC-QA-01 needs another look.
- 2026-10-26 13:4x (Claude): footer labels reworked as icon-only Labels (MAC-QA-02); 349 Mac tests pass; installed (includes Codex Implementation's MacUserGuideView change). MAC-QA-03 still needs an AX dump; no session here has Accessibility access.
- 2026-10-26 13:45 (Codex Implementation, Claude): MAC-QA-04 multiword linked terms and MAC-QA-05 quoted Insight chip get content-level AX names (`CompletedResponseSegments.swift`, `InquiryContextChips.swift`); MAC-QA-06 Mac guide copy (`MacUserGuideCopyTests`, 3 tests); MAC-TF-06 Large deferred; Mac `PrivacyInfo.xcprivacy` added (archive had none for the app). Mac and iOS builds pass; full Mac suite 354 tests / 86 suites pass (rename-flow suite skipped). Installed signed build 13:38, then quit (owner away). Nothing here is UI-verified: the owner chose to skip UI checks in this session. Release artifacts in `build/mac-release/` (see readiness doc).
- 2026-10-26 14:2x Codex installed-only retest: codesign confirms 13:38:39, process launched at 14:15. MAC-QA-01/02/03/04/05 AX checks fail; fresh linked-term output now has unnamed single-word Justice/mercy too (older restored answer retained single-word labels). Definition opens, quote X removes, E4B answer completes, Standard-only menu/plain model name pass. Exact AX evidence saved with retest-1338 prefix. No source changes/build/install, no reports/messages. Continuing feature tests.

- 2026-10-26 17:45 Codex installed-only retest handoff: ✅ 19, ⚠️ 31, ❌ 4, 🔧 0, ⏳ 21 (75 tracker rows). MAC-QA-01–05 still fail in at least one installed rendering path; MAC-QA-02 has a passing first-answer path, and Library quote names pass. MAC-QA-06 requested guide articles and MAC-TF-06 pass. Justice save appears in both trees; Library next/previous, Clip, Ask end-to-end and source-reader-return pass their recorded scenarios. Board note move/resize, box-select and deletion undo/redo observed. Queue reorder/cancel isolation, Trash drag restore, Study, rename edge cases, Photos removal, notifications, widgets, minimum layout and full preference persistence remain open. Destructive Import/Replace/Clear/Delete All/Reset skipped for disposable profile; TestFlight/hosted model skipped because no uploaded build was verified. Final Computer Use connection stuck on stale app-menu states and invalid element errors after reset/reconnect, blocking reliable remaining checks and preference restoration. Last verified theme Dark and Completed responses on; restore original Light/off when UI control returns. No build/reinstall/source edits, no reports/messages, no owner data deletion. Full repro/evidence handoff in Mac-TestFlight-Readiness.md.
