# TestFlight build 3

Source: `ebbe560737d16ec3c6a72da7436ba25730587e19`. Version **0.1 (3)** includes the [Skills/report rendering and history-persistence refactor](history-persistence-2026-10-25.md). Relative to build 2's `b7bf563` snapshot, exactly four Native/Shared files changed (eight insertions/six deletions): `ReportViews.swift`, `SkillsViews.swift`, `TrainingStore.swift` and `HistoryStore.swift`. There is no measured device-speedup claim. The Gemini schema correction runs on the separate gateway; it is not a new native feature in this binary. The judges' deck keeps its independent 00:09 UTC snapshot.

## Archive and export

The isolated release source matches all **130** tracked Native/Shared files at the stated commit. Archive and export succeeded using the existing distribution identity/profiles and release-only build-number overrides; team-neutral repository defaults remain unchanged. Independent final-artifact inspection established:

- iPhone `com.omarchoudhry.spottr` and embedded Watch `com.omarchoudhry.spottr.watchkitapp` both contain **0.1 (3)**, matching companion identity and `ITSAppUsesNonExemptEncryption: false`.
- Strict deep signature verification passed for both archive and exported apps. Profiles and entitlements match build 2, including `get-task-allow: false`.
- All **ten** checked resource paths/hashes, including the first-party privacy manifests and pose task, match build 2. All **127** vendor files also match. The pose task SHA-256 remains `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`.
- Export recorded no warnings. Four archive warnings were recorded: two missing `AccentColor` asset warnings and two skipped App Intents metadata-extraction warnings because those targets do not depend on AppIntents. They did not prevent archive/export success.

Independent inspection compared the actual final IPA with the archive: executable UUIDs and `__TEXT,__text` hashes match for all three slices, and their dSYM UUIDs agree. Signing may change whole-executable bytes; the table compares code sections.

| Slice | UUID | Code-section SHA-256 |
| --- | --- | --- |
| iPhone arm64 | `7F59E0B0-C362-39A9-8119-6FD9FD4B47C9` | `b10ab1ac35e0161f84c25b0820e3564ff36eea7f9667d80cb04e9ef32e80886e` |
| Watch arm64 | `6CFC9A27-B135-3813-B258-1329C8078455` | `4124f04e300fba23016d018966616fca88ce187d6575b12571c74460bf2bdbc9` |
| Watch arm64_32 | `D73370C5-3306-384E-8A8E-0F0964596DF7` | `ae0ebfa9b1ad3751e8198c5e5601e8d4b8b66f60289382da54ebcac64df52af9` |

IPA: **24,773,441 bytes**, SHA-256 `de572163ff395f3db620725435e85773ea5c442d615d6e9dda61ccc1df149315`. Private artifacts/audits/logs remain under ignored `.local/release/mvp-build-3/`; signing material is not published.

## Encryption continuity and acceptance limits

The independent bounded build-3 scan retains the same **14** case-insensitive decrypt symbol names as build 2, with no matches in the scanned ChaCha/Randen/crypto-common/SHA1/MD5/cipher families. Both nested model files remain plaintext `TFL3`, and observed dynamic dependencies are Apple/system libraries. Its independently resolved registry storage at `0x101ad3730` is initially zero across 32 bytes; the guard at `0x101ad3750` is initially zero across eight bytes. SDK/model inputs, cryptographic/network source and relevant link settings are unchanged from the earlier audited build. The full initializer/reference audit was not repeated, and initial zero storage or symbol absence does not establish the complete runtime call graph.

These continuity checks support the existing [technical classification](../release-encryption-audit.md), not a new vendor/legal attestation. Successful app signing or Apple validation does not resolve the [SDK privacy/origin-signature gap](../release-readiness.md#mediapipe-distribution-remains-unresolved); [issue #52](https://github.com/NakkiV7/oxhack-team/issues/52) remains open.

A separate same-source Watch simulator build/run succeeded in 15.4 seconds (`build_run_sim_2026-10-25T00-19-30-194Z_pid4129_ba1875c5.log`). Its Debug bundle retained default **0.1 (1)** and showed the idle “Open Spottr on iPhone” UI. One metadata-extraction warning was recorded. This does not establish physical installation, sensor capture or companion transport, and its Debug build number does not describe the distribution artifact.

## Apple distribution

Apple validation returned exit 0 and `VERIFY SUCCEEDED with no errors` at **25 October 2026 00:22:55 UTC**. Upload returned exit 0 and `UPLOAD SUCCEEDED with no errors` at **00:27:06 UTC**, delivery UUID `5c610f6d-5ebd-46e0-9099-0ea5e07a7ee6`. Build 3 was not immediately listed in App Store Connect. At approximately **00:33 UTC**, App Store Connect confirmed build ID `5c610f6d-5ebd-46e0-9099-0ea5e07a7ee6` (matching the delivery UUID), `processingState: VALID` and `usesNonExemptEncryption: false`. The existing **Spottr Internal** group was explicitly assigned build 3; read-back confirmed builds **1, 2 and 3** in that group, with build 3 `IN_BETA_TESTING`. Its external state is `READY_FOR_BETA_SUBMISSION`; it was not submitted externally.

At **00:28 UTC**, App Store Connect reported external build **1** as `IN_BETA_TESTING`. The **OxHack** external group still contains only build 1, with its [public invitation](https://testflight.apple.com/join/f3MhePbf) enabled and limited to 25 testers. This supersedes the earlier waiting-for-review state. Subsequent read-back still showed only build 1 assigned externally.

The public Apple invitation page was verified in Chrome: it displayed **Get TestFlight**, **View Spottr: AI Workout Coach Beta** and **View in TestFlight**, without a closed-beta message. The [page-only screenshot](testflight-public-invitation-2026-10-25.jpg) is a 1302 × 614 JPEG, 60,799 bytes, SHA-256 `6962eafd992792f7e1e63ac038dc81655be12b018cdb9975e24d26c13003aaee`. A subsequent landing check followed the hero and footer HTTPS links to this Apple page. The `itms-beta` deep link was not clicked, and no invitation was accepted or app installed during these checks. No public App Store submission, actual phone/Watch installation or physical behavior is established.
