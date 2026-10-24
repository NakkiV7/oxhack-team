# Install the Spottr beta

Checkpoint: 24 October 2026. **0.1 (1)** is processed and available to the owner's **Spottr Internal** TestFlight group. The owner tester membership and build assignment were verified through App Store Connect. This establishes distribution setup, not an installation on Omar's disconnected phone or Watch.

The **OxHack** external group has a [public invitation](https://testflight.apple.com/join/f3MhePbf), limited to 25 testers. Its build is **waiting for Apple beta review**, so the link is not yet a usable external download. No public App Store release was submitted.

## iPhone and Watch

1. Open the internal TestFlight invitation on the iPhone using the invited owner's Apple ID. Install **Spottr: AI Workout Coach** in TestFlight. Other testers should use the public invitation once Apple approves it.
2. Install the iPhone app first. In its TestFlight **App Details → Information** section, use the Watch install button when it appears for the paired, compatible Watch. Apple documents this companion installation route in its [TestFlight instructions](https://testflight.apple.com/). The phone and Watch need to be paired; Xcode discovery is not part of these installation steps.
3. Spottr requires iOS 26+ and watchOS 26+. Grant camera, Watch workout/heart-rate and motion permissions only when using those features. Confirm actual capture and command behavior during the morning device checks.

Core workouts, lessons, skill progression and local reports need no sign-in or provider key. Optional Gemini chat/reports/proposals need a reachable HTTPS gateway and its separate owner token. The development gateway on Omar's Mac uses port 8788; a phone cannot reach it using localhost. Never put the Google provider key in the app. The current gateway is single-owner; do not share its token with public testers.

## Release evidence

The signed archive includes the Watch companion and passed Apple validation, upload and processing. Export-compliance classification was saved using the [frozen-build audit](release-encryption-audit.md). Internal state is `IN_BETA_TESTING`; external state is `WAITING_FOR_BETA_REVIEW`. Build/delivery ID: `c0ae3b81-9bd6-4e1a-9e95-a7cf9fba27be`. The beta review uses the existing owner's contact details, with no demo account required. Private contact values and signing material are absent from the repository.

See the [MVP handoff](morning-handoff.md), [packaging evidence](release-readiness.md) and [open release issue](https://github.com/NakkiV7/oxhack-team/issues/31). Retest changed SDK/model/crypto code before reusing this build's classification. External approval, actual installs and physical workout quality remain separate checkpoints.
