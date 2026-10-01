<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Documentation/Brand/angrove-app-icon-dark.png">
    <img src="Documentation/Brand/angrove-app-icon-light.png" alt="Angrove app icon" width="128">
  </picture>
</p>
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Documentation/Brand/angrove-logo-light-text.png">
    <img src="Documentation/Brand/angrove-logo-dark-text.png" alt="Angrove" width="360">
  </picture>
</p>

<p align="center">
  <img src="Documentation/Screenshots/home-light.jpg" alt="Angrove Home in light mode" width="19%">
  <img src="Documentation/Screenshots/conv-light.jpg" alt="Angrove conversation with annotated Insights in light mode" width="19%">
  <img src="Documentation/Screenshots/library-light.jpg" alt="Angrove Library of primary sources in light mode" width="19%">
  <img src="Documentation/Screenshots/menu-light.jpg" alt="Angrove side menu in light mode" width="19%">
  <img src="Documentation/Screenshots/insight-tree-church-doctrine-authority.jpg" alt="Angrove Insight Tree" width="19%">
</p>
<p align="center">
  <img src="Documentation/Screenshots/home-dark.jpg" alt="Angrove Home in dark mode" width="19%">
  <img src="Documentation/Screenshots/conv-dark.jpg" alt="Angrove conversation with annotated Insights in dark mode" width="19%">
  <img src="Documentation/Screenshots/library-dark.jpg" alt="Angrove Library of primary sources in dark mode" width="19%">
  <img src="Documentation/Screenshots/menu-dark.jpg" alt="Angrove side menu in dark mode" width="19%">
  <a href="Documentation/Screenshots/study-3d-demo.mp4"><img src="Documentation/Screenshots/study-3d.jpg" alt="Angrove Study mode showing a Node Concept and its Insights in 3D" width="19%"></a>
</p>

The top row is light mode and the bottom row is dark mode. From left to right: the Home dashboard,
a source-oriented conversation with contextual Insights, the Library of primary sources, the side
menu, and the Insight Tree and Study mode (which shows a Node Concept and its Insights in 3D;
select it for a short [demo video](Documentation/Screenshots/study-3d-demo.mp4)).

## A note on privacy and current development

Angrove is a local-first project, not a hosted chat service. The iOS app is designed to use an
on-device language model and local source retrieval. It makes no network requests for model or
Insight Tree work.

This repository is an active development project. The local model and grounding assets are large
and intentionally excluded from source control, so a full on-device experience requires the
corresponding development assets.

## For contributors

The app is one part of a three-repository project. The backend repository holds offline tooling
for the grounding corpus, model conversion, and evaluation; the app does not call it at runtime.
The Foundations repository holds the shared product and architecture contracts.

| Repository | Role |
| --- | --- |
| [Angrove Backend](https://github.com/rbaltodano/Aquinas_Backend) | Corpus tooling, model conversion, and evaluation. Its FastAPI service is no longer used by the app. |
| [Angrove Foundations](https://github.com/rbaltodano/Aquinas-Foundations) | Shared product, design, model-integration, and Insight Tree documentation. |

Before contributing, read [`AGENTS.md`](AGENTS.md). It routes implementation work to the focused
architecture, runtime, workflow, and cross-repository documents without making the README carry
internal development detail.

## Repository guide

| Path | What you'll find |
| --- | --- |
| `Angrove-iOS/App` | App entry point and overall navigation shell |
| `Angrove-iOS/Features` | Conversation, Home, Insight Tree, Library, and settings experiences |
| `Angrove-iOS/DesignSystem` | Typography, colors, and shared interface elements |
| `Angrove-iOS/Services` | Model runtime and local grounding |
| `Angrove-iOS/Persistence` | Local conversation and Insight state |
| `Angrove-iOSTests` | Focused behavior and regression coverage |

## Open the project

Open `Angrove-iOS.xcodeproj` in Xcode. The project targets iOS 26.4 and uses a concrete arm64
simulator destination when building from the command line:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The README is intentionally public-facing. Detailed architecture, runtime constraints, and agent
guidance are routed from [`AGENTS.md`](AGENTS.md).

## Project status

Angrove is in active development and is not yet a public consumer release. The
most useful parts of the project to explore today are the conversation flow,
source-grounded study experience, semantic Insight Tree, and on-device model
integration. The semantic layer is central to the product: it helps the app
show how ideas relate, cluster, and develop over time.

The repository does not include the full local model bundle. To run the complete
on-device experience, you will need the corresponding development model assets
and a recent Xcode installation.

## Related repositories

- [Angrove Foundations](https://github.com/rbaltodano/Aquinas-Foundations) — product, design, and architecture contracts.
- [Angrove Backend](https://github.com/rbaltodano/Aquinas_Backend) — offline corpus, conversion, and evaluation tooling.
