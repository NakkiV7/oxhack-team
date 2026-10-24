# Team handoff

Canonical repository: [NakkiV7/oxhack-team](https://github.com/NakkiV7/oxhack-team). Native integration is merged through PR #36. Uncommitted packaging, evaluation and release preparation remain distinct from those merges; inspect the actual branch/diff before editing. The [current ledger](integration-readiness.md) records the exercised paths and remaining gates.

| Owner | Scope | First useful contribution |
|---|---|---|
| [@MishaGitnik](https://github.com/MishaGitnik) | ElevenLabs voice + landing page | Use the merged local playback boundary for a later authorized remote voice adapter. Confirm voice availability/rights before promising an exact identity. Review the existing local landing page/assets and accurate availability labels before publication. |
| [@azhar-rafiq](https://github.com/azhar-rafiq) | Push-up CV | Refine the existing MediaPipe geometry/state-machine baseline using labelled clips, calibration and failure cases. |
| [@NakkiV7](https://github.com/NakkiV7) | Squat CV | Refine the existing squat baseline, depth/view calibration and full-cycle tests; document accuracy and abstention on labelled clips. |
| [@omariosc](https://github.com/omariosc) | Native integration, Gemini, gateway, Watch, data/research/hardware tracks, documentation and final merge | Keep contracts and local demo stable, integrate feature PRs, regenerate the project, and record actual device/provider evidence. |

See [all assigned issues](ISSUES.md) for acceptance criteria and suggested branches.

## File boundaries

`Native/iOS/PoseDetector.swift` and `VisionWorker.swift` supply the common MediaPipe pipeline. `Shared/Core/PoseGeometry.swift` and `RepCounter.swift` contain shared geometry and counters; coordinate before either CV owner edits them. Add exercise-specific fixtures/tests in a focused PR. Avoid rebuilding the pipeline or broad formatting changes while the other CV branch is active.

Local Apple voice is merged: `VoiceCuePlaybackController`, `LocalVoicePlayback` and `CoachingVoiceBridge` already own event priority, expiry, opt-in and cancellation. ElevenLabs work should adapt this boundary rather than create a second competing audio owner. See the [voice handoff](voice-feedback.md); coordinate `TrainingStore`, `SessionViews` and any gateway contract changes with Omar. Fake playback tests do not establish audible acceptance.

Landing work belongs in `landing/`; a local page and assets exist. Coordinate its [design handoff](landing-design-handoff.md), source packaging and factual claims without editing native source or the generated Xcode project. Public page/App Store availability is not implied by a local page or an App Store Connect record.

Omar integrates shared contracts and `scripts/generate-project.rb`, then regenerates `Spottr.xcodeproj`. Teammates generate locally to run new files but omit incidental signing/project changes from their PRs. Agree a single editor for each shared file before working concurrently.

## Getting unstuck

Use the [getting-started instructions](../README.md) first. Open a setup/bug issue with the OS, Xcode/Swift/Node versions, command, exact redacted error and expected behavior. Include the exercise/view/source for CV issues. Do not paste `.env`, access tokens or personal workout data. Tag the feature owner; for source-contract/project conflicts tag `@omariosc`.

Good help-wanted tasks are bounded and independently reviewable:

- Label a small permitted push-up/squat clip set: full reps, partial reps, pauses, loss of view and count timestamps. Record consent/licence and provenance privately where needed.
- Check 19 catalogue entries for correct units, instructions and manual/timer behavior; camera support remains limited to two exercises.
- Review the 19 lesson guides and record authorized real demonstrations. Keep private imported movies and recordings out of Git; merged illustrations are not substitutes for filmed movement.
- Rehearse offline, permission-denied and stale-response paths; file reproducible bugs with expected behavior.
- Collect measured physical phone/Watch timings and source-labelled missingness without publishing private biometric data.
- Fact-check the landing page, slides and eventual DEV draft against the integration evidence ledger.

There is no CI/CD. Authors attach local checks and a short smoke-test result to each feature PR. The 19 icons and six phase illustrations are merged; coordinate further artwork changes. Container packaging is prepared, but creating a VM, spending credits, firmware changes and public publication remain separately scoped actions. Do not use a historical pending milestone or a prepared fixture as current live evidence.
