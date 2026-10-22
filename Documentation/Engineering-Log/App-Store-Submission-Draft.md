# App Store submission working draft

October 5, 2026. Draft only: approve scope and validate the final TestFlight candidate before
using this in App Store Connect. Delivery and encryption wording describes the intended release
and must be checked against that exact build. No account-side declarations have been submitted.

## Proposed product copy

**Name:** Angrove

**Subtitle:** A private place to think

**Description:**

Stay with the questions that matter. Angrove brings AI conversation, primary sources, and a
lasting map of your ideas into one private study workspace.

Ask a question about philosophy, theology, or history. Inspect the source passages behind an
answer, explore a term in context, and choose which definitions to save as Insights. Revisit
connections in the Insight Tree and explore your saved ideas in Study.

Generation and passage retrieval run on your device. The initial installation includes a large
model asset download; after installation and verification, supported features work offline.
Saved personal content is encrypted locally with keys managed by iOS. Conversation files you
choose to export are readable JSON.

AI answers can be mistaken, and a fluent response is not proof that a citation is correct. Use
the Library and source reader to check the underlying passages. Angrove is a tool for study and
reflection; it does not replace professional advice or spiritual guidance.

**Proposed category:** Education (owner decision).

**Keywords draft:** philosophy,theology,study,ideas,insights,library,reflection,offline

Do not add unsupported device names, performance promises, launch dates or fine-tuning claims.
Use screenshots from the candidate app, not website examples. App preview video is optional;
the portfolio recording is tracked in [Demo-Outline.md](Demo-Outline.md).

## Reviewer notes template

Replace every bracketed item before submission.

- Candidate: version [version], build [build], asset pack [ID/version], model hash [hash].
- Supported devices / minimum OS: [validated device matrix and OS].
- No login is required. Model generation and retrieval run locally; no remote inference account
  or API key is needed.
- Installation downloads an essential model asset pack through Apple hosting. Allow approximately
  [measured download/storage requirements]. If delivery is interrupted, [actual recovery steps].
- Open Conversation, ask [tested example], wait for the local response, then open a displayed
  source to inspect its Library passage. Tap an underlined term, inspect its definition and save
  it as an Insight. Open Insight Tree and Study to revisit saved concepts.
- Verify offline operation after the initial asset download. First model initialization can
  take [measured range] on [device]. Do not confuse install/download time with answer latency.
- Personal content is saved locally. Settings offers [verified export/import/deletion behavior].
  Exported conversation JSON is intentionally readable. App Lock is optional.
- Contact for review questions: [owner name, monitored email and phone].

## App Privacy and export-compliance worksheet

The app-owned source currently shows local generation/retrieval and local personal-data storage;
it does not contain an analytics or remote inference client. Website visits and Apple-managed
asset downloads are distinct from uploading conversations. The packaged native SDK contains
network-related symbols, which alone neither prove telemetry nor establish its absence.

- [ ] Complete the native SDK/network audit and aggregate archive privacy report.
- [ ] Answer App Privacy based on actual app/SDK behavior; do not copy a no-data-collected answer
  from this draft without that audit.
- [ ] Verify tracking declaration, required-reason manifests and SDK manifests against the archive.
- [ ] Review all encryption, including linked native libraries, before setting
  `ITSAppUsesNonExemptEncryption` and completing the account-side questionnaire.
- [ ] Verify license notices and distribution rights for the model and Library in launch countries.
- [ ] Fill age-rating answers from the actual features and content; do not invent a rating here.

## Privacy policy text to reconcile with the published policy

Angrove processes conversations, saved Insights and Library searches on the device. The intended
release stores personal app content encrypted using AES-256-GCM and iOS Keychain-managed keys.
The widget uses a separate key for its shared content. Deliberate exports are readable files and
are controlled by the person exporting them. Device backups and Keychain availability affect
recovery; document the tested restore behavior before release.

Support reports are optional and sent only when the person taps Send Report. A report contains the
text they write, their app and iOS version numbers and, if they provide one, a reply email address.
A thumbs-down on a response can also include that response and the question before it, but only if
the person switches on the option after seeing the exact text; it is off by default. Reports go
through Formspree to the support inbox, and Formspree also receives the sender's IP address. Add
retention rules before publishing the final policy.

Apple provides model-asset delivery during installation and recovery. Network access is needed
to obtain those assets. This does not send your conversation to a remote model. Add any confirmed
SDK collection, support-contact handling, policy contact details and retention rules before
publishing the final policy. Do not state that every byte in the app is encrypted: public model
weights, Library resources, displayed text and screenshots fall outside personal-storage coverage.

## Owner fields still needed

Launch countries; price; supported phones and iPad decision; final support contact; Developer
Program/App Store Connect access and agreements; rights confirmation; release timing. See the
[release checklist](App-Store-Release-Plan.md) for testing and submission gates.

## Owner-supplied release identity

- App name: Angrove
- Developer name: Sine Viridian (owner supplied; confirm the account display in App Store Connect)
- Initial public launch: United States only
- App Store Connect Apple ID: 6819392752

These facts update the working draft; no account identity or store availability was changed.
