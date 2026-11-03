# iPhone tracking recovery and side-camera retirement

Omar reported that build 16 worked better, but its visibility warning cut off when he returned to view and squat joints sometimes disappeared near the bottom. He confirmed this was the iPhone camera and requested complete removal of paired side-camera support.

## Resulting behaviour

- A started visibility recording finishes naturally despite recovered tracking, another ordinary cue or its original start deadline. Mute, pause, backgrounding, source/session changes and discomfort/stop still cancel immediately. Rep audio yields until the recording finishes.
- Spoken tracking warnings wait for 0.75 seconds of continuous tracking loss. After a recording finishes, the current tracking state determines whether another warning is needed. Repeats start at least two seconds apart; intermediate warnings are discarded rather than queued. Visual tracking feedback remains immediate.
- A squat retains its observed leg and depth across up to two seconds without reliable joints. Depth must actually be observed, followed by a stable standing position. Two observed depth frames can confirm a bottom across a brief missing-frame run; a wholly invisible bottom cannot produce a rep. Longer absences reset the unfinished movement. Push-ups retain the existing 1.5-second continuity bound.
- Reps recovered through missing frames do not acquire fabricated lowering/rising phase measurements. Pause, input changes, invalid geometry and stale callbacks retain their reset/rejection rules.
- The native app no longer contains pairing controls, side-camera input choices, split previews, client/TLS/inference-worker code or bundled preview pairing configuration. The project generator cannot reintroduce that configuration. Historical Pi files remain under `hardware/pi`; they are not part of the app.

## Verification

Failing tests reproduced clip interruption/expiry, repeated short tracking warnings, lost squat depth/leg continuity and the unwanted third camera-input choice before the fixes. Evidence is under `.local/tracking-recovery-20261103/`.

Shared core: 102 XCTest cases and 205 Swift Testing cases pass. The old squat-outage test now uses an absence beyond the new two-second window; push-up bounds are unchanged. Phone/rest-preview, unavailable-camera, manual-fallback and Watch regression tests were preserved when the side-camera test files were retired.

Native regression: **206 tests pass**, zero failures or skips (`native-regression.xcresult` and `native-summary.json`). The new warning-finish/reassessment, short-flicker, cached-Arnold deadline and iPhone pose-flow cases pass. Two older preview tests were updated to wait through the deliberately introduced tracking grace period.

UI: `PatientOnboardingFlowTests/testWorkoutUsesOnlyThePhoneCameraWithoutPairingControls` passes on the existing shared `iPhone` simulator (`native-green.xcresult`, individual UI result). That earlier combined run contained three assertions in the two old preview tests above; the subsequent complete native run is green. No Chrome testing or new simulators were used. Shared simulator use was coordinated with the Musallī chat.

Device: signed **0.1 (17)** built successfully, installed and launched on the same paired iPhone (`phone-build.log`, `phone-install.json`, `phone-launch.json`). Strict deep signature verification passed. Host/Watch build versions both equal 17. The package contains the checksum-matching Full pose model, 99 offline MP3s and both demo movies. Neither preview pairing configuration nor retired side-camera types is present in the app binaries; SmartSpectra remains excluded (`phone-package-summary.json`). Tests exercise deterministic observations and audio callbacks; they do not establish real-world rep accuracy. A physical retry of the reported bottom-of-squat dropout remains necessary.
