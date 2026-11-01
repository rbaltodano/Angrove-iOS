# iOS 27 new-conversation deadlock — October 28, 2026

A friend reported that starting a chat crashes Angrove on an iPhone 16 Pro running iOS 27.
The installed build number and phone crash report were unavailable. Investigation reproduced
a main-thread deadlock in the current checkout on an iPhone 16 Pro / iOS 27.0 simulator
(24A5355p). This establishes an app defect, but does not identify the friend's termination.

## Reproduction and cause

Launch the normal app with its existing Default Start Screen preference set to New Conversation
(`aquinas.settings.defaultStartScreen = newConversation`). The process remains alive, but the
new-chat screen never appears. The last rendered frame can be the encryption preparation screen,
even though preparation has finished and chat initialization has begun.

The process sample records a lock cycle:

- Main thread holds SwiftUI's graph lock during `CurrentConversationView.onAppear`, enters
  `startNewConversation`, and cleans up the initial empty conversation. Its cold
  `FlaggedQuoteStore.load` waits synchronously for `SerializedPersonalStore`'s worker.
- The worker is saving another encrypted preference. `UserDefaults.set` synchronously posts
  a change notification; SwiftUI's `UserDefaultObserver` waits for the graph lock held by main.

No model generation is required to reproduce it. A physical phone may watchdog-terminate a
blocked app, but no such termination was captured here. A separate UserDefaults instance in the
same domain still notified SwiftUI and did not break the cycle.

## Change

`PrivatePreferences` now commits protected ciphertext and removals in the standard application
domain with CFPreferences and checks synchronization success. It avoids UserDefaults' synchronous
observer callout from the persistence worker. Ordinary settings continue using UserDefaults and
AppStorage. Ciphertext, keys, domains, store identities, cache ordering and storage locations are
unchanged. Injected test suites retain their existing UserDefaults behavior.

`PrivatePreferencesNotificationTests` verifies that a background encrypted save does not notify
the standard defaults observers on its worker, remains immediately readable from the persistence
cache, and persists encrypted bytes readable through standard defaults. It also verifies removal
and the existing defaults identity.

## Validation and limits

- Original checkout: 24 focused tests passed on iPhone 17 / iOS 27; 15 passed on iPhone 16 Pro.
  Their mounted submission coverage did not exercise full-shell startup, which exposed the bug.
- Fixed checkout: 27 tests in four suites passed on iPhone 16 Pro / iOS 27, including preference
  notifications, encryption/recovery, deferred-write ordering and mounted chat submission.
- Both iOS and Mac app targets built successfully. The signed normal Mac app was refreshed at
  `/Applications/Angrove.app` through `Tools/install-local-mac.sh`.
- The fixed normal app rendered the new-conversation composer on two normal iPhone 16 Pro
  simulator launches, including a launch after allowing SpringBoard teardown to finish.
  Two rapid relaunches instead produced a blank canvas with an active scene and idle main
  thread; samples no longer show the storage deadlock. Follow-up reproduced the same rapid
  relaunch blank in Apple's Settings app on the fresh simulator. A direct UIWindow capture
  showed Angrove's fully rendered chat and refreshed the simulator display. This is a
  simulator display limitation under immediate terminate/relaunch, not evidence of the
  original storage deadlock. Experimental startup-animation changes were removed.
  Raw screenshots, launch checks and before-fix process samples are retained locally under
  `build/friend-chat-investigation/`. Build/test logs are under `build/logs/friend-chat-*`.
- UI tap/type automation was unavailable. Startup used the existing New Conversation setting;
  message submission was checked through mounted regression tests. No live model generation or
  physical-phone install was performed. The simulator cannot validate the friend's shipped
  runtime, model delivery, device memory pressure or exact iOS patch version.

Old reproducible Mac build products and compiler caches were cleared when simulator startup
filled the disk. Source edits, personal app data, release archives and backups were preserved.
The fresh investigation simulator was removed after preserving evidence; the preexisting
iPhone 17 simulator was shut down without deleting its data.
The fix remains local; no iPhone release was uploaded. The friend's build number and `.ips`
report are needed to correlate the incident with this deadlock.

## Build 7 follow-up

The focused TestFlight candidate is based on build 6's recorded release commit `fb128fc`,
with source commit `60e0bdf` on `codex/ios27-chat-hotfix`. Only the preference fix, its regression
test, build number 7, and a required-resource packaging check were added. The exact final source
passed all 579 tests in 104 suites with Library/retrieval resources restored. The native runtime
UUID matches build 6; its model pack, encryption format, keys, and storage locations are unchanged.
The candidate and its generated artifacts live at
`~/Developer/Artifacts/ios27-chat-hotfix/`. No startup-animation change belongs to this hotfix.
