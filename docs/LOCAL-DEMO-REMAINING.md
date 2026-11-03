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

## Local-only follow-up after submission freeze

No commit, branch or GitHub action was made after the cutoff. The local source now includes richer isolated demo Watch telemetry and authored Presage-style report snapshots, compact trend/effort charts, and an exact-fixture-only history upgrade that preserves user edits and all normal-mode files. Real Presage estimates remain live measurement output; this fixture change does not persist them into real workout reports.

Presage now appears only after a completed set, on the rest screen. Camera ON/OFF controls framing independently from the explicitly consented45-second measurement. Background, next set, disabling or dismissal stops it. Side-camera recovery retains the last frame with a non-live reconnecting label while clearing stale pose data, then stops if no fresh result arrives within5seconds.

Verification: Core104XCTest+143SwiftTesting cases passed; default native54cases and biometric UI passed; SDK-enabled native41cases and rest-only Presage UI passed. The Apple Vision human model still needs physical-phone acceptance because its OS model weights are missing from this simulator. Local build9 is signed, installed over USB, and includes all17Arnold clips and private Presage configuration; actual physiological output remains unverified until the human starts the check.

### Latest local tracking and report repair

- Rep counts now retain an observed partial cycle across up to1.5seconds of missing/low-confidence tracking, with fresh stable confirmation required after reacquisition. Unseen depth, long gaps, backward clocks, a different body side and invalid geometry never create a rep. Duplicate timestamps no longer disarm the next cycle.
- SDK-enabled Apple Vision tries the upright and horizontal orientations, keeps the acquired orientation, and maps joints back onto the original image. Push-up elbow tracking can continue with a missing ankle without claiming full-body alignment was measured.
- Full reports accept isolated preview-only missing-signal examples for newly completed sessions; recorded values take precedence. HR, motion and energy use time-series lines that preserve long gaps. Joint-angle example curves stay display-only. Normal history is unchanged.
- Repeated sample-session/chat headings have been removed, with source information retained in settings and report details.
- Pi clock corrected; a strict-TLS95-second real camera run decoded163/163frames, renewing the same lease at30/60/90seconds. Current bundled pairing matches the working relay.28Pi companion checks passed. Capture was stopped after that diagnostic; the app starts its own capture when selected.
- Full Core passed104XCTest+154SwiftTesting cases. Native camera recovery/pose mapping/voice policy checks passed34cases; the Coach and full-report UI flows passed. Signed local build10 installed and launched successfully on the paired iPhone. The actual human pose-model fixture remains blocked by missing simulator OS weights; it was excluded explicitly from the passing recovery suite, not treated as a passing detector test. Physical push-up recognition, live Watch data, Arnold audibility and actual Presage measurements still require human phone acceptance.

### Build11: rest-vitals fallback and extended Presage

Installed and launched locally on the paired iPhone. Preview rest camera defaults to **Use example vitals**: labelled72bpm/14breaths per minute, with genuine current Watch heart rate preferred. This explicit example path starts no paid measurement. Normal accounts do not get invented readings. Live mode now requests HRV RMSSD, SDNN, mean NN and the unitless Baevsky index, allowing75seconds for the60-second warm-up and retaining qualified completed snapshots during rest. Blood pressure remains unavailable; relative arterial-pressure waveform is not systolic/diastolic BP.

Checks passed:104XCTest+162SwiftTesting Core cases;18native Presage lifecycle/mapping/panel cases;2rest-camera UI cases including immediate, labelled preview readings with no SDK start. No live SDK/provider request was made by these checks. The user's prior45-second attempt produced no displayed values; actual live Presage output remains unverified. Error/validation guidance is now surfaced safely. No GitHub or commit activity occurred.

### Build13: compact rest-vitals copy

Removed the lengthy example-data explanation from the rest camera panel and kept a compact Example source label on generated readings. The five-second visible-camera gate remains. The timing/panel tests and updated UI check passed; signed build13 installed locally on the paired iPhone. No provider calls or Git activity were made.

### Build14: default compact demo vitals

Removed the rest-panel example switch and per-value example captions; a single compact Demo badge identifies this panel in preview mode. Pulse, breathing, RMSSD42ms, SDNN54ms, mean NN833ms and unitless Baevsky65 appear only after the existing five-second visible-camera gate. Current genuine Watch heart rate and qualified Presage values retain priority. No invented BP or clinical interpretation is added. Generated values remain display-only and source-typed, with no writes to health or training records.

Full Core104XCTest+163SwiftTesting passed, as did six timing/panel tests and the updated preview UI flow. Signed build14 was subsequently installed and launched on the paired iPhone after it reconnected. No Git operations or provider calls occurred.

### Build15: native Full pose parity with Azhar's detector

The previous installed SDK-enabled build used Apple Vision, whereas the locally available push-up prototype requests MediaPipe Full. The default native path had used Lite. This local demo build disables the live Presage binary (to avoid duplicate Objective-C classes) and uses the official Full float16 Pose Landmarker for both iPhone and Pi-frame inference. The independently sourced rest-vitals demonstration still works without SDK linkage, after the same five-second visible-camera gate. The user confirmed that the audience is informed these are demonstration values, so the redundant panel badge was removed; normal records, source types and account-mode separation remain intact.

Full model SHA256:4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad. The download helper checks this checksum. It uses the same model family/variant as the prototype, not identical browser execution or rep logic: native duration/stability, multiperson rejection, aspect correction and bounded tracking-loss protections remain. Core thresholds were deliberately unchanged pending actual phone observation.

Verification:39native tests passed, including real Full human/blank-image inference, actual JPEG-to-pose camera ingestion, camera reconnection, rep audio and isolated rest-vitals timing. The rest-camera UI flow also passed. This is pipeline evidence, not validation of push-up/squat accuracy on the user. No GitHub activity or commits occurred.

Build15 was installed and launched successfully on the reconnected paired iPhone. The installed bundle was verified to contain the checksum-matching Full model, current private Pi pairing and17audio clips, and to exclude SmartSpectra.framework. Human phone recognition acceptance is the next check.
