# Encrypted attachment storage — October 17, 2026

Finding 15 is implemented in Shared. New local saves reference immutable, encrypted originals
instead of repeating their base64 bytes throughout conversation, Topic and Board JSON. Existing
inline data remains readable. No owner data was migrated by the development tools; conversion
runs behind the updated app's encrypted startup gate on its next launch. The owner has left
normal Mac installation pending, so the installed app has not been replaced.

## Storage contract

An `UploadedFile` retains its UUID, name, rotation and exact original bytes. Local persistence
supplies an explicit owning attachment store through Codable userInfo. It writes an `attachment`
object containing `version: 1`, a 64-character lowercase SHA-256 digest and `byteCount` instead
of `imageData`. References cannot contain paths. Unsupported versions, invalid identities, missing
files, wrong keys, tampering and mismatched digests/counts fail explicitly.

Each owner has an `Attachments/` directory:

| Owner | Directory relative to Application Support's platform-specific Aquinas root |
| --- | --- |
| Conversations and all rotating backups | `ConversationStore/Attachments/` |
| Boards, their nested conversation windows, and Board trash | `Worktree/Attachments/` |
| Study Topics (preference key stays `aquinas.study-topics.v1`) | `StudyTopics/Attachments/` |

The platform-specific root is `Aquinas` on iOS and `Angrove-macOS/Aquinas` on Mac. Identical bytes
within an owner share a digest-named `.attachment` file. Separate owners deliberately keep separate
copies: deleting all conversations can erase that complete directory without damaging a Topic or
Board that uses the same photo.

Blobs use the existing personal AES-256-GCM cipher and Keychain key, with the authenticated
context `attachment-v1:<digest>`. iOS also applies Complete File Protection. Each new blob is
atomically written, synchronized, reopened, authenticated, and checked against its byte count and
digest before its reference can enter a parent save. The image digest is computed once per
immutable in-memory payload. Unchanged existing blobs are verified once and subsequently checked
by file metadata. Normal decoding still authenticates the actual image bytes before display/use.

A per-owner transaction lock covers encoding, blob publication, parent commit and cleanup.
Conversation and generic personal-store serial workers remain the owners of their writes.
Schema validation before replacing a Board file checks its references without reloading every
unchanged image; validation-only decoded values are discarded inside the validator.

## Migration and interruption

Startup first validates the existing protected data/key boundary. It then converts live
conversation files, rotating conversation backups, Board files, and the Topic preference before
preloading feature stores. A schema-limited JSON transform preserves unrelated/unknown fields.
Legacy conversation or Board preferences that migrate on first read use the same reference codec.

For each file:

1. Open the original encrypted JSON (legacy plaintext is protected using the existing migration).
2. Write and verify every needed immutable blob.
3. Preserve the encrypted original under the source's `AttachmentMigrationOriginals/` directory.
4. Atomically replace the parent with encrypted reference JSON.

Topic JSON is preserved as encrypted
`StudyTopics/AttachmentMigrationOriginals/study-topics-v1.json` before replacing its encrypted
preference value. A file-backed legacy preference is preserved under that owner's migration
originals before removing its old key.

An interruption before step 4 leaves the original parent intact; a later retry reuses verified
blobs. An interruption between files leaves independently valid migrated and inline files.
Retries are idempotent. Missing/unreadable referenced images block storage; they do not become
name-only attachments and an empty-looking store must not overwrite the saved parent.
Per-file autorelease pools bound temporary Foundation allocations during migration.

Migration needs temporary free space. Original copies are retained, so the first upgrade can
increase disk usage; subsequent saves and rotating backups stop repeating inline image bytes.
A failed write preserves the old parent and is retried through the existing startup/save paths.
Migration originals are deliberately retained until the owning data is erased; they do not
expire automatically as part of this first migration.

## Backups, deletion and conservative cleanup

A rotating JSON backup now references the same owner blobs. Keep the complete owning directory
and its Keychain when backing up/restoring encrypted local data; copying only a metadata JSON
file is insufficient. Existing self-contained conversation export remains the portable recovery
format. A migration original is an encrypted developer recovery copy, not a Settings import file.
Do not open the new local store with an older app version that does not understand references;
use a current self-contained export or a coordinated restore of pre-migration data for downgrade.

After a successful parent commit, cleanup inventories every JSON file in that owner, including
all backups and migration originals. Topics also provide their current preference JSON. Only
unreferenced blob files are removed. If any inventory is unreadable, has an invalid/unsupported
reference, or cannot be traversed safely, the entire sweep is cancelled. A sweep never creates a
key or interprets failure as an empty reference set. Unchanged inventory reference sets are
cached by file metadata so large retained inline originals are not decrypted on every edit.
Optional cleanup errors do not close otherwise usable storage.

Deleting all conversations removes their metadata, backups, migration originals and blobs together.
Other owners survive. Deleting all app data removes all these owner directories. Start Fresh
archives all owner directories, including `StudyTopics`, before reopening empty stores. Images
still referenced by Board trash or an encrypted recovery original are intentionally retained.

## Portable import/export

Ordinary Codable/export encoding continues to emit `imageData` inline and no local reference.
Conversation exports therefore remain self-contained readable JSON, including exact image bytes,
and remain compatible with older inline importers. Import accepts inline data and writes the
fresh destination's own encrypted blobs. An external reference-only file is rejected rather than
resolving references against the person's private local library.

## Verification

`EncryptedAttachmentMigrationTests` uses temporary directories and injected in-memory keys;
it does not reset, migrate or inspect the owner's personal stores. Coverage includes:

- compact local metadata, exact UUID/name/rotation/byte round trips, deduplication, and no blob
  rewrite across repeated small edits;
- portable export and import into a fresh owner, rejecting reference-only imports;
- interruption before parent commit, exact recovery-copy preservation and idempotent retry;
- failed blob writes, wrong keys, swapped/missing blobs, malformed/unsupported references;
- migration of live files, backups, Topics and Boards while preserving unknown fields;
- backup-only references, owner-isolated deletion, unreadable inventory preventing cleanup;
- real Board photo, trash and nested conversation models;
- repeated schema validation avoiding additional image-key calls.

Fixture checks show two identical 1 MiB attachments produce one encrypted blob and less than
4 KiB of conversation metadata. This establishes the storage behavior, not a measured device
latency, memory or energy improvement. Physical-device interrupted-upgrade, low-space,
lock/unlock and encrypted backup/restore checks remain release validation.

Final focused verification on October 17: **48 tests in 6 suites passed on iPhone 17 / iOS 27.0
Simulator**, and **33 tests in 3 suites passed on arm64 Mac**. Both test commands compiled their
full app and test targets. The initial Board-controller fixture was replaced with pure stored
models to keep this migration suite isolated from personal app state. Documentation validation
checked 124 local links in 45 documents; `git diff --check` passed. Logs are
`/tmp/angrove-attachments-ios-verified.log` and `/tmp/angrove-attachments-mac-verified.log`, with
xcresult paths printed at their ends. The separate signed Release build succeeded and `codesign --verify --deep --strict` passed,
with sandbox/App Group entitlements present. Build output is recorded in
`/tmp/angrove-attachments-mac-release.log`; it was not installed or launched. Installation
remains pending by owner request.

## Normal Mac installation completed — October 17, 2026

The owner confirmed all existing data is test data and explicitly authorized installation without
migration or launch. The obsolete pre-sandbox Application Support folder was moved intact to
`build/mac-data-backups/20261017-152126-retired-test-data/Legacy Application Support`, with its
legacy preferences copied alongside it. The protected sandbox container was not touched.
`ANGROVE_MAC_LAUNCH_AFTER_INSTALL=0 bash Tools/install-local-mac.sh` succeeded and installed the
current signed Release at `/Applications/Angrove.app`. The old app remains recoverable under
`build/mac-installed-backups/`. Installed signature verification passed, its executable matches
the freshly built executable, and no Angrove app process is running. No app data migration ran.
This resolves the earlier installation-pending status. Output is recorded in
`/tmp/angrove-final-install-no-launch.log`.
