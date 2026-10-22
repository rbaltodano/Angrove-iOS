# Documentation

Start with the case study for the product story, then the architecture and evaluation documents
for how it is built and measured.

## Start here

| Document | What it covers |
| --- | --- |
| [Case study](Case-Study.md) | Constraints, architecture, key decisions, and measured results |
| [Build and run](Development-Setup.md) | Toolchain, model and grounding assets, and test commands |
| [App architecture](App-Architecture.md) | Composition, state ownership, and persistence |
| [Evaluation](Evaluation.md) | How the AI pipeline is evaluated, with recorded evidence |

## Architecture and subsystems

| Document | What it covers |
| --- | --- |
| [Workspace layout](Workspace-Layout.md) | How `iOS/`, `macOS/`, and `Shared/` divide the two apps |
| [Model runtime](Model-Runtime.md) | The process-scoped LiteRT-LM runtime, task queue, and recovery |
| [Apple-hosted model delivery](Apple-Hosted-Model-Delivery.md) | Shipping the multi-gigabyte model as an Apple-hosted asset pack |
| [Data encryption](Data-Encryption.md) | AES-256-GCM storage, Keychain keys, and recovery |
| [Attachment storage migration](Attachment-Storage-Migration.md) | Moving attachments to immutable, encrypted originals |
| [LiteRT privacy and crypto audit](LiteRT-Privacy-Crypto-Audit.md) | Privacy-manifest and encryption review of the vendored runtime binaries |
| [Complete Library reader](Complete-Library-Reader.md) | Full-text reading of the 37 bundled works |
| [Study tool](Study-Tool.md) | The 3D Study view for a concept and its Insights |
| [Boards](Boards.md) | The Mac canvas for arranging Insights and conversations |
| [Mac port](Mac-Port.md) | The native Mac app: windows, input, and platform adapters |
| [Development workflow](Development-Workflow.md) | Builds, tests, and device conventions |

## Model research

| Document | What it covers |
| --- | --- |
| [Bonsai case study](Bonsai-Case-Study.md) | Whether a ternary 9B model beats Gemma 4 E4B on a phone |
| [Model exploration](Model-Exploration.md) | Earlier runtimes and models, and why they were shelved |
| [Model strategy](Model-Strategy-Plan.md) | Choosing the largest reliable model in about 4 GB |
| [Gemma 4 E4B QAT plan](Gemma4-E4B-QAT-Plan.md) and [progress ledger](Gemma4-E4B-QAT-Progress.md) | The gated migration to the current model |
| [Post-C9 diagnostics](Gemma4-E4B-Post-C9-Diagnostics.md) and [quality triage](Gemma4-E4B-Quality-Triage.md) | Phone failures, separated into causes |
| [EmbeddingGemma 2 assessment](EmbeddingGemma2-Assessment.md) | Whether to replace MiniLM embeddings |
| [Evaluation records](Evaluation/) | Raw results for the native-thinking comparison |

## Release history

- [Post-1.0 changelog](Post-1.0-Changelog.md): every change since the 1.0 App Store submission.
- [Engineering log](Engineering-Log/README.md): dated release checklists, audits, and handoffs,
  kept as written.

## Media

[Screenshots](Screenshots/), [brand assets](Brand/), and the [app icon source](AppIcon-Source/README.md).
