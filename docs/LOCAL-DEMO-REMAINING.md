# Local demo: what remains

Checkpoint: **25 October 2026, camera recovery and Presage local variant, 11:50 London**. This is a remaining-work list, not a claim of physical acceptance or a new TestFlight release. Stop after the requested phone installation and acceptance; the items below do not authorize extra work.

## Immediate acceptance

- **Phone:** local 0.1 (8) is installed and launched; its process was confirmed running. Physical testing found that the camera stopped after a few seconds and cached audio was not audible. Camera expiry recovery, image/overlay alignment, explicit audio-session activation and preview encouragement every two completed camera reps now pass software checks. Installed build 8 adds side-only capture, reconnection without resetting completed reps/sets, the louder 17-clip Arnold bank and a Presage panel. These still need a physical retry.
- **Physical-feedback regression checks:** 53 native voice/store/lifecycle cases and 22 camera client/worker cases passed after observed RED failures. These include a delayed inference result being discarded while the next fresh frame recovers on the same lease, and a sustained outage stopping capture.
- **Current software checks:** the focused 39-case native run and separate 22-case native run plus Rewards UI passed. Core passed 104 XCTest and 141 Swift Testing cases. Scripted Coach, Skills preview and Progress UI checks passed. These are software/simulator results, not exercise-accuracy or physical Watch acceptance.
- **Pi:** the Mac relay passed a fresh check at 10:23 UTC; private pairing configuration is included in the local demo setup. Still verify the phone receives the intended live side-camera stream, stops it reliably, rejects stale frames and supports explicit manual fallback. Do not publish pairing secrets.
- **Watch:** the registered Watch is included in the development profile and companion bundle, but it is not currently discoverable to the Mac. Actual sync/install, permissions, fresh readings, controls and saved reports remain unverified. Simulator checks do not establish these; missing sensor values must remain missing.
- **Push-up acceptance:** the reported failure to recognize push-ups is still unconfirmed. The native path uses correct elbow landmarks, but needs a complete side view and accepted frame intervals below 0.75 seconds. Retest after the camera recovery fix; do not claim accuracy from synthetic tests.
- **Exercise scope:** live automatic counting supports the base **push-up and squat** only. **Pull-ups are unsupported.** Other catalogue exercises use manual repetitions or hold timing.
- **Infrastructure:** the existing Vultr VM continues billing until destroyed; retain the planned cleanup deadline of 26 October 06:47 UTC. No new hosting work is authorized here.
- **Release:** the new local source has not been uploaded to TestFlight. The earlier reported **0.1 (5)** post-onboarding crash remains unreproduced and unresolved; passing frozen-source simulator cases did not identify its cause.

## Provider integrations still needing acceptance

| Service | Verified checkpoint | Remaining gate |
| --- | --- | --- |
| Vultr / Gemini | Hosted Gemini accepted one bounded synthetic response. | Verify the intended normal-mode defaults and deploy/accept the current demo API; the earlier response does not validate every current native route. |
| Tiger | Persistence/SQL behavior has offline coverage. | Resolve the strict certificate-chain failure and verify authorized live persistence without disabling TLS checks. |
| Snowflake | Authentication and a no-warehouse `CURRENT_VERSION()` check were accepted. | The scoped role, token, schema and grants are configured; verify the funded warehouse import and live analytics reconciliation. Remaining credits are unverified, so that import is on hold. |
| Presage | API-key use is authorized; SDK-enabled local build, three mapping tests and three panel tests pass. The variant excludes external MediaPipe and uses Apple Vision to avoid duplicate classes. | Phone must verify body-pose inference and explicitly start the front-camera check (45 seconds maximum). Actual authentication, quality, metrics and quota remain unverified. Apple Vision inference fails in the current simulator because model weights are missing; this is not a passing detector test. |
| ElevenLabs | The 12-cue offline bank has been tested. | Deploy and accept the intended live gateway path; an offline bank is not proof of live synthesis or an authorized named-person voice. |

Private configuration must stay private. Preview history, scripted Coach replies and fixture results must remain clearly separate from real activity and live provider evidence. See the [integration ledger](integration-readiness.md) for source and earlier receipts.

## Deferred ideas and user-dependent work

- **19 real lesson clips:** await the user's recordings; the existing artwork, filming guides and import UI do not replace real demonstrations.
- **Running and workout zones:** separate future design and validation; neither is part of the current strength-workout demo.
- **Watch complications and extended sensors:** deferred drafts and physical human verification remain follow-up work. Presage is a separate opt-in investigation, not a substitute for missing Watch readings.
- **Cloud accounts:** the MVP's optional local display name is not authentication, multi-user isolation or account recovery/deletion.
- **Delta:** prepared packets are not evidence that an actual Delta evaluation was run.

Keep these boundaries and the preserved draft locations in [POST-HACKATHON.md](POST-HACKATHON.md); resume only the next explicitly chosen slice.

## Submission freeze

Omar requires the final GitHub push by **25 October 2026, 11:55 London**. After that time, all work must stay local: no new branches or GitHub operations, including comments, fetches or PR updates. Camera/voice/Presage physical acceptance can continue locally.

Latest checks: 93 native camera/voice/store cases passed before the Presage build; 28 Pi companion cases passed. SDK-enabled mapping/panel/store cases passed (24), as did the side-only UI (19.248 seconds) and finished Close UI (14.139 seconds). The actual Apple Vision human-fixture execution remains blocked in this simulator by missing OS model weights, including a failed CPU-only candidate that was reverted.

Build 8 bundle verification: 17 Arnold MP3s, SmartSpectra.framework and private Presage configuration are present. Human phone acceptance is pending. Enhanced demo biometric history/analytics requested at the cutoff remains a separate local follow-up if not completed before the final push.
