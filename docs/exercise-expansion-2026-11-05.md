# Exercise expansion — 5 November 2026

The catalogue now contains 32 entries, including 13 camera counting choices. Existing raw identities and saved history formats are preserved. New alternatives remain available in the exercise library; the existing family path sequences and their onboarding placement stay unchanged.

## Added camera counting choices

- `tempoSquat`, `tempoPushup`: at least three observed seconds from the first sample leaving the extended position to the first sample at depth. Time spent at depth cannot substitute for lowering time.
- `pausedSquat`, `pausedPushup`: at least two continuous seconds at depth before returning to extension. Leaving depth before the hold completes restarts the hold. A hold cue appears while the pause is pending.

These retain the existing stable extension/depth checks, image-space knee/elbow angles, side identity and body alignment gates. New temporal push-ups require a visible ankle and shoulder–hip–ankle body-line measurement; legacy push-up missing-foot behavior is preserved. New temporal choices discard an incomplete movement after low/nonfinite confidence or a sample gap greater than 0.75 seconds, as well as the existing side/alignment/reset/time-invalidity gates. Previously completed counts survive resets. Existing variations retain bounded short occlusion recovery.

Timing is an observed threshold, not a measured uniform movement speed. Depth thresholds remain 105° for these squats and 100° for these push-ups, with extension at 160°. A person who needs a smaller range can choose half/supported squats or a manual alternative. No stance width, hand spacing, support contact, balance quality, or clinical efficacy is inferred.

## Added manual alternatives

`widePushup`, `diamondPushup`, `calfRaise`, `birdDog` and `seatedKneeExtension` record repetitions with separate catalogue identities. `wallSit` records seconds through the existing hold timer or manual entry. Wide/diamond instructions explicitly say the camera does not check hand placement. Bird dog and knee extension count each side; the filming checklist requests both sides.

Every new entry selects a dedicated faceless vector figure. The guide uses the existing stick-figure visual language with highlighted joints, wall/chair/support marks, a floor baseline, and timing badges where relevant. Drawings are instructional illustrations and are not pose measurements. Existing image assets are preserved.

## Verification

Tests preceded production changes. The first expansion red run had nine failures for missing catalogue/exercise/guide identities. After adding identities, six temporal/geometry tests produced 18 issues against the old generic counter/geometry. Separate red runs showed the old rise cue during an incomplete pause, and all ten missing dedicated figure selections. The corresponding tests passed after implementation.

Core tests use an ordinary SSD package snapshot at `/Volumes/Spottr Development/exercises-package` and scratch `/Volumes/Spottr Development/exercises-core`. In-progress `Membership*.swift` source/tests are excluded from this snapshot to avoid another agent's concurrent TDD cycle; the integrating agent must also run the combined package suite. No local `.build`, new simulator, worktree, branch, commit, ML model, or training workload was created for this expansion.

The staged whole-package run executed 234 tests. The latest run has one outstanding catalogue expectation in `capabilitiesSeparateAssessmentCountingAndPractice`: its equipment list must include the new stable chair. All exercise expansion, temporal, geometry, guide, manual provenance and existing continuity assertions pass. The integrating agent owns that expectation and the combined suite. Native artwork syntax parsing is separate from an iOS build. No device, simulator, browser, physical movement, visual acceptance, latency, sensitivity, specificity, or clinical validation is claimed.
