# Codex: Mac QA retest — October 26, 2026

Work from `~/Developer/Angrove-iOS-main`. Read `Documentation/Mac-TestFlight-Readiness.md` (the
"Progress — 13:45" section) and `Documentation/Mac-QA-Tracker.md` first.

## Rules

- Test only the installed app, `/Applications/Angrove.app` (signed Oct 26 13:38). Don't rebuild,
  reinstall or launch other builds.
- It holds the owner's personal data. Use the `QA test` conversation, Study Topic and Board, or
  new items named `QA …`. Never reset, import, clear or delete the owner's data. Don't press
  Reset Settings.
- Don't send bug reports or messages.
- Mark ✅ only for behavior you watched work. Save evidence (AX dumps, screenshots) in
  `build-output/qa/2026-10-26-release/` and cite it in the row.
- Re-read the tracker immediately before each edit; other sessions write to it.
- Quit the app normally when you finish, and leave it quit.

## 1. Accessibility fixes (dump the AX tree for each)

1. **MAC-QA-01:** collapse the sidebar; every compact button should have its destination's name.
2. **MAC-QA-02:** in a finished answer, the footer should read Copy response, Regenerate response,
   Bad response, and Read response aloud (Stop reading while it speaks).
3. **MAC-QA-03:** dump Settings → Support & Privacy with role, title and description for Report…,
   View…, Privacy Policy and Reset Settings.
4. **MAC-QA-04:** in `QA test`, ask "What is the distinction between justice and mercy? Please
   answer in two short paragraphs." Every linked term, including multiword ones like "divine
   goodness", should be named in full. Single-word links should still open definitions.
5. **MAC-QA-05:** open a definition and Quote it. The chip should read "Open Justice Insight" and
   its X "Remove Justice"; X should still remove it. Quote again and send a quoted question.

If one still fails, paste the exact AX output into the row. The source fixes exist, so the cause
lies elsewhere.

## 2. Other changes in this build

- **MAC-QA-06:** Settings → User Guide. Open Starting a Conversation, Definitions, Insight Tree,
  Organizing, Model Tasks, Personalizing and Privacy. They should describe the Mac: no haptics,
  text alignment, Face ID, "tap" or "your phone". Try the Model Tasks demo; its hints should say
  Click. Check light and dark.
- **MAC-TF-06:** Settings → Model should offer only Standard. Model Tasks should show "Gemma 4 E4B"
  with no menu chevron. One question should answer end to end.

## 3. Untested features, highest value first

1. **Queue:** queue two or more questions/definitions, reorder them, cancel a queued task and an
   active one after text starts streaming. Canceling one task shouldn't affect another. Navigate
   away and back mid-task.
2. **Persistence:** quit normally, relaunch; the QA conversation, topic, board and settings
   should all be intact.
3. **Conversations:** the rename sheet with Escape and an empty name; delete a QA-only
   conversation; empty, very long and rapid repeated questions; slash commands with arguments;
   add and remove a Photos attachment.
4. **Insight Tree:** save a definition and confirm it appears in the conversation tree and the
   global tree; pan, zoom, search; enter and leave Study.
5. **Boards (QA board):** pan and zoom; move and resize notes; box select and move several;
   trash an item and restore it; undo/redo across these; then delete the QA board.
6. **Library:** next/previous chapter; a citation opening the reader and Return to Conversation;
   Ask into a QA conversation; Clip save.
7. **Settings:** completed-response and Question of the Day notifications (open them from
   Notification Center); App Lock with Touch ID, including Cancel; each preference you change
   survives a relaunch. Restore the original values afterward.
8. **Widget:** add small and medium; clicking one should deep-link with the app closed and open.
9. **Layout:** the 760×540 minimum window, light and dark on every page, keyboard navigation in
   menus (arrows, Return, Escape, typing to jump).

## 4. Skip and mark ⏳ with a note

Import/Replace, Clear Insight Tree, the Delete All actions and Reset Settings need a disposable
profile. TestFlight install and hosted model download need an uploaded build, which doesn't
exist yet.

## Finish

Update the tracker's row counts and add one dated log line: what passed, what failed (with
reproduction steps) and what you skipped.
