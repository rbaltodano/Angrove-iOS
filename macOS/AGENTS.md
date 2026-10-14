# Angrove macOS workspace

Read [`../AGENTS.md`](../AGENTS.md) and [`../Documentation/Workspace-Layout.md`](../Documentation/Workspace-Layout.md) before changing code. Those repository rules apply here.

This Codex project owns **Mac-specific UI, windows, keyboard/mouse input, lifecycle and service adapters**. New work for this area belongs in this folder. Keep platform-specific behavior in `../iOS/` or `../macOS/`; common behavior belongs in `../Shared/`. Both app targets compile the same Shared files directly.

The Git repository and Xcode project are one directory above this folder. Run Git and build commands from the repository root. Tests are in `../Angrove-iOSTests/` and `../Angrove-macOSTests/`. Do not create an independent repository, duplicate common implementations, or edit the historical `Aquinas-iOS-mac` worktree to synchronize changes.

Read sibling source and repository documents as needed. For a task limited to this platform/area, keep edits here unless build configuration or a shared contract requires a coordinated change. Preserve other agents' uncommitted work; multiple project conversations may use this same checkout.

## Tool choice and verification cost

- Do not default to Computer Use, app/browser automation, screenshots, or opening the running app for every change. Prefer file reads, targeted searches, patches, command-line builds, focused tests, and purpose-built tools.
- Documentation, nonvisual logic, and routine refactors do not need Computer Use unless the user requests it or there is a concrete UI-dependent issue to resolve.
- For visible changes, satisfy the repository's applicable visual checks with the smallest useful verification scope. Prefer existing previews, rendered artifacts, or focused UI tests when they provide the needed evidence. Use Computer Use when live layout, window behavior, keyboard/mouse interaction, or an otherwise unobservable UI defect actually needs it.
- Before starting Computer Use, briefly state the specific behavior being checked and why direct tools are insufficient. This is an explanation, not an extra permission request. Stop once that behavior is verified; avoid unrelated app tours and repeated screenshots unless a new change or failure justifies them.
- Report what was verified and any remaining visual checks honestly. A successful build alone does not establish visual correctness. This policy does not waive required builds, relevant regression coverage, or installation of completed Mac app changes into `/Applications/Angrove.app`.
