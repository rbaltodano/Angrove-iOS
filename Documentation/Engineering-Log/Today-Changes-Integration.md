# October 6 Library and polish integration

The performance build at `16cc099` used the canonical `main` checkout. Completed changes in the
dirty `Aquinas-iOS-study-branch` worktree were absent from that build. This integration imports
that worktree's patch into main, preserving its original files and the performance changes.

Included work:

- Library reader Ask, New/Existing Conversation choices, Library quote chips/cards, author/date
  attribution, bookmarked Clipped Passages, and the conversation Plus → Passages picker.
- Sidebar contents animate on the first opening, then appear without replaying that entrance.
- Adding a conversation to a Study Topic requests the tree-update prompt even if the Topic page
  is recreated or the app restarts.
- Completed response system notifications use the conversation title and completed answer.
  Page-return prompts remain in-app and retain the existing delay/border behavior.
- In-flight generation receives iOS's finite background execution window. This does not promise
  unlimited background generation; existing memory, thermal, and runtime lifecycle policy stays.

Three-way integration retains main's encrypted recents/preferences, definition deduplication,
page-return notification exclusion, and asynchronous persistence. Clips use protected atomic file
storage, with legacy migration, instead of the older worktree's direct UserDefaults writes.
The cross-repository contract is [Library passages](https://github.com/rbaltodano/Angrove-Foundations/blob/main/LIBRARY-PASSAGES.md).

The separate word-streaming experiment at `d9742c6` remains paused on its branch: its author
reported that intermediate model updates still did not reach the UI. Main keeps the requested
twice-as-fast answer reveal and existing animation style.

Before installing, conversation files and five rotating backups, Insight Tree files, and
preferences were copied from the production container and verified locally by SHA-256. This
backup does not include Keychain keys, and no history restoration or production-data reset was
performed. A differing display name never constitutes a separate data instance.

Validation: physical-device build and all 414 tests in 67 suites passed in the full serial
simulator regression run. This includes old Insight decoding,
protected clip migration/round-trip, and the reader Ask/Copy menu. The exact signed app's name,
bundle ID, Library corpus, and model resources are checked before installation. Library touch
interaction and subjective animation smoothness require an on-device visual check because the
available tooling cannot expose the iOS UI hierarchy.
