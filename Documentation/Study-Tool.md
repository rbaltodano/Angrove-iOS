# Study Tool

## Purpose

Study is a focused way to explore a Node Concept and its Insights in full 3D without losing
the user's place in the Insight Tree. It is not a separate screen with a copy of the node: the
tree canvas moves its own camera into a 3D view of the node the user was looking at, fades the
rest of the tree, and moves back on exit.

A short [demo video](Screenshots/study-3d-demo.mp4) shows entering Study, rotating, hovering,
and exiting.

## Entry and exit

1. The user hovers a Node Concept or an Insight in the tree and selects **Study**
   (`graph.3d`). Hovering an Insight and choosing Study opens its parent Node Concept with that
   Insight hovered.
2. The docked card scales away (the same transition as switching Insights), then the Study
   tool card pops up in its place (the same transition as hovering an Insight).
3. The tree's camera swings from overhead to eye level over 0.8 s and flies the node into the
   300 × 300 Study slot. Everything else in the tree moves with the same camera while it
   fades; the flat dot grid fades into a receding dot floor. The node's Insights leave the
   tree's ±45° band and spread over a sphere around it.
4. The side-menu button grows an **× Exit** capsule. Exit hands the dock and card back
   immediately, then moves the camera back into the tree (any whole turns are dropped first,
   so it unwinds at most half a turn). Whatever was hovered in Study stays hovered.

## The 3D view

| Element | Behavior |
| --- | --- |
| Camera | Level with the node, looking down at a floor ring. Opens at 2× zoom. |
| Insights | Tree-sized chips spread in 3D (Thomson directions, deterministic), retaining each semantic bond radius. Chips behind the node dim smoothly and draw behind it. |
| Ring | A dashed 300 × 42 ellipse 24 pt above the tool card; gradient 5% (far) to 40% (near). Stays fixed while the user pans or zooms. Its dashes turn with the node. |
| Floor | The tree's dot grid laid on the ring's plane at 50% opacity, receding toward the horizon. It moves 1:1 with the node camera. |

Gestures (Study only; the tree's own gestures are off):

- **Drag the ring** to spin the node like a turntable (detent haptic every 15°). Releasing
  mid-swipe keeps it turning and easing to a stop. The ring brightens and grows 5% while held.
- **Drag elsewhere** to pan. **Pinch** to zoom (0.5×–5×).
- **Tap an Insight** to hover it, exactly like hovering in the tree (haptic, card state, and
  connector pulse). The camera centers it 70 pt below the node's spot with the tree's hover
  spring, zooms in by the tree's hover amount measured from Study's opening zoom, and makes it
  the axis of rotation. A hovered Insight never dims.
- **Tap the node** to hover it; the camera glides back to center it.
- **Pan off a hovered Insight** to unhover it; the hover returns to the node and the axis of
  rotation returns to the node's center without moving the view.

## Tool card

Branch is the only launch tool. It is available only while an Insight is hovered in Study;
Node Concepts do not offer it. Activating **Branch** isolates the Insight, hiding the rest of
the tree, and shows `StudyToolCard` with the Insight card's chrome (`dockedCardChrome`).
Deconstruct and Sequence remain post-launch work; there are no tool-switching controls.

## Dot matrix (retained, currently unused for most Insights)

> **Before launch:** the dot matrix is kept in case it becomes useful again. It is only
> reached from Insights without an ordinary parent Node Concept (placed midpoints). If it is
> still unused when the app goes live, remove `StudyDotMatrix`, its Branch and Deconstruct
> visuals, and the `.insight` Study subject.

`StudyDotMatrix` draws seven concentric rings around the central Insight symbol. The innermost ring is intentionally omitted, leaving visual space for the focal Insight.

### Base-dot entrance

Each base dot has a deterministic, per-Insight random delay between **0.2 and 1.0 seconds**. Dots enter concurrently rather than as a serial sweep:

- They appear at 4 points.
- They remain at their initial size for 0.2 seconds.
- They settle to 2 points over 0.16 seconds.

Each arrival registers a haptic event. Events that land within a tiny perceptual window are combined into a stronger impact, which preserves the sensation of simultaneous dots instead of letting device haptics discard overlapping requests.

## Branch

Branch decomposes the selected idea into **2–6 more fundamental points**, each saved as an
Insight. It uses `AngroveModel.generateChildren(for:count:)` on the shared on-device runtime
and serialized queue, never the session-only prototype proposals.

1. Activate Branch while studying an Insight. Everything except that Insight fades away.
2. Choose the count with plus/minus, then confirm with **Branch**. Controls lock until the
   operation finishes. If queued, the original Insight stays visible until the job starts.
3. The Insight fades into a Node Concept with exactly the same title. Only its title uses
   the existing `ThinkingShimmer`; the node icon remains steady during generation.
4. Wait for the full validated batch. No child loading icons or partial model results appear.
5. Release the children with randomized **0.1–0.25 s gaps between bursts**. Each burst uses
   a 0.65 s acceleration/deceleration curve, one medium haptic, and a small recoil of the
   Node Concept opposite the outgoing Insight. Reduce Motion substitutes fades and omits recoil.
6. Burst directions and radii come from the actual tree layout and semantic bond lengths,
   with a uniform viewport fit that preserves their relative lengths. On completion the isolated
   workspace hands its chips and both connector types back to the tree, focusing Study on the
   new Node and revealing its connected parent. Generated Insights retain
   stable identities, are bookmarked, and survive reopening the tree. The new Node Concept keeps a persisted connection to its original parent, even if
   it was that parent's only Insight. A placed midpoint Insight retains its source-node
   connections when promoted. Exiting Study returns to the full connected tree.

Failure or queue cancellation rolls back the temporary promotion and restores the original
Insight. The ordinary model-action error offers retry. Leaving the workspace before a queued
job starts prevents that stale request from promoting a different Insight.

`StudyBranchDockControls` uses two 64 pt pills: the 2–6 selector and confirmation action.
`StudyBranchScene` owns the isolated crossfade, text shimmer, staggered releases, and recoil.
The debug-only `--study-branch-preview` launch option exercises that presentation with clearly
labeled test content and no live runtime or persistence. Add `--study-branch-preview-tree`
to exercise the real Canvas, including the completed Branch handoff and its parent connection.

## Deconstruct

Deconstruct begins by highlighting every dot in the fourth ring from the center. Those dots reveal in a shuffled order, using the same individual haptic-arrival treatment as Branch markers. After the ring has had time to complete, its 2 o’clock dot returns to the normal base-dot treatment while the matching 2 o’clock dot on the sixth (outer) ring grows into a persistent highlighted marker and registers a haptic.

This outward transfer is the first visual metaphor for decomposition: a selected semantic component separates from the Insight’s local structure and becomes available for further inspection.

## State and integration

`CanvasModeModel` holds the cross-view state needed by Study:

- Whether Study is active or exiting
- The request tokens used to enter and exit it from the tree
- The Branch count (2–6)

Closing the conversation canvas, including quoting or forking an Insight into conversation,
immediately clears its shared Study and Tools flags. The tree owns the Study session and is
removed on close; returning to the tree starts in regular mode while retaining the Branch count.

`InsightTreeView` coordinates Study with the Insight Tree's selection, docked cards, and back
navigation. For a Node Concept it passes `studyNodeID`, the optional initially hovered Insight,
and the slot frame reported by `StudyModeView` to `InsightTreeCanvasView`, which owns the 3D
camera, gestures, and hover. `StudyModeView` itself only reserves the slot (or shows the dot
matrix for an Insight subject).

## Relevant implementation files

| File | Responsibility |
| --- | --- |
| `Angrove-iOS/Features/InsightTree/StudyModeView.swift` | Study slot, Branch card, and the retained dot matrix. |
| `Angrove-iOS/Features/InsightTree/InsightTreeView.swift` | Enters and exits Study, the Branch card, and hover hand-off. |
| `Angrove-iOS/Features/InsightTree/InsightTreeCanvasView.swift` | The Study camera move, 3D positions, fades, gestures, hover, and momentum. |
| `Angrove-iOS/Features/InsightTree/InsightTreeCamera.swift` | The canvas camera projection and focus snapshot. |
| `Angrove-iOS/Features/InsightTree/StudyNodeScene.swift` | `StudyFraming` (camera framing, ring, floor), the ring, and the dot floor. |
| `Angrove-iOS/Features/InsightTree/StudyNodeLayout.swift` | The sphere spread and spherical interpolation. |
| `Angrove-iOS/Features/InsightTree/InsightClusterSpatialLayout.swift` | The tree's ±45° Insight elevations. |
| `Angrove-iOS/DesignSystem/OrbitCamera.swift`, `PerspectivePlaneProjection.swift` | The 3D camera and the tree's overhead projection. |
| `Angrove-iOS/Navigation/NavigationButtons.swift` | `StudyExitButton`. |
| `Angrove-iOS/Features/Conversation/StudyBranchDockControls.swift` | Branch count and confirmation controls in the persistent dock. |
| `Angrove-iOS/Features/InsightTree/StudyBranchScene.swift` | Isolated Branch loading, burst, and recoil presentation. |
| `Angrove-iOS/Features/Canvas/CanvasModeModel.swift` | Shared Study mode and Branch-count state. |

## Planned extensions

- Extend Deconstruct from this visual structure into a token-level semantic decomposition of the selected Insight.
- Reintroduce Sequence as a post-launch exploration tool once its behavior is defined.
- Remove the dot matrix before launch if it is still unused (see above).

## Branch verification — October 6, 2026

- Concrete iPhone 17 arm64 simulator build passed.
- Focused cases passed across Study Branch, canvas persistence, Insight Tree label queue,
  and model action availability. Branch covers all counts, the single-member parent
  edge, recreation, midpoint source connections, failure rollback, and narrow-phone layout.
- The debug preview on iPhone 17e (390 pt) passed light/dark visual checks with six Insights and
  a long Node title. The normal radial layout and chip style are reused, with semantic radii rather than
  independent row spacing. Loading text
  alone shimmers; children and their connectors stay hidden until the complete batch is ready.
  Updated light/dark screenshots are under `output/study-branch/`.
- Manual taps, production-screen integration, live generation quality, and physical haptic feel
  are not verified by this preview. No build was installed on the owner's physical phone.

Branch's result chips use the same `RevealedInsightLabel` and `InsightTreeChipChrome` as the
normal tree: horizontal bubble icon, single-line Figtree title, canvas background, 20 × 16 pt
padding, 12 pt corners, shadow, and a new-Insight discovery dot. The workspace fits the normal tree offsets uniformly rather than changing the chips
or independently stretching their connector lengths. Generated children are embedded with the
configured provider before release; saved children refresh stale vectors on tree preparation.
Study retains each Insight's own semantic radius rather than moving all of them to a mean radius.
The promoted Node Concept retains the source Insight's bookmark ID and saved status.

## Branch connector correction — October 6, 2026

Finished Branch results restore the normal renderer's Insight, connector, Node, and graph-edge
visibility together. Promotion parent edges have stable IDs across semantic rebuilds. The
completed Study focus moves to the new Node and retains its connected parent as visible context.
This fixes a result that remained in the isolated workspace with no visible parent connection,
and generated children that skipped embedding preparation and appeared equally distant.

Completed Branch uses a fitted opening camera that considers the actual parent, child, and Node
footprints and chooses a 3D orientation with less label overlap. The fit scales the connected
result uniformly. Generated child and promotion-parent lines use readable foreground strokes;
other Study graph edges retain their ordinary fade.

The connector correction passed Branch, Study geometry, canvas persistence, semantic membership,
and unavailable-model regression checks. The actual Canvas DEBUG integration preview passed
a 3-child dark check and 6-child light/dark checks on the 390 pt iPhone 17e: parent/child connectors are visible,
all titles and both Node icons are readable, and the displayed distances vary. Physical haptics,
manual rotation, and live generation were not exercised by these fixture checks.
