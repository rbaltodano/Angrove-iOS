# Personal-data encryption device-validation record

Unfilled template. This is not evidence that validation was performed. Complete it from actual
physical-device observations and supporting records; simulator and unit-test results establish
repository behavior only. Leave unknown facts blank and identify them under known issues.

## Test identity

| Field | Recorded value |
| --- | --- |
| Date and time, including time zone | |
| Tester | |
| Physical device model | |
| iOS version and OS build | |
| App version and build number | |
| Source commit, if known | |
| Installation source (development, TestFlight, App Store) | |
| Test scope and fixture content | |
| Evidence paths or links | |

## Lock and unlock

Record the actions actually performed, their order, and the observed results. Include the state
before locking, behavior while locked, and access to the same saved content after unlocking
and relaunching. Record personal-key and widget-key behavior separately when checked.

| Step | Action and device/app state | Expected result | Observed result | Pass/fail/not checked | Evidence |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
| | | | | | |
| | | | | | |
| | | | | | |

- Lock method and duration:
- Protected-data/Keychain behavior observed while locked:
- Saved content readable after unlock:
- Saved content readable after relaunch:
- Widget behavior, if checked:
- Lock/unlock result and limitations:

## Backup and restore

Distinguish restoring an app binary, preserving files during an update, importing JSON, and
restoring device data with its encryption keys. Only record a backup/restore result when the
restore itself and post-restore decryption were observed. Do not include backup passwords,
Keychain secrets, or personal content in this record.

| Field | Recorded value |
| --- | --- |
| Backup date and method | |
| Backup encryption enabled and how confirmed | |
| Source device model and iOS version | |
| Destination device model and iOS version | |
| Restore date and method | |
| Restored app version and build | |
| App-data scope included | |
| Was the Keychain restored? (yes/no/unknown) | |
| Evidence for the Keychain-restore outcome | |
| Pre-backup fixture identifiers or checksums | |
| Post-restore content/decryption comparison | |

| Step | Backup/restore action | Expected result | Observed result | Pass/fail/not checked | Evidence |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
| | | | | | |
| | | | | | |
| | | | | | |

- Personal stores successfully decrypted after restore:
- Attachments and rotating conversation backups checked:
- Widget-key recovery, if checked:
- Key-loss behavior, if checked:
- Backup/restore result and limitations:

## Results and known issues

- Overall result:
- Checks completed:
- Checks not performed or not verified:
- Known issues and reproduction steps:
- Supporting logs/screenshots and capture dates:
- Follow-up work:
- Tester confirmation and date:
