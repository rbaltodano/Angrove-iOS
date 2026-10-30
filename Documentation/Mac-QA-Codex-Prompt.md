You are doing a hands-on QA pass of the Angrove Mac app at /Applications/Angrove.app, using computer use.

Tracker: ~/Developer/Angrove-iOS-main/Documentation/Mac-QA-Tracker.md. Read it first, including the tester rules at the top. A Claude Code session is fixing failures from this same file, so:
- Change only the Status and Notes cells of rows you tested, and add dated lines to the Log section. Don't restructure the file.
- Don't edit source code. Report what you find; the Claude session fixes it.
- Re-read the file just before each write, because the other session also writes to it.

How to test:
1. Go section by section. For each row, try the normal path, then edge cases: empty input, very long input, rapid repeated clicks, Escape midway, switching pages while something is loading, resizing to the minimum window size, and light and dark appearance.
2. Mark ✅ only when you saw it work. For ❌ or ⚠️, write in Notes the exact steps, what you expected and what happened, short enough to reproduce. Save a screenshot to ~/Developer/Angrove-iOS-main/build-output/qa/ and give its filename.
3. Don't run destructive actions (Delete Everything, Clear Insight Tree, delete conversations or passages, Import/Replace, Reset Settings) or submit the Report sheet. Mark those ⏳ with "skipped: destructive". Don't delete, rename or pin the owner's existing conversations; create a throwaway conversation, topic and board named "QA test" and use those, then delete only those.
4. Live answers use the on-device model and can take a while. Wait for them; don't mark a generation failure until about two minutes have passed.
5. Don't quit or reinstall the app while a generation is running.

When done, add a summary line to the Log: counts of ✅/⚠️/❌/⏳ and the top three problems.
