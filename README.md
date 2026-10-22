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

# Angrove

[![CI](https://github.com/rbaltodano/Angrove-iOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/rbaltodano/Angrove-iOS/actions/workflows/ci.yml)

**An AI of your own. A private place for serious questions.**

Angrove is a private study workspace for philosophy, history, and theology. Ask a question,
check the primary sources behind an answer, and save useful ideas in a semantic map.
Generation and retrieval run on-device, without a model server or an account.

Built by **Ryan Baltodano** across product design and engineering, with a SwiftUI iPhone app
and a native Mac app in progress. **The iPhone app is in public beta on
[TestFlight](https://testflight.apple.com/join/qHDFeAUa); the App Store release is next.**

[Try the iPhone beta](https://testflight.apple.com/join/qHDFeAUa) ·
[Watch the 1:49 demo](https://angrove.app/case-study.html#demo-conversation) ·
[Engineering overview](#building-the-product-around-the-model) ·
[Technical case study](Documentation/Case-Study.md) ·
[Build and run](Documentation/Development-Setup.md)

[Website](https://angrove.app/) · [User Guide](https://angrove.app/guide.html) ·
[FAQ](https://angrove.app/faq.html)

## Watch Angrove in use

Three iPhone app recordings captured October 8, 2026. Select a preview to watch the clip
with playback controls and audio on the website.

| Ask a question and explore its tree · 1:49 | Explore saved ideas · 0:24 | Listen to an answer · 0:50 |
| --- | --- | --- |
| [![A Peloponnesian War conversation](https://angrove.app/assets/app/demos/user-question-and-insight-tree.jpg)](https://angrove.app/case-study.html#demo-conversation) | [![A saved polis Insight in the global tree](https://angrove.app/assets/app/demos/global-insight-tree.jpg)](https://angrove.app/case-study.html#demo-global-tree) | [![An answer playing in the Reading controls](https://angrove.app/assets/app/demos/on-device-reader.jpg)](https://angrove.app/case-study.html#demo-reader) |

[All three demos](https://angrove.app/case-study.html#demos) ·
[Conversation guide](https://angrove.app/guide.html#conversation) ·
[Insight Tree guide](https://angrove.app/guide.html#tree)

## A look inside

October 5, 2026 app captures: Home, a Peloponnesian War inquiry, a Homoousios conversation,
and the Ancient Greek Politics map. Select an image to view it at full size.

<p align="center">
  <a href="Documentation/Screenshots/case-study-2026-10-05/home.jpg"><img src="Documentation/Screenshots/case-study-2026-10-05/home.jpg" alt="Angrove Home with activity and a Question of the Day" width="23%"></a>
  <a href="Documentation/Screenshots/case-study-2026-10-05/conversation-peloponnesian-war.jpg"><img src="Documentation/Screenshots/case-study-2026-10-05/conversation-peloponnesian-war.jpg" alt="Peloponnesian War inquiry with underlined concepts" width="23%"></a>
  <a href="Documentation/Screenshots/case-study-2026-10-05/conversation-homoousios.jpg"><img src="Documentation/Screenshots/case-study-2026-10-05/conversation-homoousios.jpg" alt="Homoousios conversation with a contextual concept" width="23%"></a>
  <a href="Documentation/Screenshots/case-study-2026-10-05/insight-map.jpg"><img src="Documentation/Screenshots/case-study-2026-10-05/insight-map.jpg" alt="Ancient Greek Politics map and saved Insight card" width="23%"></a>
</p>

[Full screenshot set and context](Documentation/Screenshots/case-study-2026-10-05/README.md)
include expanded source details and two mobile browser captures of the website's technical guide.

<details>
<summary>More screenshots: Library, dark appearance, and Study mode</summary>

Earlier captures show the Library, menu, dark appearance, and Study mode:

<p align="center">
  <img src="Documentation/Screenshots/library-light.jpg" alt="Angrove Library of primary sources in light mode" width="19%">
  <img src="Documentation/Screenshots/menu-light.jpg" alt="Angrove side menu in light mode" width="19%">
  <img src="Documentation/Screenshots/home-dark.jpg" alt="Earlier Angrove Home in dark mode" width="19%">
  <img src="Documentation/Screenshots/conv-dark.jpg" alt="Earlier Angrove conversation in dark mode" width="19%">
  <a href="Documentation/Screenshots/study-3d-demo.mp4"><img src="Documentation/Screenshots/study-3d.jpg" alt="Angrove Study mode with a Node Concept and its Insights in 3D" width="19%"></a>
</p>

Select the Study image for the [short demo video](Documentation/Screenshots/study-3d-demo.mp4).

</details>

## Building the product around the model

One process-scoped LiteRT-LM runtime serves conversation, definitions, and tree updates through
a shared task queue. On-device retrieval supplies source passages, and encrypted persistence
keeps conversations and saved ideas local. Common logic lives in `Shared/`; each platform owns
its navigation, input, and window behavior.

The [technical case study](Documentation/Case-Study.md) explains the constraints and tradeoffs.
These are useful starting points in the implementation:

| Engineering area | Implementation and evidence |
| --- | --- |
| Runtime ownership and cancellation | [Shared task queue](Shared/Features/Conversation/ModelTaskQueue.swift), [iPhone runtime](iOS/Services/AngroveApplicationRuntime.swift), [Mac runtime](macOS/Platform/MacApplicationRuntime.swift) |
| Source-grounded answers | [Local retrieval](Shared/Services/MiniLMGroundingProvider.swift), [retrieval regressions](Angrove-iOSTests/MiniLMGroundingRetrievalTests.swift) |
| Durable conversations and saved ideas | [Shared persistence](Shared/Persistence), [migration regressions](Angrove-iOSTests/EncryptedAttachmentMigrationTests.swift), [architecture](Documentation/App-Architecture.md) |
| Mac port in progress | [Mac workspace](macOS/Features/MacWorkspaceView.swift), [navigation history tests](Angrove-macOSTests/MacPageHistoryTests.swift) |
| Measured model tradeoffs | [Evaluation methodology and artifacts](Documentation/Evaluation.md) |

**One measured decision:** native thinking remained off by default after two development sets
returned **74/80 objective passes in either arm**, while simulator median answer time roughly
doubled. These are historical pattern-scored comparisons, not an independent accuracy claim or
phone latency benchmark. See the report for the exact build and limitations.

## From a question to a map of your thinking

- **Conversation:** talk a question through, ask for an example or an objection, and follow up
  for as long as you need.
- **Insights:** tap an underlined term for a definition in the context of your discussion. Save
  the definitions worth keeping; saved definitions become Insights.
- **Insight Tree:** explore how your ideas connect. Angrove adds broader subjects called Node
  Concepts as a conversation develops; Insights are only added when you choose to save them.
  Semantic relatedness shapes the map, so distance reflects meaning rather than truth or importance.
- **Study and Midpoint:** explore a subject and its Insights in 3D, or select and weight ideas
  to propose a concept that connects them.
- **Library:** trace an answer to the passages it draws on and open the source to read it in
  context. The current bundled Library contains **37 works and 51,836 passages**, including
  Scripture, the Church Fathers, Thomas Aquinas, councils, catechisms, classical philosophy,
  and history. Retrieval runs on-device.

Study Topics bring related conversations and their Insights together. Home offers a Question of
the Day and ideas worth revisiting, while Model Tasks lets you stop, remove, or reorder work
waiting for the on-device model.

## A note on privacy and current development

Generation, source retrieval, and Insight Tree work run on-device. Conversations and saved
Insights stay in the app's local storage; answering questions and building the tree make no
network requests. Once the model is installed, Angrove works offline. No account is required.

**Encrypted local storage.** Angrove encrypts saved personal data on the device with
AES-256-GCM, including conversations, attachments, Insights, Study Topics, personal settings, and
local backups. Keys are protected by Apple Keychain. User-created conversation exports are
readable JSON. The encryption is integrated into the app's storage and covered by tests;
physical-device lock and backup-restore validation is still pending. See [encryption coverage and recovery](Documentation/Data-Encryption.md).

The current model is **Gemma 4 E4B, instruction-tuned, from the LiteRT Community package**,
running through Google's LiteRT-LM runtime. It is not an Angrove fine-tune. Angrove’s default
Scholarly personality uses the learned-friend prompt; its grounding comes from local retrieval.
A fine-tuned voice model is planned for a later release. On-device MiniLM embeddings support
source retrieval and the semantic relationships in the Insight Tree.

Answers can make mistakes. The Library makes it easy to check important claims against the
author's own words and context.

Angrove is in public beta on [TestFlight](https://testflight.apple.com/join/qHDFeAUa), and the App Store release is next. It is being built to stay
free, with no subscription or paywalled features. Development uses iPhone 17 and Apple silicon
Macs. The Mac front end is still in progress and currently requires macOS 27;
final supported-device requirements and release availability will be shared before launch.

The local model and grounding assets are large and intentionally excluded from source control.
A clean checkout can build the interface, but full inference requires the development artifacts.
[Setup instructions](Documentation/Development-Setup.md) explain the expected paths, model hash,
degraded behavior and release-delivery gap.

## Repository guide

| Path | What you'll find |
| --- | --- |
| `iOS/` | iPhone app shell, navigation, platform adapters, and iPhone-only features |
| `macOS/` | Native Mac windows, keyboard/mouse interaction, and platform adapters |
| `Shared/Features/` | Conversation, model tasks, Insight Tree, and common presentation |
| `Shared/DesignSystem/` | Semantic typography, colors, motion, and reusable interface elements |
| `Shared/Services/` | Model integration, local retrieval, and shared services |
| `Shared/Persistence/` | Encrypted local storage and durable conversation/Insight state |
| `Angrove-iOSTests/`, `Angrove-macOSTests/` | Behavior and regression coverage for both apps |
| `Documentation/` | Case study, architecture, evaluation evidence, and build instructions |

## Build and verify

Use **Xcode 27 on Apple silicon**. Follow the [setup guide](Documentation/Development-Setup.md),
then open `Angrove-iOS.xcodeproj`. Select **Angrove-iOS** for iPhone or **Angrove-macOS** for Mac.
The deployment targets are iOS 26.4 and macOS 27. A source checkout can build the UI; full
inference requires the separately supplied model and grounding assets.

Use an installed concrete arm64 simulator for iPhone:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build
```

Build the native Mac target without a developer signing identity:

```sh
xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

The [setup guide](Documentation/Development-Setup.md#verify-behavior) includes test commands for
both platforms. CI runs the asset-independent checks; tests requiring private development
artifacts report explicit skips.

For model-evaluation methodology and recorded evidence, see [Evaluation](Documentation/Evaluation.md).

## For contributors

The app is one part of a three-repository project. The backend repository holds offline tooling
for the grounding corpus, model conversion, and evaluation; the app does not call it at runtime.
The Foundations repository holds the shared product and architecture contracts.

| Repository | Role |
| --- | --- |
| [Angrove Backend](https://github.com/rbaltodano/Angrove-Backend) | Corpus tooling, model conversion, and evaluation. Its FastAPI service is no longer used by the app. |
| [Angrove Foundations](https://github.com/rbaltodano/Angrove-Foundations) | Shared product, design, model-integration, and Insight Tree documentation. |

Before contributing, read [`AGENTS.md`](AGENTS.md). It routes implementation work to the focused
architecture, runtime, workflow, and cross-repository documents without making the README carry
internal development detail.

## Naming

Angrove was originally named Aquinas. Bundle identifiers, stored-data keys, and some local paths
keep that name so existing installs and tooling continue to work; references to Thomas Aquinas
are to the theologian.

## License

Copyright © 2026 Ryan Baltodano (Sine Viridian). All rights reserved. The source is published
for reference and review; see [`LICENSE`](LICENSE). Third-party components keep their own
licenses.
