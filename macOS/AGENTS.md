# Angrove macOS workspace

Read [`../AGENTS.md`](../AGENTS.md) and [`../Documentation/Workspace-Layout.md`](../Documentation/Workspace-Layout.md) before changing code. Those repository rules apply here.

This Codex project owns **Mac-specific UI, windows, keyboard/mouse input, lifecycle and service adapters**. New work for this area belongs in this folder. Keep platform-specific behavior in `../iOS/` or `../macOS/`; common behavior belongs in `../Shared/`. Both app targets compile the same Shared files directly.

The Git repository and Xcode project are one directory above this folder. Run Git and build commands from the repository root. Tests are in `../Angrove-iOSTests/` and `../Angrove-macOSTests/`. Do not create an independent repository, duplicate common implementations, or edit the historical `Aquinas-iOS-mac` worktree to synchronize changes.

Read sibling source and repository documents as needed. For a task limited to this platform/area, keep edits here unless build configuration or a shared contract requires a coordinated change. Preserve other agents' uncommitted work; multiple project conversations may use this same checkout.
