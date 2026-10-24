# Team handoff

Canonical repository: [NakkiV7/oxhack-team](https://github.com/NakkiV7/oxhack-team). Branch publication and PR state should be checked on GitHub; the local baseline is not a claim that every change has merged into `main`.

| Owner | Scope | First useful contribution |
|---|---|---|
| [@MishaGitnik](https://github.com/MishaGitnik) | ElevenLabs voice + landing page | Build a small cached cue set with the requested David Goggins voice direction; confirm an available authorised voice/voice ID before promising that exact voice. Demonstrate audible phone playback and stop priority. Ship a landing page that describes verified behavior. |
| [@azhar-rafiq](https://github.com/azhar-rafiq) | Push-up CV | Refine the existing MediaPipe geometry/state-machine baseline using labelled clips, calibration and failure cases. |
| [@NakkiV7](https://github.com/NakkiV7) | Squat CV | Refine the existing squat baseline, depth/view calibration and full-cycle tests; document accuracy and abstention on labelled clips. |
| [@omariosc](https://github.com/omariosc) | Native integration, Gemini, gateway, Watch, data/research/hardware tracks, documentation and final merge | Keep contracts and local demo stable, integrate feature PRs, regenerate the project, and record actual device/provider evidence. |

See [all assigned issues](ISSUES.md) for acceptance criteria and suggested branches.

## File boundaries

`Native/iOS/PoseDetector.swift` and `VisionWorker.swift` supply the common MediaPipe pipeline. `Shared/Core/PoseGeometry.swift` and `RepCounter.swift` contain shared geometry and counters; coordinate before either CV owner edits them. Add exercise-specific fixtures/tests in a focused PR. Avoid rebuilding the pipeline or broad formatting changes while the other CV branch is active.

Voice work should own a small cue/audio boundary and its tests; coordinate changes to `TrainingStore`, `SessionViews` and gateway contracts with Omar. Landing-page work should stay in its own directory and avoid native source or the generated Xcode project. Choose its minimal tooling in the feature issue; there is no existing web app implied by the native baseline.

Omar integrates shared contracts and `scripts/generate-project.rb`, then regenerates `Spottr.xcodeproj`. Teammates generate locally to run new files but omit incidental signing/project changes from their PRs. Agree a single editor for each shared file before working concurrently.

## Getting unstuck

Use the [getting-started instructions](../README.md) first. Open a setup/bug issue with the OS, Xcode/Swift/Node versions, command, exact redacted error and expected behavior. Include the exercise/view/source for CV issues. Do not paste `.env`, access tokens or personal workout data. Tag the feature owner; for source-contract/project conflicts tag `@omariosc`.

Good help-wanted tasks are bounded and independently reviewable:

- Label a small permitted push-up/squat clip set: full reps, partial reps, pauses, loss of view and count timestamps. Record consent/licence and provenance privately where needed.
- Check 19 catalogue entries for correct units, instructions and manual/timer behavior; camera support remains limited to two exercises.
- Rehearse offline, permission-denied and stale-response paths; file reproducible bugs with expected behavior.
- Collect measured physical phone/Watch timings and source-labelled missingness without publishing private biometric data.
- Fact-check the landing page, slides and eventual DEV draft against the integration evidence ledger.

There is no CI/CD. Authors attach local checks and a short smoke-test result to each feature PR. New image generation is paused; use the existing assets. No deployment, firmware flash or public article publication is implied by a feature PR.
