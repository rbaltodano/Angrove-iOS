# Personal data encryption

**Status (October 23, 2026): implemented on iPhone and Mac.** AES-256-GCM encryption is
integrated into both apps' shared persistence and covered by repository tests. Physical-device
lock and backup-restore checks remain pending validation. This document records the current
storage boundary; dated engineering-log checklists describe their historical state.

Angrove's saved personal data is **Fully Encrypted on your device** using authenticated
AES-256-GCM through Apple CryptoKit. Generation and retrieval run locally; there is no model
server or server-side user store.

## Coverage

Encryption covers conversation questions, responses, drafts, hidden context and attached image
bytes; saved Insights and definitions; Study Topics and their attachments; tree topology, labels,
seeds and embeddings; discovery and reading history; personalized Home cards and usage records;
the user's name and custom instructions; Mac Boards and their saved content; and every rotating
conversation backup. The shared
Question of the Day widget text is encrypted with a separate key. Opt-in debug generation
recordings are also encrypted, and existing recordings migrate at startup.

Library audio bookmarks (work ID/title, paragraph and word position, completion percentage, and
the most recent work ID) are encrypted through `PrivatePreferences` as listening history.

Appearance preferences, bundled books and public grounding data, and model weights are not
personal content and do not receive this additional encryption layer. iOS Data Protection still
applies to app storage.

## Implementation

- `LocalDataCipher` writes a versioned binary envelope containing a fresh random GCM nonce,
  ciphertext and authentication tag. The logical store name is authenticated as additional data.
  Backup snapshots share the conversation context so recovery can restore them to the live path.
- A random 256-bit personal-data key lives in the app's private Keychain access group with
  `kSecAttrAccessibleWhenUnlocked`. It is not synchronized through iCloud Keychain, embedded in
  the binary, written alongside ciphertext or exported by the app.
- iPhone and Mac use separate personal Keychain services and storage roots. Both compile the
  cipher and Keychain implementation from
  [`AngroveCore`](../Packages/AngroveCore/Sources/AngroveCore/LocalDataEncryption.swift), with
  migration and startup validation in
  [`PersonalDataPreparation`](../Shared/Persistence/PersonalDataPreparation.swift).
- The widget has its own random 256-bit key in the existing App Group. Its
  `kSecAttrAccessibleAfterFirstUnlock` policy allows Lock Screen widget refreshes after the first
  device unlock following a restart. The extension cannot access the personal-data key.
- Personal property-list values are encrypted before entering UserDefaults. Ordinary UI
  preferences remain compatible with AppStorage; personal strings use encrypted bindings.
- Personal files use atomic replacement and, on iOS, Complete File Protection in addition to AES-GCM.
  Historical `.json` filenames remain stable but now contain binary ciphertext.
- Before mounting the app interface, startup verifies all existing ciphertext before migrating
  legacy plaintext. Replacement ciphertext is authenticated before the legacy representation is
  overwritten. Backup modification times survive migration. If no existing ciphertext can be
  verified, startup preserves the files and shows recovery controls. Once the key is verified,
  damaged files can be preserved separately so valid conversation backups remain available.
  Runtime integrity failures block further preference writes.

## Backup and recovery

The keys use migratable Keychain accessibility classes. Restore the app's data **together with
its Keychain** using an encrypted device backup or a supported device transfer that preserves
both. Copying only the app container to another phone does not include its decryption keys.
Angrove cannot recover encrypted content if the corresponding key is lost. Missing keys are
never silently replaced when existing ciphertext is read or overwritten.

Device backups may include encrypted app data. Their Keychain protection and transfer behavior
are managed by Apple; this feature does not claim end-to-end encryption for iCloud Backup.
Migration cannot change older device backups or exports made before the upgrade.

## User-directed copies and display

**Export Conversations intentionally produces readable JSON** for portability and independent
recovery. Settings states this explicitly. Exported files, copied text, original photos outside
Angrove, screenshots, notification previews and WidgetKit's system-managed rendered snapshots
are outside the app's encrypted storage boundary. The optional Lock Screen widget displays its
question to anyone who can see that screen.

Personal content must be decrypted in memory while the app processes or displays it. Encryption
protects saved data; it does not conceal text from someone using an unlocked app. Existing App
Lock settings remain available.

Use “Fully Encrypted” alongside “Your saved personal data is encrypted on your device.” Avoid
an unqualified promise that every exported file, screen image or Apple-managed backup is covered.

## Verification

`PersonalDataEncryptionTests` exercises tampering, wrong keys, store swapping, fresh nonces,
legacy property-list and file migration, backup ciphertext, missing-key preservation, startup
preflight and the widget's real App Group Keychain. Existing conversation and tree persistence
suites exercise recovery and stable identifiers through encrypted storage. Physical-device
backup/restore and lock/unlock lifecycle checks remain release-validation requirements.

Apple references: [CryptoKit keys in Keychain](https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain),
[Keychain sharing](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps),
[Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web).

## Attachment references (October 17, 2026)

Local conversation, Topic and Board saves now reference immutable encrypted image files scoped
to each owner. Startup migrates inline images only after writing/verifying the blob and
preserving the encrypted original. Conversation exports stay self-contained readable JSON with
image bytes. Restore complete owner directories with their Keychain, rather than metadata alone.
See [Attachment storage migration](Attachment-Storage-Migration.md) for schema, recovery copies,
cleanup/deletion rules and verification.
