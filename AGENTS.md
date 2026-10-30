# Angrove multiplatform repository guide

This is the canonical instruction file for coding agents. `CLAUDE.md` imports it so Claude Code
and Codex follow the same project guidance. Keep this file short: it routes work; it does not
duplicate architecture specifications.

## Read the right document

| When changing… | Read… |
| --- | --- |
| Any iOS code | This file, then the relevant feature source and tests |
| Product behavior | [`../Angrove-Foundations/FUNCTIONALITY.md`](../Angrove-Foundations/FUNCTIONALITY.md) |
| Design or interaction | [`../Angrove-Foundations/DESIGN.md`](../Angrove-Foundations/DESIGN.md) |
| Model, API, retrieval, persistence, or privacy boundary | [`../Angrove-Foundations/MODEL-INTEGRATION.md`](../Angrove-Foundations/MODEL-INTEGRATION.md) |
| Insight Tree | [`../Angrove-Foundations/INSIGHT-TREE.md`](../Angrove-Foundations/INSIGHT-TREE.md) |
| iOS composition, ownership, and persistence | [`Documentation/App-Architecture.md`](Documentation/App-Architecture.md) |
| LiteRT runtime or model recovery | [`Documentation/Model-Runtime.md`](Documentation/Model-Runtime.md) |
| Builds, tests, device work, or Figma | [`Documentation/Development-Workflow.md`](Documentation/Development-Workflow.md) |
| Native macOS port | [`Documentation/Mac-Port.md`](Documentation/Mac-Port.md), then the shared feature contracts |
| Study mode | [`Documentation/Study-Tool.md`](Documentation/Study-Tool.md) |
| Mac Boards canvas (`Worktree` in code) | [`Documentation/Boards.md`](Documentation/Boards.md) |
| Gemma 4 E4B QAT migration | [`Documentation/Gemma4-E4B-QAT-Plan.md`](Documentation/Gemma4-E4B-QAT-Plan.md), then its [progress ledger](Documentation/Gemma4-E4B-QAT-Progress.md) |

## Non-negotiable rules

- Preserve unrelated and uncommitted work. Do not reset, discard, or overwrite it.
- The owner's everyday Mac app is `/Applications/Angrove.app`. After completing a Mac
  app change, use `bash Tools/install-local-mac.sh` to update that same signed app before
  handoff. Do not leave the latest usable build only in DerivedData or launch another
  normal build copy. Keep isolated previews separate. Preserve running work: quit normally
  before installing, and report explicitly if installation is still pending. See
  [`Documentation/Mac-Port.md`](Documentation/Mac-Port.md#normal-local-app).
- Before installing a special build on the owner's physical phone from any worktree other
  than `~/Developer/Angrove-iOS-main` on `main`, set its visible app name to
  `<current main app name> – <work name>` and verify the exact signed app's
  `CFBundleDisplayName` before installation. Follow the naming procedure in
  [`Documentation/Development-Workflow.md`](Documentation/Development-Workflow.md).
- Use `AngroveTheme` typography and color tokens. Do not introduce ad hoc system colors or raw
  visual constants when an existing semantic token applies.
- All live generation goes through `AngroveModel` and the shared runtime/queue. `MockAngroveModel`
  is for previews and tests only; live actions fail explicitly rather than inventing fallback
  content.
- The Thinking display shows the app's approach line and retrieved sources, then, when native
  thinking is on, Gemma 4's own `thought` channel (one line at a time live, in full under
  **Show Thinking**). Native thinking is off by default (`LiteRTAngroveModel.usesNativeThinking`).
  Never invent or paraphrase reasoning the model did not produce.
- Keep the LiteRT runtime process-scoped. Do not create competing live engines or queues.
- Automatic response analysis can create a Node Concept, never an automatic Insight. Manual
  definition saves create Insights.
- Treat API schemas and structured output as cross-repository contracts. Update iOS decoding and
  Foundation documentation in the same change.
- The app has no network backend. Generation, retrieval, and Insight Tree work all run on-device;
  do not add an HTTP model or data client. The one outbound exception is the person-initiated
  support report (`BugReportSubmission`, used by Settings and the thumbs-down sheet). It sends
  only what the person types plus app and iOS version numbers, and an optional reply email. A
  flagged response and its question are attached only if the person turns on the opt-in in the
  thumbs-down sheet, which previews that text first. Never attach conversation content by default,
  and update the published privacy policy before widening what a report sends. `Angrove-Backend` is offline tooling only (corpus,
  model conversion, evaluation).

## Working conventions

- Make the best decision that will elevate all three: the user experience (UX), developer
  experience (DX), and agent experience (AX) always, without breaking anything.
- Cut taglines, helper text and secondary labels. If a screen needs them to make sense, fix the
  layout.
- One canonical checkout at `~/Developer/Angrove-iOS-main` owns both native app targets.
- iPhone-only code lives in `iOS/`; Mac-only code lives in `macOS/`; code and resources
  compiled by both apps live in `Shared/`. Read `Documentation/Workspace-Layout.md`.
- Focused tests remain in `Angrove-iOSTests/` and `Angrove-macOSTests/`.
- The old `~/Developer/Archive/Worktrees/Aquinas-iOS-mac` worktree is preserved for recovery, not automatic
  sharing. Do not implement new platform work there for this unified workflow.
- Prefer small SwiftUI views with narrow inputs. Keep feature code under
  `iOS/Features/<Feature>/` or `macOS/Features/<Feature>/`, with common features under
  `Shared/Features/` and common visual primitives under `Shared/DesignSystem/`.
- Add behavior-oriented regression coverage for logic with meaningful regression risk.
- Before handing off a visible change, inspect small-phone layouts, light/dark appearance,
  navigation, and empty states as applicable.
- For queue changes, verify idle, one-task, multi-task, cancellation, and reorder states. For
  tree changes, verify both the global library canvas and the persisted conversation tree.

## Standard verification

For shared-source changes, verify both app targets. The Mac command is:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/workspace-layout-mac CODE_SIGNING_ALLOWED=NO build
```


Run from the repository root. Always use a concrete arm64 simulator; the bundled LiteRT framework
does not support the generic simulator destination.

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run focused tests when relevant:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Use a physical base supported iPhone for final sustained model, thermal, memory, and lifecycle
validation. Never use `devicectl ... --remove-existing-content true` against the production app
container; back up app data before model experiments.
