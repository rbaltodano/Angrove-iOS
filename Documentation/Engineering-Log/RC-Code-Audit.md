# RC code audit — October 5, 2026

Scope: the local `Aquinas-iOS-main` working tree on `main`, based on `21ac6a6`, including its existing uncommitted release and Question of the Day changes. This is a code audit, not certification of the uploaded build. Existing changes were preserved; no app code, signing settings, device data, or remote release state was changed by this audit.

## Fix before freezing the RC

### 1. P1 — Backup creation can reject a normal save after a long idle period

Location: `Angrove-iOS/Persistence/InquiryPersistence.swift:208–226`, with failure handling at `:414–416`.

Backups are throttled using their file modification date, but `copyItem` preserves the live file's old modification date. When a conversation has not been saved for more than six hours, the first save creates a backup that still appears more than six hours old. A second write during the same timestamp second attempts the same `conversations-yyyyMMdd-HHmmss.json` destination and fails with Cocoa error 516 (file exists). Because backup creation precedes the live write, the second edit never reaches disk. The asynchronous save wrapper reports this error without `duringWrite: true`, which also closes the encrypted-storage gate.

**Reproduced:** age the live file, perform two saves with the same injected clock second. The second throws and the live snapshot retains the first edit.

**Tighten:** track backup creation time independently of the copied snapshot's age; use collision-resistant filenames; retain correct recovery ordering. Test two same-second saves after idle and ensure a backup failure has deliberate save/recovery behavior.

### 2. P1 — Import can replace recent conversations without preserving their current state

Locations: `Angrove-iOS/Persistence/InquiryPersistence.swift:174–182`, `:215–219`; `Angrove-iOS/Features/Settings/SettingsPages.swift:315–332`.

Import replaces the entire snapshot and uses the same six-hour backup throttle as ordinary saves. It does not guarantee a backup of the version being replaced. The UI presents no replacement confirmation or preview. Selecting a valid export can therefore discard conversations and edits newer than the most recent backup, even though `createsBackup: true` sounds protective.

**Reproduced:** save A, save B (creating a backup of A), then import C within six hours. The live state becomes C; the only backup contains A. B has no preserved snapshot.

**Tighten:** make import an explicit replacement or merge operation. For replacement, preview the incoming data and preserve a verified encrypted copy of the current live snapshot regardless of the routine backup interval, before committing. Check interaction with queued generations and ensure old callbacks cannot mutate imported slots that reuse the same IDs.

### 3. P1 for upgrades/legacy data — Declared property defaults do not migrate older snapshots

Locations: `Angrove-iOS/Models/InquiryModels.swift:99–138`; `Angrove-iOS/Persistence/InquiryPersistence.swift:256–259`, `:261–284`.

`InquiryConversation` uses synthesized `Decodable`. Nonoptional fields including `createdAt`, `isPinned`, and `isStudyTopic` remain required JSON keys despite their stored-property defaults. The comments promising safe decoding of older data are incorrect. `createdAt` was introduced in commit `09dc9184`; `isPinned` in `84509aee`.

**Reproduced:** remove only `createdAt` from an otherwise valid encoded snapshot. Decoding throws `keyNotFound`, and the file store returns nil. Startup's encryption migration checks JSON syntax rather than the conversation schema, so valid legacy JSON can pass startup yet appear to contain no conversations. A later save can replace the live snapshot; existing backups may have the same undecodable schema.

This matters for existing internal users and old imports; a fresh first-time beta install has no legacy snapshot to migrate.

**Tighten:** add explicit backward-compatible decoding for fields introduced after the original schema, ideally with a versioned migration boundary. Distinguish missing storage from unreadable snapshots instead of returning nil for both. Test exports/fixtures from actual prior schema versions, not only current-type round trips.

## Additional concrete findings

### 4. P2 — Document attachments are accepted but their contents are discarded

Locations: `Angrove-iOS/App/ContentView.swift:960–985`; `Angrove-iOS/Features/StudyTopics/StudyTopicsView.swift:336–359`; `Angrove-iOS/Models/UploadedFile.swift:10–25`; `Angrove-iOS/Services/LiteRTAngroveModel.swift:1989–2007`.

Both document pickers accept PDF, audio, and plain text. They read the entire file, then retain only data recognized as an image. Other documents become filename-only attachment cards; the prompt builder processes text and image-bearing uploads, so these documents contribute no content or unsupported-file notice to generation. Images do receive the model's text-only limitation note, but the non-image path does not.

**Tighten:** restrict the picker to supported content or show a clear unsupported-format result. If documents are intended for this beta, extract and bound their text before submission. Treat read failures as errors instead of successful empty attachments. Perform bounded reads off the main actor; the current callbacks read arbitrarily large selected files synchronously, and image attachment data remains embedded in whole conversation snapshots.

Evidence: source trace; file-picker UI was not exercised in this pass.

### 5. P2 — Importing an empty export leaves stale conversations in the shell

Locations: `Angrove-iOS/App/ContentView.swift:708–714`, `:1459–1468`.

A valid empty export replaces the persisted store with zero conversations. The import notification calls `loadShellConversationState`, which returns early when the snapshot is empty, leaving the prior side-menu conversations, active ID, and title intact. The shell can continue presenting conversations that are no longer in the imported store.

**Tighten:** assign the imported snapshot even when empty; explicitly clear the active identity/title and reconcile the mounted conversation session. Test nonempty-to-empty replacement and navigation afterward.

Evidence: source trace; no end-to-end import UI test was run.

### 6. P2 — Start Fresh omits an encrypted diagnostic file that startup validates

Locations: `Angrove-iOS/Persistence/PrivatePreferences.swift:146–149`, `:202–232`; `Angrove-iOS/App/EncryptedStorageGate.swift:82–97`.

Startup validates `Documents/litert-generations.jsonl` if present, including in Release. Start Fresh archives only `ConversationStore`, `InsightTree`, and encrypted preferences. An encrypted generation log left by a prior diagnostic build therefore stays in the startup scan. If its original key is missing or unusable, Start Fresh cannot finish recovery: the next prepare call encounters the same unreadable log after the other data has been archived. The recorder itself is DEBUG-only, so this affects a diagnostic-to-TestFlight upgrade with that file present.

**Tighten:** use one inventory of protected files for validation and recovery, preserving the log in the fresh-start archive too. Test an upgrade containing the diagnostic file with a missing/unusable key, without deleting any existing data.

Evidence: source trace; the owner's diagnostic files and Keychain were not accessed.

## Lower-priority tightening

- Resolve app-owned actor-isolation warnings before moving to Swift 6. The retained Release log shows `GlobalInsightReconciliation.reconcile` is nonisolated while its default embedding function and helpers are MainActor-isolated. Preserve the shared runtime/embedding ownership boundary rather than suppressing diagnostics. The vendor's `OpaquePointer` Sendable warning requires separate wrapper review; a warning alone is not evidence of a demonstrated runtime race.
- Move synchronous import/export and large attachment work behind bounded asynchronous operations. The serial persistence queue avoids running its work on the caller, but its `queue.sync` entry points still block the main actor until encoding, reading, and encryption finish.
- Decompose large shell/conversation/tree views gradually after correctness fixes. Avoid a broad architecture or observation migration during RC stabilization. Focus first on extracting attachment transfer and import/recovery coordination into testable owners.
- Refresh release documentation around a single current status. Existing audit/handoff files contain historical blockers and subsequent resolutions in the same document; verify the exact final archive and service state before copying them into beta instructions.

## Verification and limits

Three isolated defect reproductions passed using the actual production persistence implementation, preference/encryption code, and the original conversation model declarations. The harness compiles these with a fixture Keychain provider and minimal unrelated type stubs on macOS; it does not touch the real Keychain or app container. This establishes the storage/decoding defects, not iOS UI behavior or distribution-runtime performance.

Run from the repository root:

```sh
python3 output/rc-code-audit/reproduce.py
```

Evidence: `output/rc-code-audit/reproductions.txt`. Both the harness and output are delivered with this audit. No new Xcode full-suite run, phone installation, model probe, weight download, upload, or App Store Connect mutation occurred. Existing prior suite/packaging evidence was read and is not represented as fresh verification.

The static pass covered persistence/encryption recovery, app launch/lock/lifecycle, queue ownership and cancellation, hosted-model preparation, attachment intake, Settings import/export, the bundled guide bridge, widget storage, and release build configuration. It is not an exhaustive line-by-line review of all 164 app Swift files or the native SDK. Actual TestFlight asset delivery, physical lock/restore behavior, distribution memory/thermal stability, and accessibility remain hands-on checks documented in the release handoff.
