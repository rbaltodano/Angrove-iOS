# Angrove iOS repository guide

This is the canonical instruction file for coding agents. `CLAUDE.md` imports it so Claude Code
and Codex follow the same project guidance. Keep this file short: it routes work; it does not
duplicate architecture specifications.

## Read the right document

| When changing… | Read… |
| --- | --- |
| Any iOS code | This file, then the relevant feature source and tests |
| Product behavior | [`../Aquinas-Foundations/FUNCTIONALITY.md`](../Aquinas-Foundations/FUNCTIONALITY.md) |
| Design or interaction | [`../Aquinas-Foundations/DESIGN.md`](../Aquinas-Foundations/DESIGN.md) |
| Model, API, retrieval, persistence, or privacy boundary | [`../Aquinas-Foundations/MODEL-INTEGRATION.md`](../Aquinas-Foundations/MODEL-INTEGRATION.md) |
| Insight Tree | [`../Aquinas-Foundations/INSIGHT-TREE.md`](../Aquinas-Foundations/INSIGHT-TREE.md) |
| iOS composition, ownership, and persistence | [`Documentation/App-Architecture.md`](Documentation/App-Architecture.md) |
| LiteRT runtime or model recovery | [`Documentation/Model-Runtime.md`](Documentation/Model-Runtime.md) |
| Builds, tests, device work, or Figma | [`Documentation/Development-Workflow.md`](Documentation/Development-Workflow.md) |
| Study mode | [`Documentation/Study-Tool.md`](Documentation/Study-Tool.md) |
| Gemma 4 E4B QAT migration | [`Documentation/Gemma4-E4B-QAT-Plan.md`](Documentation/Gemma4-E4B-QAT-Plan.md), then its [progress ledger](Documentation/Gemma4-E4B-QAT-Progress.md) |

## Non-negotiable rules

- Preserve unrelated and uncommitted work. Do not reset, discard, or overwrite it.
- Before installing a special build on the owner's physical phone from any worktree other
  than `~/Developer/Aquinas-iOS-main` on `main`, set its visible app name to
  `<current main app name> – <work name>` and verify the exact signed app's
  `CFBundleDisplayName` before installation. Follow the naming procedure in
  [`Documentation/Development-Workflow.md`](Documentation/Development-Workflow.md).
- Use `AngroveTheme` typography and color tokens. Do not introduce ad hoc system colors or raw
  visual constants when an existing semantic token applies.
- All live generation goes through `AngroveModel` and the shared runtime/queue. `MockAngroveModel`
  is for previews and tests only; live actions fail explicitly rather than inventing fallback
  content.
- The Thinking display shows the app's approach line and retrieved sources, then Gemma 4's own
  native `thought` channel (one line at a time live, in full under **Show Thinking**). Never
  invent or paraphrase reasoning the model did not produce.
- Keep the LiteRT runtime process-scoped. Do not create competing live engines or queues.
- Automatic response analysis can create a Node Concept, never an automatic Insight. Manual
  definition saves create Insights.
- Treat API schemas and structured output as cross-repository contracts. Update iOS decoding and
  Foundation documentation in the same change.
- The app has no network backend. Generation, retrieval, and Insight Tree work all run on-device;
  do not add an HTTP model or data client. `Aquinas_Backend` is offline tooling only (corpus,
  model conversion, evaluation).

## Working conventions

- The app source lives in `Angrove-iOS/`; focused tests are in `Angrove-iOSTests/`.
- Prefer small SwiftUI views with narrow inputs. Keep feature code under
  `Angrove-iOS/Features/<Feature>/` and shared visual primitives under `DesignSystem/`.
- Add behavior-oriented regression coverage for logic with meaningful regression risk.
- Before handing off a visible change, inspect small-phone layouts, light/dark appearance,
  navigation, and empty states as applicable.
- For queue changes, verify idle, one-task, multi-task, cancellation, and reorder states. For
  tree changes, verify both the global library canvas and the persisted conversation tree.

## Standard verification

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
