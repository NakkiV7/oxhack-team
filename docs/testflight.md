# Install the Spottr beta

Checkpoint: 25 October 2026. **0.1 (2)** is processed and available to the owner's **Spottr Internal** TestFlight group alongside **0.1 (1)**. App Store Connect confirmed build 2 as `VALID` and `IN_BETA_TESTING` after explicit assignment to that group. Distribution setup does not establish an installation on Omar's phone or Watch.

The **OxHack** external group has a [public invitation](https://testflight.apple.com/join/f3MhePbf), limited to 25 testers. It contains only build **0.1 (1)**, still **waiting for Apple beta review**, so the link is not yet a usable external download. Build 2 was not submitted externally (`READY_FOR_BETA_SUBMISSION`). No public App Store release was submitted.

## iPhone and Watch

1. Open the internal TestFlight invitation on the iPhone using the invited owner's Apple ID. Install **Spottr: AI Workout Coach** in TestFlight. Other testers should use the public invitation once Apple approves it.
2. Install the iPhone app first. In its TestFlight **App Details → Information** section, use the Watch install button when it appears for the paired, compatible Watch. Apple documents this companion installation route in its [TestFlight instructions](https://testflight.apple.com/). The phone and Watch need to be paired; Xcode discovery is not part of these installation steps.
3. Spottr requires iOS 26+ and watchOS 26+. Grant camera, Watch workout/heart-rate and motion permissions only when using those features. Confirm actual capture and command behavior during the morning device checks.

Core workouts, lessons, skill progression and local reports need no sign-in or provider key. Optional Gemini chat/reports/proposals need a reachable HTTPS gateway and its separate owner token. The development gateway on Omar's Mac uses port 8788; a phone cannot reach it using localhost. Never put the Google provider key in the app. The current gateway is single-owner; do not share its token with public testers.

## Release evidence

**Build 2:** the archive from staged source `b7bf563dc8c2e93a0f4e72d84de1cf7837a26749` and its export passed independent inspection: host and embedded Watch version **0.1 (2)**, matching distribution profiles, entitlements and bundled resources. Apple validation returned exit 0 / `VERIFY SUCCEEDED` at **23:06:21 UTC on 24 October**; upload returned exit 0 / `UPLOAD SUCCEEDED` at **23:08:00 UTC**. At **23:10:33 UTC**, App Store Connect verified build ID `ba329de6-2a44-4c8b-b2d5-31841fad0f05` as `VALID`, with `usesNonExemptEncryption=false`, and internal state `IN_BETA_TESTING` after group assignment. The IPA is 24,774,269 bytes, SHA-256 `61779379fac39bd1c459f95e01883e956f1eeefbcf45f869ae90bf9268379fe0`. [Build 2 evidence](evidence/testflight-build-2-2026-10-24.md).

**Build 1 receipt:** the signed archive includes the Watch companion and passed Apple validation, upload and processing. Export-compliance classification was saved using the [frozen-build audit](release-encryption-audit.md). Internal state is `IN_BETA_TESTING`; external state is `WAITING_FOR_BETA_REVIEW`. Build/delivery ID: `c0ae3b81-9bd6-4e1a-9e95-a7cf9fba27be`. The beta review uses the existing owner's contact details, with no demo account required. Private contact values and signing material are absent from the repository.

See the [MVP handoff](morning-handoff.md), [packaging evidence](release-readiness.md) and [open release issue](https://github.com/NakkiV7/oxhack-team/issues/31). Retest changed SDK/model/crypto code before reusing this build's classification. External approval, actual installs and physical workout quality remain separate checkpoints.
