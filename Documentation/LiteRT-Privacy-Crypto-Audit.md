# LiteRT SDK privacy and crypto audit

October 5, 2026. Static review of the native SDK currently vendored by this working tree.
The inventory is complete for the checks below. The integration-reviewed SDK API manifest is now
bundled and verified in an App Store distribution export; the export-encryption answer remains
unresolved.
No model weights were downloaded, no model experiment was rerun, and the SDK was not upgraded.

## Artifact and method

The device binary is `Vendor/LiteRTLM/Binaries/CLiteRTLM.xcframework/ios-arm64/CLiteRTLM.framework/CLiteRTLM`.
Its SHA-256 is `32c2576cddd50542934289b850ce2061115f90f63de2857ff6f7c5f8f2425607`, matching the
recorded September 26 migration. The simulator hash recorded there is
`12aba062062d7dc3d027ded18452c58f90445a5d7b18e4114f17af34d0cb153a`.
The local Package.swift references v0.14.0. Framework version 1.0 alone does not identify the SDK.

Reviewed the official [v0.14.0 source](https://github.com/google-ai-edge/LiteRT-LM/tree/f73637c57f0940b53da184e0d5adfc52a4e55eef)
at commit `f73637c57f0940b53da184e0d5adfc52a4e55eef`, global symbols/imports, and direct native
callers identified from disassembly. The published source and the supplied binary are separate
artifacts; a matching release label is not a reproducible-build proof. This is a static audit,
not a network capture or an exhaustive reachability analysis of every prebuilt component.

Repeat the binary inventory on macOS with the installed Xcode tools:

```sh
python3 scripts/audit_litert_sdk.py \
  Vendor/LiteRTLM/Binaries/CLiteRTLM.xcframework/ios-arm64/CLiteRTLM.framework/CLiteRTLM \
  --output build/sdk-audit/device-inventory.json
```

The generated JSON records hash, imports, crypto-related symbols, API callers and minizip entry
instructions. It lives in gitignored `build/`; the script and this interpretation are portable.
Re-audit whenever the binary hash changes, including before freezing the signed release candidate.

## Required-reason APIs

| Evidence | What the review establishes | Declaration follow-up |
| --- | --- | --- |
| `stat`, `fstat`, `fstatat`, `lstat` | Direct callers include LiteRT `ScopedFile::GetSize`, `GetFileCacheIdentifier`, model mmap/weight loaders, TensorFlow allocation/cache code, MediaPipe file utilities and Rust file metadata helpers. Public `runtime/util/file_util.cc` uses `fstat` to size a model mapping. | Declared `C617.1` for this integration: the model is in app/App Group storage and the runtime supplies `Library/Caches/LiteRTLM` as its native cache directory. |
| `mach_absolute_time` | Four direct callers are miniaudio's null-device read/write/thread and timer initialization functions. These are native audio elapsed-time operations, not the app's DEBUG timing code. The public release pins miniaudio 0.11.22. | Declared `35F9.1` for the linked elapsed-time/timer implementation. Angrove passes no audio backend, so the audio executor is not initialized by the production configuration. |
| Preferences, disk-space and keyboard categories | No corresponding imports identified by the reviewed global-symbol inventory. | This is limited negative evidence; indirect/dynamic calls are outside the scan. |

Added `PrivacyInfo.xcprivacy` to both vendored iOS framework slices. These are **Angrove's
integration-reviewed required-reason declarations**, not an upstream Google privacy attestation.
Only `NSPrivacyAccessedAPITypes` is included; unverified SDK collection/tracking declarations were
not invented. The app's own privacy manifest remains separate.

Follow-up source review establishes the cache directory from `LiteRTModelStore.cacheDirectory()`
and the explicit `cacheDir` passed by `LiteRTAngroveRuntime` into the Swift/C bridge. The audio
backend defaults to `nil` in the reviewed Swift config, and the production runtime leaves it unset.
The [pinned miniaudio source](https://github.com/mackron/miniaudio/blob/0.11.22/miniaudio.h)
initializes a timer from `mach_absolute_time` and calculates elapsed differences; the null backend
uses it for simulated audio pacing. This supports the elapsed-time reason even though Angrove
currently does not initialize its audio executor. Neither reviewed use transmits metadata or
boot-time values. Any future runtime, file-location, audio or telemetry change needs re-review.

The exported IPA contains the framework manifest. App/widget/downloader distribution signatures
and provisioning profiles were verified; all have the shared App Group and `get-task-allow=false`.
The required-reason selections were checked against Apple's
[approved definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
Native input binaries were not changed or upgraded; Xcode re-signs the embedded framework.

## Networking and collection

The direct callers of `connect`, `socket`, `socketpair` and `gethostname` are Rust standard-library
TCP/UDP/Unix-socket and hostname helpers. Their presence is **not evidence of telemetry**. No
telemetry uploader was identified in the reviewed public runtime source; local metrics/profiling
are not themselves collection. Conversely, unused-looking linked helpers do not prove the whole
opaque native SDK cannot transmit data. Runtime network observation and upstream provenance are
still needed to close that question. Angrove's inference path remains on-device; Apple-hosted
model delivery is a separate download operation.

## Crypto inventory and export declaration

- App-owned storage uses Apple's CryptoKit AES-GCM and Keychain. Model integrity uses SHA-256.
- Native `_CCRandomGenerateBytes` calls occur in Rust random/hash initialization and tokenizers'
  random-generator dependencies. The binary also includes **`rand_chacha` / `ChaCha12Core`** code.
  Thus “all linked cryptography is provided solely by Apple's OS” has not been established.
  The observed uses concern random-number generation; they do not establish message encryption.
  The [dependency’s own API documentation](https://docs.rs/rand_chacha/0.3.1/rand_chacha/) confirms
  the crate exposes ChaCha random-generator cores and RNGs. This narrows the submission question
  to the bundled PRNG rather than a demonstrated native conversation-encryption feature.
- The named minizip `_unzOpenCurrentFilePassword` entry does not prove usable ZIP decryption.
  In this device binary, it passes the password as `x4` to `_unzOpenCurrentFile3`, whose entry
  rejects a non-null `x4` with parameter error `-102`. This is consistent with a `NOCRYPT` build.
  Angrove's reviewed archive-reading source calls `unzOpenCurrentFile2` without a password.
- No AES/SSL cipher entry was identified in the reviewed global-symbol scan. This is not an
  exhaustive cryptographic proof: stripped/internal implementations may not have obvious names.

**`ITSAppUsesNonExemptEncryption` remains unset.** Resolve the classification of the bundled
random-generator code, confirm the actual distribution artifact and launch territories, then
record the applicable account-side answer and plist value. Do not mistake a crypto symbol for
an export determination, or equate absence of a cipher import with an exemption. Apple's
[encryption documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)
is the reference for the submission answer.

## Check-off criteria

- [x] Pin binary hash and source release; provide repeatable static inventory.
- [x] Trace native file/timing/network/RNG imports to direct callers.
- [x] Distinguish PRNG code and disabled ZIP password handling from app storage encryption.
- [x] Confirm the integration’s native cache/audio configuration; add the API-reason manifest to
  both framework slices and verify it in the distribution IPA.
- [ ] Complete upstream collection/provenance confirmation and physical runtime network observation.
- [ ] Resolve export classification and account-side declarations; set the justified plist value.
- [ ] Observe networking on the physical release build during offline generation.
