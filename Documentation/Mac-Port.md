> **Workspace update — October 14, 2026:** active Mac development is now in
> `~/Developer/Aquinas-iOS-main/macOS`, with common source in `../Shared`.
> Both targets build from the canonical checkout. The older paths and branch named
> below describe historical milestones; see [Workspace-Layout.md](Workspace-Layout.md).

# Native Mac port

### Compact stagger and conversation loading — October 13, 2026

The compact rail fades its logo and navigation items in from top to bottom, using
60ms between items and 200ms opacity transitions after the existing collapse midpoint.
Reduce Motion presents all items immediately. Repeated expand/collapse cancels pending
entrance tasks through the shared presentation modifier.

Saved conversation rows display the same 14-point spinning ContextUsageIcon as iPhone
when an active or queued user-question task belongs to one of their branches. The
workspace observes the process-shared queue and passes the pending branch IDs into
the sidebar; no additional queue or runtime is created. Finishing or canceling a task
removes the wheel, and unrelated definition/tree work does not mark a conversation busy.

Mac Debug build passed (`/tmp/angrove-sidebar-stagger-build.log`). Visual validation is
left to the owner as requested; no Computer Use checks were performed for this change.
A concurrent signed installer included the final sidebar source; the installed binary
matched the Release product and its signature passed verification.

### Insight Card width — October 13, 2026

Insight Cards now share `AngroveTheme.Spacing.insightCardMaxWidth` (400 points)
across iOS and Mac: inline responses, library carousel, detail sheets, and selected
tree cards. Mac tree cards size independently of their controls pill and remain
constrained by their pane. The library carousel measures actual card width for
page spacing on narrower screens. Mac Release and iPhone 17 simulator builds passed.
The owner will perform visual verification. The local installer encountered another
Release build holding `build/mac-local`’s database; installation is pending.
Log: `/tmp/angrove-insight-width-install.log`.


### Sidebar title truncation and header toggle — October 13, 2026

Conversation titles in Recents and the studying heading use one line with trailing
ellipsis. The header's `inset.filled.leftthird.rectangle` button sits opposite the
native traffic-light controls, at the sidebar's trailing 24-point inset. It toggles
the existing compact state with the same width/content transition and honors Reduce
Motion. In the compact rail, it remains beside the controls without overlapping them.

Mac Debug build passed. Native fixture clicks verified collapse and expansion, and
rendered previews confirmed single-line truncation and control-row alignment.
Previews: `output/sidebar-preview/sidebar-menu-toggle.png` and
`sidebar-collapsed-toggle.png`, with matching `toggle-light` versions. The initial
installer attempt encountered another local build; that signed installation completed
with the final source. The installed `/Applications/Angrove.app` signature passed
verification and its native UI exposes the new header toggle.

### Mac app icon — October 13, 2026

The Mac target uses the existing shared `AngroveAppIcon.icon` Icon Composer asset
for Debug and Release. Xcode compiles the layered leaf artwork and its light/dark
appearances for macOS, including the fallback `AngroveAppIcon.icns`, and generates
`CFBundleIconFile` and `CFBundleIconName`. The compiled fallback was visually inspected.
Release build passed; the signed update was installed at `/Applications/Angrove.app`
and reopened. Build/install logs: `/tmp/angrove-mac-icon-build.log` and
`/tmp/angrove-mac-icon-install.log`.


### Desktop density and sidebar edge — October 13, 2026

The sidebar minimum is 280 points, with uniform 24-point side/bottom padding and
24 points between the native control row and menu content. The 92-point compact rail
fits its 44-point icons inside the same padding. The existing 84-point overshoot and
smooth collapse/expand transitions remain; the adjacent page retains at least 350 points.
The resize target spans 12 points on either side of the edge and sets the horizontal
resize cursor. Native traffic-light controls are inset 24 points from the top and left,
using AppKit's existing spacing and standard behavior. The workspace extends under the
transparent title bar so the sidebar remains attached to the full window height.

Mac BrandTypography uses 13-point text for body, controls, and captions, with larger
headings capped at 24 points. Native question measurement uses the same size. iPhone
font sizes are unchanged.

Mac build-for-testing and the iPhone 17 simulator build passed. All five sidebar layout
regressions passed in an isolated harness using the production layout source. A native
fixture verified continuous inward collapse and outward expansion without touching
personal conversation data. Dark/light expanded and collapsed renders are saved in
`output/sidebar-preview/` with the `24pt` suffix. Native rendered window measurements
confirmed 24-point top/leading control insets.

### Conversation editor click-through — October 13, 2026

The secondary pane's clipped content could intercept clicks outside its visible frame,
including over the question editor while the tree was collapsed. Both the conversation
and tree surfaces now apply a matching contentShape at their finite viewport, before
the outer full-workspace alignment frame. This bounds their hit areas as well as their
drawing and preserves the existing pane layout and animations.

Native UI checks reproduced the failure in a test-only copy of the full workspace with
an unavailable model and in-memory preview state. The same check with the fix accepted
a mouse click and typed text in the actual question editor; the test draft was cleared
and no question was submitted. Mac Debug build passed
(`/tmp/angrove-mac-composer-hit-test-build.log`). Restarting the main app still encounters
the separate existing Keychain wait while reading saved data; no access settings were changed.

### Sidebar native window inset — October 13, 2026

Measured AppKit's macOS 27 standard close-button frame: ordinary/hidden title bars use
9-point top/leading insets; a unified-toolbar window uses 19 points. Sidebar content now
uses the latter 19-point side/bottom inset. Its top remains 52 points: the toolbar
controls end at 33 points, followed by the same 19-point gap. Collapsed icons use the
same leading inset and hover labels retain an 8-point gap beyond the rail.

Mac Debug build passed (`/tmp/angrove-mac-sidebar-native-inset-build.log`). Rendered
expanded and compact previews were inspected under `output/sidebar-preview/` as
`sidebar-menu-native-inset.png` and `sidebar-collapsed-native-inset.png`.

### Conversation pane collapse in one drag — October 13, 2026

The secondary pane now stops at its minimum width and collapses immediately when the
same inward drag reaches an additional 84 points. Both floating and pinned modes use
this threshold, including when Swap makes the conversation secondary. Narrow windows
measure overshoot from the clipped visible minimum. The resize gesture stays mounted
until release, allowing an outward reversal to reopen the pane. Closing/reopening retains
the pane's role and pinned mode. Collapse uses the existing pane animation and respects
Reduce Motion; ordinary resizing follows the pointer directly.

All 11 pane layout regression tests passed in an isolated package using the production
layout type and repository tests (`/tmp/angrove-pane-collapse-tests.log`). Mac
build-for-testing passed (`/tmp/angrove-mac-pane-collapse-build.log`). Live pointer
inspection remains blocked by the existing app-startup Keychain wait.

### Sidebar expansion choreography — October 13, 2026

Compact/expanded width changes now animate the whole workspace over 0.42 seconds,
including the adjoining page. Expanded resizing still follows the pointer directly;
outward drags from the rail smoothly retarget the opening width. Both content layers
stay mounted. At 0.21 seconds, compact content starts its 0.14-second fade and the
expanded menu begins the mobile entrance sequence: headings at 0.15 seconds with
24-point movement, page icons at 0.20–0.35 seconds with the shared symbol draw-on,
text 0.025 seconds later with 10-point movement, and conversation rows staggered by
0.05 seconds. The divider uses mobile's inward line scaling and leaf rotation.

Cancelable view tasks discard stale delayed reveals on reversal. Reduce Motion skips
width movement, geometric entrances and stagger delays. Existing 350-point minimum,
84-point collapse threshold, hover labels and conversation actions are unchanged.

Mac Debug build passed (`/tmp/angrove-mac-sidebar-expansion-build.log`). Native component
renders under `output/sidebar-expansion/` verified intermediate width, midpoint fade,
staggered arrival, rapid reversal and recollapse. Live pointer inspection remains
blocked by the existing app-startup Keychain wait; Reduce Motion was reviewed in code.

### Collapsed sidebar branding and labels — October 13, 2026

The collapsed rail shows the shared Angrove leaf logo above its destination icons.
Hovering or focusing a page icon reveals its label just outside the rail, using
canvasSecondary and the semantic border. Labels fade and slide from -16 to 0 points
over 0.2 seconds; Reduce Motion keeps the fade and removes translation. The workspace
owns the label overlay so the sidebar's clipping does not cut it off, and the label
does not intercept pointer input or duplicate the icon's accessibility label.

Mac Debug build passed (`/tmp/angrove-mac-collapsed-label-build.log`). Native component
rendering verified the logo, icon layout and expanded hover label in dark appearance;
preview: `output/sidebar-preview/sidebar-collapsed-hover.png`. Live hover-animation
inspection remains blocked by the existing app-startup Keychain wait.

Hover labels retain their dark palette in light appearance for contrast. The override
is scoped to the label's text, fill and border. Mac Debug build passed
(`/tmp/angrove-mac-sidebar-label-contrast-build.log`); native light-mode component
rendering verified it in `output/sidebar-preview/sidebar-collapsed-hover-light.png`.

### Sidebar conversation actions — October 13, 2026

Saved conversation rows reveal an ellipsis on hover (also available on keyboard focus).
It opens a custom SwiftUI menu over the workspace with canvasSecondary fill, the semantic
border color, 12-point padding and 12-point continuous corners. The menu is anchored to
the row, stays within the window, and dismisses with Escape, an outside click, navigation
or sidebar collapse. Actions match the mobile menu: Rename, Pin/Unpin, Add to/Remove from
Study Topic, and Delete. Pinned conversations sort first; topic assignment uses the
existing Mac topic picker. Deletion asks for confirmation, cancels that conversation's
model tasks and removes its local tree membership/seeds, preserving the global library.

Live sessions observe sidebar metadata changes even while their workspace is unmounted,
so subsequent saves retain renamed titles and topic assignments. Deleted sessions stop
persisting. Added five regression cases covering metadata mutations, sorting, deletion
selection and background session notifications. Mac build-for-testing passed; direct
checks against the built Mac module also passed without launching the app or reading
personal stores. Logs: `/tmp/angrove-mac-sidebar-menu-build.log` and
`/tmp/angrove-sidebar-menu-checks.log`. Native visual inspection remains blocked by the
existing startup Keychain access wait; no Keychain access settings were changed.

### Attached navigation sidebar — October 13, 2026

The navigation sidebar now spans the full window height and joins the active page at a
single trailing divider. Removed the inset rounded card and its outer margins; retained
the existing theme fill, navigation actions and footer, with top clearance for the window
controls. The shared workspace layout applies this presentation to every destination.

Mac Debug build passed in `build/mac-sidebar`; log: `/tmp/angrove-mac-sidebar-build.log`.
Native visual verification was blocked by repeated computer-use timeouts. Light/dark,
minimum-window and navigation inspection remain unverified for this change.

The sidebar is now resizable from its trailing edge, with a 350-point expanded minimum.
An inward drag reaching 84 points past that minimum switches to an 84-point rail showing
only the four destination icons, with tooltips and selection highlighting. An outward
84-point drag restores the expanded sidebar. The gesture uses a fixed workspace coordinate
space and its original layout so reversing the same drag reverses the collapse. VoiceOver
offers resize and expand/collapse actions; compact transitions respect Reduce Motion.

Five drag/layout regression tests passed against the extracted production layout type in
an isolated Swift package (`/tmp/angrove-sidebar-isolated-tests.log`). The app-hosted test
runner and native UI inspection were blocked on existing Keychain access during startup;
no Keychain permissions or saved data were changed. Mac Debug build passed; log:
`/tmp/angrove-mac-sidebar-resize-build.log`.

Owner-approved baseline, October 12, 2026: **Apple silicon, at least 16 GB installed
memory, macOS 27 or later**. Development lives in `Aquinas-iOS-mac`, branch `codex/mac-port`,
starting at committed main `19baca9`. Uncommitted work in the canonical iOS checkout was not
copied or modified. Bring subsequent iOS commits into this branch before adapting those features.

## Working architecture

One repository, two native app targets. `Angrove-iOS` retains its existing composition.
`Angrove-macOS` has a dedicated SwiftUI app entry point, native navigation sidebar, Settings
window, and separate bundle ID `com.ryanbaltodano.Angrove.macOS`. This is a macOS target;
it does not use Catalyst. The shared `AngroveTheme.swift` and bundled fonts are compiled/copied
from the existing iOS source locations, without creating a second theme or font collection.

Share feature logic and contracts as they become portable; keep platform-specific input,
navigation, window management, and service adapters separate. Do not duplicate the iOS
app into another independent implementation. Future windows must share one process-scoped
model runtime and task queue. Never point this development target at an iOS data container.

## First milestone — October 12, 2026

- Added shared `Angrove-macOS` scheme and a focused Mac test target.
- Restricted application builds to arm64 and deployment to macOS 27.0.
- Added startup hardware eligibility checks. Less than 16 GiB installed memory is rejected;
  this checks hardware capacity, not free memory at launch. It is a product support baseline,
  not a measured inference-memory or performance guarantee.
- Added the native Home preview, sidebar destinations and Settings window. Conversations,
  Library and Insight Tree explicitly show that they are under construction.
- Extracted existing colors, typography and spacing into one shared source file. Added an
  AppKit dynamic-color implementation for the same light/dark palettes; iOS retains UIKit
  dynamic colors and its existing typography modifiers.
- Resolved and linked the existing vendored LiteRT-LM 0.14.0 package's Mac dependency.
  A test exercises the native capabilities API and verifies rejection of a missing model.
  At this first milestone, no weights were downloaded, copied, loaded, or changed. It did **not** establish
  Gemma inference, GPU support, latency, memory use, vision support or model delivery on Mac.

## Build and test

### Normal local app

Quit all running Angrove copies, then run `bash Tools/install-local-mac.sh` from this
checkout. Launch `/Applications/Angrove.app` for everyday use. Do not launch a different
unsigned build directory against personal stores or use `open -n` for the normal app.
The installer signs embedded code and the app with the owner's existing Apple Development
certificate, verifies the signature, and installs at that fixed path. It keeps a dated
rollback archive under `build/mac-installed-backups/` and refuses to replace an app while
Angrove is running. Completed Mac changes must update this installed copy before handoff,
as required by `AGENTS.md`. The owner opens the same app after each update; opening it does
not compile unfinished source edits. Quit and reopen after an installed update to see it.
`ANGROVE_SIGNING_IDENTITY` and `ANGROVE_MAC_INSTALL_PATH` can override the local defaults.

This local installation keeps the existing non-sandboxed development data/model locations;
it does not migrate personal data or change Keychain permissions. The Xcode target's
distribution sandbox settings remain unchanged. A first Keychain authorization may still
be needed to trust the transition from an ad hoc build. Choose Always Allow for this
signed app; later builds retain a certificate/bundle-based designated requirement instead
of an executable hash. Certificate rotation or Keychain changes can require new approval.

The main scene is a single `Window`, so restored workspaces and New Window cannot multiply
it. Normal launches acquire a process-lifetime file lock before opening personal stores;
a competing local copy activates the existing process and exits. A crash releases the lock
automatically. Design fixtures and app-hosted tests bypass ownership of the live workspace.
Settings remains a separate window. Unsigned builds below are for build/test verification
and isolated fixtures, not the everyday app.

Verification (October 13, 2026): Release build passed; the app and embedded code passed
strict/deep signature verification. Installed `/Applications/Angrove.app` with the same
certificate/bundle-based designated requirement. Three actual signed executable launches
against a held workspace lock exited successfully before opening stores, and the lock
was reacquired after release. Logs: `/tmp/angrove-mac-local-build.log` and
`/tmp/angrove-mac-local-install.log` (the latter stopped after signing because the old
development copy was still running; the new fixed-location app was installed separately
without replacing that copy). Computer-use access to Angrove was denied. The owner's
first authorization and subsequent prompt-free relaunch remain to be verified; no
Keychain item, permissions or saved data were changed. After the old normal workspace
closed, the installed app was launched. A second actual launch exited and process
inspection confirmed exactly one `/Applications/Angrove.app` workspace process remained.

From this worktree, using Xcode 27:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/mac-foundation CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/mac-foundation CODE_SIGNING_ALLOWED=NO test

open build/mac-foundation/Build/Products/Debug/Angrove-macOS.app
```

Unsigned local verification is sufficient for this UI foundation. Signed sandbox behavior and
distribution still require verification before personal persistence or model delivery ships.
The target enables App Sandbox and Hardened Runtime for signed builds.

Verified on the development Mac with Xcode 27.0 and macOS 27.0.1:

- Mac Debug build passed; executable is arm64, generated minimum OS is 27.0.
- Six tests passed: five hardware eligibility cases and one native-library linkage/API case.
  Evidence: `build/mac-foundation/Logs/Test/Test-Angrove-macOS-2026.10.12_16-56-29--0400.xcresult`.
- Shared theme and existing UIKit color helpers type-checked against the arm64 iOS simulator
  SDK. This was not a full iOS build, phone install, or release validation.
- Launched the preview and inspected its dark appearance, Home layout, all sidebar
  destinations and Settings window. Light appearance and minimum-window layout still need
  interactive verification.
- The vendored wrapper emits an existing unavailable-Sendable warning involving
  `OpaquePointer`; this milestone makes no runtime concurrency changes.

## Next work

1. Adapt the existing conversation types and orchestration behind narrow platform boundaries.
   `InquiryModels.swift` currently references attachments, evidence, inline markup and saved
   Insights; it cannot simply be added to the Mac target in isolation.
2. Adapt encrypted persistence and startup key validation. Review file protection, Keychain
   and sandbox access on Mac while retaining existing encryption and migration contracts.
3. Adapt the existing process-scoped runtime and task queue. `ModelTaskQueue` uses UIKit
   background tasks; the app composition, memory pressure and lifecycle need Mac adapters.
   Retain the current AngroveModel boundary, Gemma E4B artifact/configuration and no-backend
   architecture. Follow the existing shelving restrictions and model documentation.
4. Establish Mac model acquisition and verification before running a bounded, new Mac smoke
   check. Reuse the manifest and integrity rules; determine Mac delivery without assuming
   the iOS managed asset-pack extension can be reused unchanged.
5. Complete one real conversation: submit, stream, persist, reopen; then adapt reading and
   Insight Tree interactions. Add commands and multi-window behavior around shared services.
6. Add Mac app icons, signed validation, accessibility, light/dark and minimum-window checks.

The current Home preview is not yet the iOS Home dashboard or Model Download status card.
Those features must be explicitly connected to shared feature state during the next milestones.

## First real Mac inference — October 12, 2026

Owner requested trying a question. A standalone, opt-in raw diagnostic using the same
vendored Swift wrapper as the existing iOS raw probe completed successfully. This is not
the Mac app's live generation implementation; production actions must still go through
`AngroveModel`, the shared runtime and task queue when those are connected.

- Run: `MAC-E4B-GPU-1`, immutable evidence under `output/mac-runtime/MAC-E4B-GPU-1/`.
  Report, exact arguments, source snapshot/hash, model digest, stdout and native stderr saved.
- Host: Apple M4 Pro, 24 GiB installed RAM, macOS 27.0.1. The native log reports a WebGPU
  environment using the Metal adapter and main GPU executor. Embeddings use CPU components.
- Model: existing `Aquinas-iOS-main/Angrove-iOS/LocalModels/gemma-4-E4B-it.litertlm`, read
  directly without copying or modification. Size 3,659,530,240 bytes; verified SHA-256
  `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
- Runtime: existing LiteRT-LM 0.14.0 Mac dylib SHA-256
  `eddb330164eb9cf911f74320c6a41b368fef43b42d1232874cc658e161b48779`.
- Configuration: GPU, 4,096 context, activation override F32, greedy top-k 1 / top-p 1 /
  temperature 0 / seed 0. Native thinking, MTP, vision and audio off. Raw system instruction
  `Answer clearly and in one concise sentence.` No retrieval, production prompts or history.
- Question: `What is prudence?`
- Exact answer: `Prudence is the ability to govern and discipline oneself by the use of reason.`
- Load 2.643 s; synchronous answer generation 1.195 s. The file was hashed before loading,
  so these are warm filesystem single-run observations, not cold-cache benchmarks or
  time-to-first-token measurements. No peak-memory or 16 GiB-machine gate is claimed.
- The optional dynamic sampler dylib was absent; native logs confirm use of the statically
  linked WebGPU sampler C API. The diagnostic completed and exited with status zero;
  its PID was absent afterward. No CPU-decoder fallback or repeat was run.
- Reusable diagnostic source: `Tools/MacRuntimeSmoke.swift`; it is outside app source groups
  and cannot replace the live app model boundary. The launcher imposed a 180-second external
  deadline. Native compile caches remain in this ignored diagnostic output directory.

### Model storage for the Mac edition

Mac-specific model identity, runtime selection and delivery configuration belong in the Mac
composition layer. Installed weights belong in the Mac app's own Application Support model
directory (inside its sandbox for signed builds), with integrity verification and a distinct
runtime cache directory. They should not be tracked in Git or placed among Mac UI source files.
Local development may reference an existing verified artifact directly. A larger Mac model has
not been selected or downloaded; evaluate its weights, context/KV cache and runtime memory on
the 16 GiB baseline before adopting it. The previously shelved 12B research remains shelved.


## Mac conversation design — October 12, 2026

Implemented the `08-Mac App` frames in Figma file `JBM9BM0Zo6JHgj7NCjxcRt`:
`open-conversation-top` (1075:4739) and `open-conversation-scrolled` (1075:4993).
The owner explicitly requested the actual iOS SF Symbols in place of Figma's SVG icons.

- Native SwiftUI floating sidebar, 500-point reading column, shared brand colors and fonts,
  48-point transcript spacing, anchored model dock, pinned title and scroll-edge gradients.
  Default content size 1440×900, minimum 760×540; shorter windows scroll independently in
  the sidebar and transcript, with footer controls remaining accessible.
- The Mac compiles the existing `AppPage` icon names and `AppIconImage` source/resource.
  `ContextUsageIcon` moved unchanged to DesignSystem so both platforms compile one gauge.
  The iOS app icon loader continues using its asset catalog; Mac loads the same PNG resource.
- Native question editing, sidebar navigation, Settings, recent-preview menu and model-status
  popover are interactive. Draft text survives sidebar navigation and the explicit unavailable
  model alert; New Conversation clears the draft. No live generation or persistence is claimed.
- The supplied Figma conversation is a DEBUG-only fixture. It is not a model answer or saved
  conversation, and is not included in Release builds. The window is named
  `Angrove – Design Preview` when showing the fixture. Normal launch opens an empty inquiry.
- Existing Home and unfinished destinations remain development placeholders; their designs
  were outside this requested conversation screen.

Launch the exact top and scrolled development states:

```sh
open -n build/mac-foundation/Build/Products/Debug/Angrove-macOS.app --args \
  --mac-design-preview --mac-preview-light
open -n build/mac-foundation/Build/Products/Debug/Angrove-macOS.app --args \
  --mac-design-preview-scrolled --mac-preview-light
```

Quit the existing instance before switching flags. `--mac-preview-compact` opens 760×540;
`--mac-preview-dark` selects dark appearance without changing system settings. Fixtures and
appearance overrides are development-only. Window restoration is disabled for these checks.

Verification superseding the initial foundation checks above:

- Mac Debug and Release builds passed, as did all six existing hardware/native-linkage tests.
  The Release executable contains neither preview launch flags nor Figma sample copy.
- Full iOS arm64 iPhone 17 / iOS 27 simulator build passed after sharing the visual components.
  No physical phone build was installed or canonical main checkout edited.
- Compared native light top/scrolled states to both Figma exports. Checked title pin/unpin,
  navigation, dark appearance, smaller windows, empty state, model popover and retained draft.
- Local logs: `/tmp/angrove-mac-figma-build.log`, `/tmp/angrove-mac-figma-test.log`,
  `/tmp/angrove-ios-shared-build.log`; design exports under ignored `output/mac-figma/`.

## Resizable conversation Insight Tree — October 12, 2026

Refreshed both conversation frames after the owner added the right-hand handle and changed
both edge gradients to 200 points. The native divider has a 149-point painted bar, a larger
pointer target, a horizontal resize cursor, a 5% hover scale, and accessible 5% adjustments.
Dragging left opens the tree; dragging right closes it. The Insight dock button always sets
its width to 50% of the conversation workspace (excluding the floating sidebar). Width is
stored as a fraction so window resizing keeps the split. Closing the pane keeps its mounted
canvas and camera alive. A new conversation starts a new workspace.

The Mac target now compiles the actual iOS `InsightTreeCanvasView` and its feature extensions,
including dot-grid rendering, physics, connector routing, crisp text/SF Symbols, selection,
chip drag, focus/restore and Study orbit camera. Shared fonts, transition primitives, feedback,
geometry and encrypted tree-store primitives were extracted rather than duplicated. UIKit
feedback remains UIKit on iPhone; Mac uses native trackpad haptics. Mac encrypted storage has a
separate Keychain service and Application Support root; iOS paths/key identity are preserved.

Mac canvas navigation:

- Scroll up/down pans vertically; native horizontal trackpad deltas also pan horizontally.
- Shift-scroll up/down pans left/right, including AppKit's remapped X-axis Shift-wheel events.
- Command-scroll up/down zooms in/out around the pointer, within the shared canvas's limits.
  Command takes precedence when both modifiers are held.
- Mouse dragging and trackpad magnification retain the iOS canvas gesture logic. Study uses its
  own shared pan/zoom state and retains ring dragging for rotation.
- Only scroll events inside the visible canvas are consumed. Conversation and docked-definition
  ScrollViews keep their native scrolling. Event monitors are removed on teardown.

The initial canvas wrapper below has now been superseded by the shared full feature presenter
and queue integration described in the next milestone. Figma-labelled samples remain DEBUG-only;
normal conversations use real saved content and on-device generation.

Verification:

- Mac Debug and Release builds pass; all 11 Mac tests pass (including divider behavior, native
  scroll-axis mapping, modifier precedence, pointer-preserving zoom and zoom bounds).
- Full iOS 27 arm64 simulator build passes. All 13 personal-data encryption tests pass using
  an ad-hoc signed simulator build; unsigned simulator tests lack Keychain entitlement access.
- Camera, semantic membership and canvas persistence selection: 28 pass, 2 fail. The failing
  midpoint scope/edge and removal visibility expectations also fail on an untouched `19baca9`
  baseline checkout (3 parameterized failures there). No midpoint algorithm was changed here.
- Native UI inspected at 1440×900 light and 760×572 dark: half-width opening, divider dragging,
  vertical wheel panning, node cards, Study, compact controls and accessible divider increments.
  Command/Shift mapping is regression-tested; the UI automation API cannot hold modifiers alone
  for a wheel event. No physical iPhone installation or canonical-main edits were made.
- Logs: `/tmp/angrove-mac-tree-test.log`, `/tmp/angrove-mac-tree-final-build.log`,
  `/tmp/angrove-mac-tree-release.log`, `/tmp/angrove-ios-tree-build.log`,
  `/tmp/angrove-ios-tree-signed-test.log`, `/tmp/angrove-ios-encryption-signed-test.log`,
  `/tmp/angrove-ios-tree-baseline-test.log`; baseline failure summary retained in
  `/tmp/angrove-ios-baseline-summary.json`.


## Shared conversation, tree and queue — October 12, 2026

The Mac workspace now hosts `InsightTreeView`, not a second implementation of its cards or
controls. The same presenter supplies bookmarking/removal/undo, quote/fork, selection, search,
Study, Make Node, Branch and Midpoint. It retains the native scroll adapter, resize divider,
50% opening, 5% handle hover scale and 200-point edge fades. Global Insights uses the same
bookmark snapshot and explicit update/reconciliation contracts as iOS.

`InquiryControlDock`, `ModelControlsHost`, `ModelTasksCard`, Context and Reading cards are
compiled into both targets from the same files. The queue is process-scoped and runs actual
`AngroveModel` jobs. Waiting questions build their context when execution starts, so earlier
answers are present. Removing a waiting question restores its draft; stopping a running answer
shows the shared cancellation state. Clear gives the branch a new identity, and per-response
run IDs reject late updates from a cancelled or regenerated job.

Mac uses the shared response renderer, SF Symbols, Insight cards, definition menus, copy,
regeneration and read-aloud. The native word context menu offers Copy, Define and Read from
here. Paradee/Misaki/ONNX synthesis and AVAudioEngine back the shared player and Reading card;
this is the same speech engine, not a substitute voice. The source assets and package products
are reused. Shared typography scales point sizes by 0.85 only on Mac; iOS retains its existing
sizes. Body text specified at 14 points becomes 11.9 points on Mac.

The development app reads the **already present pinned Gemma 4 E4B** from the canonical
checkout without copying or downloading weights. SHA-256 verification runs off the main
thread before the first runtime lease loads it. Release uses its own installed-model location.
Mac conversation files, tree state, model paths and personal Keychain service are separate
from iOS. Conversations appear in Recents and can be reopened. No phone build was installed,
and the canonical checkout was not modified.

Verification for this milestone:

- Mac Debug and Release builds pass. Eighteen Mac tests cover hardware/linkage, canvas input,
  queue completion/reordering/cancellation, queued context including an earlier answer,
  restoring a removed draft, rejecting completion after Clear, and isolating preview tree IDs.
- Full signed arm64 iOS simulator build and 36 focused tests pass: model lifecycle/queue,
  Insight Tree growth and personal-data encryption.
- Native UI checks: compact light and full-size dark layouts; global empty canvas; tree cards,
  Study and Branch controls; search and next-result navigation; real question and definition
  generation; current/upcoming queue rows, Remove and Stop; real read-aloud, Pause and Stop.
- Logs: `/tmp/angrove-mac-parity-test.log`, `/tmp/angrove-mac-parity-release.log`,
  `/tmp/angrove-ios-parity-test.log`. UI generation used the production shared model boundary,
  not mock answers. Delayed test answers exist only in the test target.

Remaining Mac-port work: full Home/Study Topics/Library navigation, full passage browsing and
attachment pickers, distribution model delivery, signed sandbox validation, app-lock/privacy
lifecycle integration and sustained performance checks on a base 16 GB Mac. The current
Passages menu offers existing clipped passages. Mac has not yet bundled the full grounding
corpus/MiniLM assets; existing production grounding fallback remains explicit in response
provenance. These screens and distribution concerns are not claimed as completed by sharing
the conversation/tree/queue components. The 16 GB support threshold remains a product target,
not a performance certification from this 24 GB development machine.


### Card width alignment — October 13, 2026

On Mac, docked Insight and tool cards use the current measured controls width, with the
phone-only side inset removed. Their height is measured at that constrained width, and the
Mac host lets the stack grow naturally above the bottom-pinned controls. iOS retains its
existing inset and height behavior. The Mac Debug build passed and the saved-conversation
Insight card was visually verified with matching left/right edges and all controls visible.


### Foreground ordering — October 13, 2026

The Mac sidebar has a foreground layer above workspace content. Each canvas is a compositing
group, so its node depth ordering cannot cover the floating controls and docked cards.
Focused or dragged Insight chips draw above other canvas nodes on Mac; iOS keeps its existing
semantic depth ordering. The Mac build passed; the active card and native Add menu were
visually checked above the saved conversation’s tree.


### Context and minimum tree size — October 13, 2026

The conversation Context button remains available while its tree is open. The displayed token
estimate follows iOS: the un-compacted question/response text plus the checkpoint, without the
model request’s system reserve. Compaction uses only new turns and the existing checkpoint,
keeps visible history intact, and protects against late completion after Clear. Compact is
disabled during pending responses or when no new context remains. Clear also resets the draft.

The separate tree button sits to the right of the controls and uses the iPhone toggle’s
`point.3.connected.trianglepath.dotted` symbol. It opens the right pane without navigating away.
Tree content has a 500-point minimum; a narrower available viewport clips that content instead
of reflowing it. A resize from above the minimum stops there. After releasing, another inward
drag from the minimum collapses the panel on release; reversing the drag cancels that collapse.
The handle is 2 points wide, uses `AngroveTheme.Colors.treeConnector`, and retains its broad
hit area and 5% hover growth.

Verified: 25 Mac tests passed, full iOS simulator build passed, and native UI confirmed the
Context card beside the open tree, Clear’s confirmation (cancelled without clearing saved
history), real on-device compaction reducing the estimate from 406 to 83, resizing to the
minimum, collapsing on a second drag, and reopening with the new right-hand button. Logs:
`/tmp/angrove-mac-context-resize-test.log` and `/tmp/angrove-ios-context-control-build.log`.


### Insight Ask flow — October 13, 2026

Ask in a conversation attaches the selected Insight to the editable question, dismisses the
tree card, closes the tree pane, scrolls to the composer and focuses it. Draft and submitted
quotes use the shared BranchContextChip; draft quotes can be removed without clearing the
question. Quote attachments use the shared ChatBranch draft fields and remain part of the
submitted user block and model context. Inline definitions and clipped passages use the same
attachment action. Global Insights offers New Conversation, Existing Conversation and Cancel;
the existing-conversation picker attaches the Insight to the chosen conversation.

Verified the native Ask-to-editor flow, focused typing, quote removal, global destination
actions and existing-conversation picker. The Mac build and all 28 tests passed, including
quote attachment/removal and first/follow-up question context. Log:
`/tmp/angrove-mac-ask-final-test.log`. No phone build was installed.


### Slash commands — October 13, 2026

The native Mac composer reuses SlashCommandMenu and the shared invocation parser. Typing a
bare slash token shows prefix-filtered suggestions; selecting inserts the command and keeps
the editor focused. Escape dismisses suggestions. Submission dispatches /compact, /clear,
/rename, /new, /tree, /topic and /insights locally. /define with a subject retains the existing
model response route; a bare /define stays editable. /clear confirms before resetting, and
/new leaves queued work running. The Study Topic picker supports existing topics, no topic
and explicit topic creation. Saved conversation updates retain custom names, topic assignment
and existing metadata instead of rebuilding a fresh record on every response.

Verified compact dark suggestions, filtering, insertion, Enter submission, rename prompt,
empty Study Topic picker and cancelled clear confirmation. Mac build and all 30 tests pass.
Logs: `/tmp/angrove-mac-slash-build.log`, `/tmp/angrove-mac-slash-test.log`.


### 14-point body text — October 13, 2026

Owner requested the Codex-sized 14-point body baseline. Removed the implicit 0.85 Mac
typography reduction; shared tokens now use their specified point sizes on both platforms.
Mac responses explicitly use Medium (14 points), matching the question editor and body
copy. This supersedes the earlier desktop scaling note; iOS point sizes are unchanged.
Mac build passed and the compact dark preview was inspected for wrapping and controls.
Log: `/tmp/angrove-mac-font14-build.log`. The control layout remains unchanged while the
owner considers alternatives to the side-by-side conversation/tree presentation.


### Tree visibility toggle — October 13, 2026

The bottom tree button toggles visibility and labels its current Open/Close action. Closing
remembers the current split fraction; reopening restores it within the window’s existing
minimum/maximum constraints. Divider collapse and Ask-driven closing preserve the same width
memory. /tree explicitly opens the pane, restoring its last split when closed and leaving an
already-open pane’s width unchanged. The canvas remains mounted while hidden.

Mac build/test passed. Native preview verification resized the pane from 50% to 54%, closed
and reopened it with the button, then confirmed /tree restored 54%. Log:
`/tmp/angrove-mac-tree-toggle-test.log`.


### Local Release model installation — October 13, 2026

The owner’s running desktop app was Release, which does not use the DEBUG checkout model
path. Installed the already-present pinned E4B package in
`~/Library/Application Support/Angrove-macOS/Models/gemma-4-E4B-it.litertlm` using an APFS
copy-on-write clone. Source and destination were verified at 3,659,530,240 bytes with SHA-256
`0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`. Wrote the matching
`.verified.json` receipt required by LiteRTModelStore. No weights were downloaded or modified.

Rebuilt Release and restarted the normal app. During verification, the owner submitted
“When was the council of nicaea”; the UI displayed “The First Council of Nicaea met in the
year 325.” and returned to Idle. This verifies availability and an ordinary conversation
answer, not sustained performance or signed sandbox delivery. Build log:
`/tmp/angrove-mac-installed-model-release-build.log`. The app was left open for testing.

### Follow-up question reveal — October 13, 2026

The empty Mac question field now fades in when the shared response renderer reports the
body complete, alongside the footer's action entrances. It uses the shared 0.35-second
finishing animation and respects Reduce Motion. Existing drafts, focused editors and attached
quotes stay available. Readiness follows the latest response run, so regeneration hides the
empty field again and callbacks from an old run cannot reveal it. Restored answers and new
conversations show the field immediately. The iPhone composer already uses this body-complete
event and timing; its implementation is unchanged.

Mac Debug and Release builds and the iPhone simulator build passed. All 13 Mac conversation
tests and four iPhone response finishing tests passed. Native checks covered the initial
question and restored follow-up field. Logs: `/tmp/angrove-composer-fade-mac-test.log`,
`/tmp/angrove-composer-fade-mac-release.log`, `/tmp/angrove-composer-fade-ios-build.log` and
`/tmp/angrove-composer-fade-ios-test.log`. No phone build was installed.


### Response layout and generation presentation — October 13, 2026

Mac conversation requests now enable the shared progress presentation. The response card shows
queued/thinking/writing states, the app's public approach line and actual retrieved source rows,
then the shared text fade and persistent thinking disclosure. Native Gemma thinking remains off
by default; when the runtime emits a thought channel, Mac forwards its current line and retains
the complete returned summary. Recorded preparation time excludes queue waiting. Completion
retains source passages and thinking metadata for reopening saved conversations.

Inline link labels retain their intrinsic width on Mac. Live annotated tokens measure the bold
font used by their overlay, and annotation changes invalidate the word measurements. This fixes
the ellipses in “First Council of Nicaea” and other completed and live response links.

The Mac resource phase now includes the existing MiniLM package, vocabulary, frozen corpus and
embeddings. Local assets were cloned from the canonical checkout into the ignored
`Angrove-iOS/LocalGrounding` directory; no download or canonical-checkout change occurred.
Xcode compiles the MiniLM package for Mac. This supersedes the earlier missing-grounding-assets
limitation; full Library reader/navigation support remains separate work.

Verification: Mac Release build and full iPhone 17 simulator build passed; all 34 Mac tests
passed, including real bundled retriever loading and Nicaea source lookup, plus live progress,
actual thought forwarding, source retention and reopening. Native Release UI showed the old
Nicaea link in full, the John 14 disclosure with expandable original passages, and a new Nicaea
answer's live approach/source animation and text fade. Logs:
`/tmp/angrove-mac-response-release.log`, `/tmp/angrove-mac-response-final-test.log`,
`/tmp/angrove-ios-response-build.log`. No phone installation was performed.

### Floating conversation Insight Tree — October 13, 2026

The conversation tree opens from a 48-point control at the workspace’s top-right, inset
24 points. Completed tree changes show “Updated” for five seconds with the iPhone’s
0.28-second transition and subtle 5% grow, respecting Reduce Motion. The default tree
floats over the conversation with 24-point outer margins and a 500-point starting width.
Its left handle resizes it; closing and reopening retains the width in points.

Pin moves the same mounted canvas into the existing divider layout. X restores the
conversation’s full width while retaining pinned mode; opening again restores the split.
Only Unpin returns to floating presentation. Each mode retains its sizing state. Conversation
tree cards render within the tree, inset 24 points from its bottom, independently of Model
Controls. Global Insights retains its existing controls/card layout.

Regression coverage includes floating width memory, narrow-window clipping, pin/close/reopen/
unpin transitions, and the existing divider behavior. No iPhone source or model configuration
was changed.

Verified: all 36 Mac tests passed and Release build passed. Native dark-mode inspection
confirmed floating margins, 500-point initial width, resize and reopening at 550 points,
pinned closing/reopening, unpinning, a selected Node Concept card at the frame’s bottom,
and visible controls beside the overlay. Logs: `/tmp/angrove-floating-tree-final-test.log`
and `/tmp/angrove-floating-tree-release-final.log`. Light appearance and compact-window
visual inspection remain unverified; narrow-window sizing is covered by layout tests.

### Tree button-to-panel transition — October 13, 2026

The collapsed tree control and expanded tree now share one persistent surface. Opening
animates its width and height from the top-right 48-point capsule to the remembered tree
frame, crossfading canvasSecondary into the tree’s canvas background. Closing reverses
this growth. The persistent control swaps the tree symbol and X with the same shared
8-point blur-fade transition used by Model Controls, timed at 0.28 seconds. Pin arrives
beside the X. Reduce Motion removes geometric growth and blur while retaining a fade.

The conversation view has an additional 24-point inset on all sides within its workspace
frame, including when pinned beside the tree. Controls retain their existing bottom inset.
The canvas remains mounted and floating/pinned width memory is unchanged.

All 36 Mac tests passed. Native dark-mode checks and the recording confirmed the intermediate
expanding frame, fill transition, icon swap, closing, reopening and pin/unpin presentation.
Recording: `output/tree-demo/insight-tree-morph.mp4`. Test log:
`/tmp/angrove-tree-morph-test.log`. No iPhone sources or model configuration changed.
Release build also passed: `/tmp/angrove-tree-morph-release.log`.

### Swap conversation and Insight Tree — October 13, 2026

The expanded pane’s top-right controls use plain green icons with a 16-point row gap.
Swap is the rightmost action. It exchanges the main and secondary content: the tree
becomes the main canvas and the conversation occupies the remembered smaller frame.
The same action works while pinned, exchanging the two divider slots. Both presenters
stay mounted rather than rebuilding a second conversation or tree.

Pin/unpin, resize and close/reopen retain the current orientation and secondary width.
X always closes the secondary pane. When the conversation is secondary, closing it leaves
the tree full width and keeps the shared controls available. Ask still closes the secondary
pane in the ordinary orientation; when swapped, it opens the conversation so the attached
quote and focused composer are accessible.

All 37 Mac tests passed, including swapped floating/pinned sizing and reopening. Native
dark-mode checks verified plain controls, both Swap directions, pinning with the tree as
main, and closing/reopening the smaller conversation with controls retained. Log:
`/tmp/angrove-tree-swap-final-test.log`. No video was recorded for this change.
Release build passed as well: `/tmp/angrove-tree-swap-release.log`.


### Quoted question editor — October 13, 2026

The Mac composer and submitted questions now use the iPhone quotation layout, extracted into
`DesignSystem/QuotedQuestionContainer.swift` and compiled into both apps. The complete quoted
container caps at 285 points when trailing (321 for the shared centered variant). It hugs short
text, reserves only punctuation space, and keeps the opening quote on the first line and closing
quote on the last. The same spring controls wrapping and placeholder-width transitions, with
Reduce Motion respected. Quotes are presentation only, excluded from the submitted text.

Mac keeps native editing, focus, Return submission and slash commands. The empty editor measures
its placeholder instead of using a fixed width; nonempty drafts grow to the quoted width limit
and wrap without the former eight-line cap. Submitted questions retain selectable text.

Mac Debug/Release and full iPhone 17 simulator builds passed. Native UI inspection covered the
quoted placeholder, existing submitted question, typed multi-line draft and quote movement.
The unsubmitted verification draft was cleared. Logs: `/tmp/angrove-mac-quotes-build.log`,
`/tmp/angrove-mac-quotes-release.log`, `/tmp/angrove-ios-quotes-build.log`.

### Separate conversation and tree controls — October 13, 2026

Each conversation workspace slot now owns a persistent shared ModelControlsHost. The main
slot and secondary slot remain in place during Swap; their controls IDs change between
conversation and tree, invoking the shared blur-fade and capsule sizing animation. Floating
and pinned geometry use the same fixed-slot ownership. Conversation Send/Context remains
available while the tree has its own Search, selection, Ask, Study, queue and tool controls.
Both publishers use the existing process-scoped runtime and queue, with separate Context
and model-task popup presentation state. Switching slot roles dismisses its old popup.

The canvas publishes its docked card to the host currently displaying tree controls. Cards
and Study tools stack above that host using the mobile ModelControlsStack, superseding the
previous frame-bottom placement. The preference boundaries prevent the two controls
configurations or cards from merging into one bar. Closing the secondary slot hides only
that host; the main host remains available for its current screen.

All 38 Mac tests passed, including controls slot widths remaining unchanged on floating
and pinned swaps. Native dark-mode checks confirmed simultaneous conversation/tree bars,
both controls changing on Swap, cards above tree controls before and after Swap, and a
pane-local queue popup dismissing when its slot changes role. An existing unfinished
question was restored after reloading the build; no question was submitted for verification.
Test log: `/tmp/angrove-two-controls-test.log`. No iPhone source or model configuration changed.
Release build passed: `/tmp/angrove-two-controls-release.log`.
Final typography-token compile also passed in an isolated build directory to avoid a concurrent
build's database lock: `/tmp/angrove-mac-quotes-isolated-build.log`.

### Compact tree header actions — October 13, 2026

The open pane’s actions are now icon-only, ordered Swap, Pin, X from left to right,
with the existing 16-point row gap. Swap retains its accessibility label and tooltip.
Inactive Pin remains the green outline `pin`; active Pin uses `pin.fill` and the shared
accentRed token. Clicking the filled pin still unpins. The Mac Debug build passed,
and native dark-mode inspection confirmed the order and both pin appearances.
Log: `/tmp/angrove-tree-header-build.log`. No video was recorded.

### Floating pane outline and swapped toggle — October 13, 2026

The floating secondary pane now draws its full outline above the model controls fade,
so the bottom edge remains visible for both the tree and swapped conversation pane.
The collapsed toggle uses the shared conversation icon when the conversation occupies
that pane; its symbol retains the existing blur-fade transition.

Mac Debug build passed (`/tmp/angrove-tree-border-build.log`). Native visual checks
confirmed all four border edges before and after Swap, plus the conversation toggle
when closing the swapped pane. No video was recorded.

### Minimized conversation update cue — October 13, 2026

Completed answers now increment a session completion signal after the final response is
stored. When Swap puts the tree in the main slot, that signal drives the minimized
conversation button's existing Updated label and grow animation, including its five-second
dismissal. Question answers, quoted Insight inquiries and regenerated answers use the same
completion path. Canceled responses do not emit the signal. Tree changes drive the cue only
when the tree occupies the secondary slot, so background tree analysis cannot trigger a
conversation update cue. Changing the toggle's role clears any previous cue.

The existing animation implementation is reused unchanged. All 39 Mac tests passed,
including completion timing, quoted Insight answers, regeneration and cancellation.
Log: `/tmp/angrove-conversation-updated-test.log`.


### Conversation controls and command editor — October 13, 2026

The whole collapsed Insight Tree capsule opens the pane. Mac tree controls omit attachments
and Context; conversation controls omit Send, retaining Return submission. Slash suggestions
sit below the quoted editor and remain clear of the bottom fade. The top scroll fade begins
at the pane edge and extends through the top safe area. Quoted Insights have separate full
hit regions for opening the Insight and removing it with X; their border is decorative.

The native Mac question editor sweeps recognized slash-command text to green over one second,
using the shared invocation parser. Arguments retain the ordinary text color. Reduce Motion
applies green immediately. Native selection, undo, multiline wrapping, Shift-Return and
Escape remain available; command insertion moves the cursor to the end.

Mac Debug and iPhone simulator builds passed. All 53 Mac tests passed;
light/dark compact composer renders were inspected at `/tmp/angrove-composer-light.png` and
`/tmp/angrove-composer-dark.png`. Native pointer verification was unavailable because Computer
Use access to Angrove was denied.


### Live response reveal pacing — October 13, 2026

Live response blocks now reveal newly arrived words in the same four-word, 27.5-millisecond
batches as completed responses. A final large batch continues the existing reveal instead
of becoming visible in one step. Completion waits for every block to finish revealing and
for the last 0.55-second word fade before showing response actions and the follow-up composer.
Restored answers and Reduce Motion skip the pacing. The conversation column now caps at
650 points (previously 500), keeping the existing narrow-pane margins.

All 54 Mac tests passed, including a mounted first-word response followed by 200 completed
words: intermediate words reveal progressively and completion stays pending until the body
finishes. iPhone response navigation tests passed. Logs: `/tmp/angrove-response-reveal-test.log`
and `/tmp/angrove-response-reveal-ios.log`.
Release build passed. The signed update was installed at `/Applications/Angrove.app` and
reopened after the owner quit normally. Install log: `/tmp/angrove-response-reveal-install-final.log`.


### Matched sidebar and paragraph sizing — October 13, 2026

Conversation response paragraphs, the sidebar menu, and native question editor now reference
`MacConversationStyle.bodyFontSize`. They use the existing 13-point Mac typography baseline.
Release build passed and the signed update was installed at `/Applications/Angrove.app` and
reopened. Log: `/tmp/angrove-paragraph-size-install.log`.
