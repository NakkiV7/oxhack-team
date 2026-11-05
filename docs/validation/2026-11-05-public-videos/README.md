# Public-video movement validation — 5 November 2026

This is bounded engineering validation of Spottr's bundled native pose pipeline, not a clinical evaluation or an accuracy claim for all 52 automatic exercise profiles. Public demonstrations differ from a live phone camera in framing, edits, clothing, speed and person visibility. The references were visually assigned by Codex, not an independent human annotator.

The original acquisition selected 24 sources and 33 windows before model output. Eight sources were originally held out. After the development baseline exposed measurement-family gaps, four additional development sources and eight windows were selected and visually labelled before their own native outputs. That creates 28 distinct selected sources and 41 primary windows. Overlapping windows and repeated actors are not independent trials. An additional downloaded Baptist sit-to-stand candidate was never selected or replayed.

Candidate 1 was frozen before the first evaluation of the eight held-out sources. Those first results are preserved. Four sources were then explicitly promoted to development to fix demonstrated defects: kneePushupNASM, calfRaiseBalance, hipAbductionAHA and sitToStandRoyalFree. Original split fields and reference files remain unchanged. Candidate 2 is an unblinded re-evaluation; it must not be described as a new independent held-out validation. The separate NASM cut-free sensitivity reuses a consumed source and does not replace the original full-window result.

## Pipeline and cadence

The opt-in XCTest uses AVAssetReader with actual presentation timestamps and preferred orientation, bounded decoded input (at most 640 pixels on either axis), one native PoseDetector per window, bundled MediaPipe Full model/SDK 1.1.1, PoseGeometry and the production rep/hold counters. Frames are processed sequentially with an autorelease pool, no retained images and no Python detector or replacement model. Raw poses and videos stay in private external storage, outside the app and Git.

The initial 15 Hz development baseline was exploratory. Inspection of VisionWorker showed a production maximum cadence of 10 Hz. Final primary trials therefore use a minimum 0.1-second interval between accepted actual timestamps. Some sources deliver approximately 8 Hz because their encoded frames do not fall exactly on that interval. This is not a hardware frame-rate guarantee. Cached-pose mirror/rate/dropout replays are explicitly distinguished from native end-to-end runs. A bounded 720p sensitivity did not rescue the occluded paired chains in the selected mountain-climber/bird-dog/dead-bug clips.

Reps require observed setup, excursion and return. Synchronized bilateral arm curls/raises count as one displayed cycle; raw completed limb cycles are also retained. Alternating individual leg actions count individually. Holds earn only qualified adjacent observed intervals: neither wall clock nor lost-frame gaps are substituted. Dynamic high-knee timing also requires witnessed alternating activity, so short clips lose startup and discontinuous intervals.

## Ambiguous people and edits

An explicit multiple-person model result now suspends camera counting until an intentional Resume-camera action and two seconds of valid single-person observations. Earned quantities survive; unfinished movement is discarded. The workout remains active and ordinary speech is allowed to finish. Phone and Watch publish needs-Resume, waiting-for-clear and rearmed states. Old queued capture frames cannot re-arm or re-latch a new generation. Manual input remains available and does not erase unresolved camera recovery.

This protects the Royal Free examples where the model alternates between multiple-person detections and several seconds of false single-person tracking. It cannot reject a second person who is never detected. It can also conservatively pause on false multiple-person output. In the NASM knee-pushup source, exact inspected frames at 6.131125 and 14.26425 seconds show one person without a visible duplicate, near zoom cuts; stale video tracking across the edit is a plausible explanation, not proven physical multiplicity. The full primary result remains visible. No scripted acknowledgment is inserted into primary trials.

## Interpreting the matrix

The matrix retains physical actions, expected automatic quantity/rejection, output, count/time deficit or excess, and pose/measurement coverage separately. Royal Free has one physical patient stand in each window but an expected automatic quantity of zero; Cleveland shows one physical bridge while its critical chain is cropped. Other rejection sources with no annotated physical count say so rather than pretending there was no movement.

Deficits/excesses are aggregate quantity differences, not event-matched false-negative/false-positive rates. “Measurement coverage” means geometry could produce a finite measurement, not that counting was armed, posture was clinically correct, or a complete cycle was visible. Static-hold seconds and dynamic-activity seconds are not pooled with reps. The preserved source annotations carry the exact case/view notes and URLs.

## Scope of the fixes

- Resting arm raises and stable near-extension setup now use observable movement-family rules; neutral calibration needs stable valid samples, substantial subsequent excursion and a return. Source/provenance changes and limb loss cannot fuse phases.
- Initial side selection chooses the clearest complete chain and preserves that identity during a bounded ordinary dropout. Confidence remains 0.6.
- Bridge counting uses projected hip opening; side-plank accepts visible forearm or straight-arm support with side/body-line gates. Neither claims measured floor contact or load.
- Calf counting follows one complete visible leg/heel/toe chain and projected foot tilt. It does not verify the far leg or floor contact. Hip-abduction uses projected leg excursion instead of torso-scaled ankle displacement.
- Knee-supported presses retain the measured body angle and adjustment feedback through moderate projected hip flexion; quadruped posture still resets. Ordinary straight-leg presses keep the stricter rule.
- Ordinary returns can confirm with two observations after witnessed depth and the existing complete-cycle duration. Setup and tempo/pause timing remain stricter. No isolated unseen extremum is invented.

Aspect-ratio distortion was investigated and ruled out here: existing image geometry converts normalized x/y back to width/height units before Euclidean calculations. Overlay coordinates and metadata were not changed speculatively.

## Provenance and limits

Exact source/annotation hashes, model/SDK hashes, code snapshots, configuration, commands, results and private trace hashes are retained. Candidate 2 receipts additionally hash the actual Debug app dylib and all shared core source files. Earlier baseline/Candidate 1 receipts hashed the app launcher and XCTest executable, with source/dirty-diff/build evidence, but did not separately hash the Debug app dylib; that missing earlier binary hash is a provenance limitation and is not retroactively claimed.

The remaining misses and false pauses are part of the result, including unsupported frontal squat views, cropped chains, paired-limb occlusion in bird-dog/dead-bug/mountain-climber demonstrations, edit stress and brief observed activity. Synthetic regressions prove software semantics, not real-world accuracy. There is no new model training, paid inference, physical-phone/Watch acceptance, clinical-form validation or all-profile success claim from these sources.

## Explicit post-output reference erratum

The original calfRaiseBalance reference says four cycles and remains immutable. After seeing output3, the implementer and root separately re-inspected the original47-frame/4fps source contact sheet. Root acknowledged its original count was mistaken: three lifts/returns occur approximately1.25–2.77,4.26–6.26 and7.51–9.51s, with planted/idle start and tail. The result remains **3/4 against the original locked reference**, alongside **3/3 against this post-output source audit**. The correction is not blind, independent-human or clinical validation. No threshold was changed to invent a fourth action. [Erratum](post-output-reference-errata.json), SHA256 `a7a00a22439fc7fb10f545d4a250e37bfe3f4547ab899f993bf0d01f79652c91`.

The subsequent [v2 erratum](post-output-reference-errata-v2.json) also documents the South Tees knee-pushup window `video-28` (13.5–16.0s). Higher-resolution source reinspection found descent/bottom and only a partial rise before the boundary; it contains zero complete cycles, with physical movement present. The original **0/1** remains in the primary matrix; the post-output interpretation is **zero complete cycles**, not a newly passed independent positive. The full-source four-action reference is unchanged. Erratum-v2 SHA256: `8bb2ed7ae958e50af47c5fa03e948ecdb0e22c32b5aa20c0af7d2c122fd9abe9`.

## Witnessed time accounting

These disjoint durations sum to the original selected window. “Unobserved adjacency” means at least one endpoint lacks a valid geometry measurement; no interval is filled across it. Valid startup precedes the first credited interval. Valid unqualified intervals after startup lack the required witnessed activity evidence. Values below are rounded; [exact accounting](time-accounting.json) is retained.

| Window | Credited | Unobserved adjacency | Valid startup | Later valid but unqualified | Unsampled boundaries |
|---|---:|---:|---:|---:|---:|
| highKnees32 (3.7s) | 0.801 | 1.602 | 0.401 | 0.801 | 0.096 |
| highKnees33 (3.2s) | 0.701 | 1.702 | 0.506 | 0.200 | 0.091 |
| plank18 (8s) | 7.920 | 0 | 0 | 0 | 0.080 |
| sidePlank19 (7s) | 3.504 | 3.406 | 0 | 0 | 0.090 |
| singleLegBalance40 (14.5s) | 13.560 | 0.840 | 0 | 0 | 0.100 |

The final full native regression ran260 tests with one explicit opt-in-video skip and zero failures; four pre-existing simulator StoreKit notEntitled cases remain excluded and are not claimed passing. The actual41-window native validation runs processed4507 frames with zero skips. Core ran139 XCTest cases successfully; Swift Testing reported337 cases with the cached-pose helper explicitly disabled. A focused seven-case Companion/recovery check covered the Watch button-label correction before those final suites. [Final integration receipt](final-integration-receipt-v3.json) distinguishes the subsequent Watch-label and same-input audio-continuation fixes. Detector, geometry algorithms, counters, cadence and session quantities match the frozen replay; the final PoseGeometry.swift message-only change is separately verified against the frozen file.

## Separate sensitivity trials

The same-source controls initialize a new native detector at the stated window start, with no scripted Resume. They were selected and visually labelled after full-source outputs were known, before their own comparison; they add no independent sources. NASM knee6.5–13.5s contains one complete cycle: first sensitivity0/1 exposed the stable-neutral boundary defect; the frozen counting candidate replays1/1. Ordinary pushup4.0–10.2s contains two complete cycles and replays2/2. Full edited windows remain0/3 and0/4 respectively. [Control references](pushup-cut-free-sensitivity-reference.json) and [all sensitivity results](sensitivities.json) retain the chronology.

| Cached-pose sensitivity | Squat01 reps | Arm raise08 cycles | Plank18 seconds | High knees32 seconds |
|---|---:|---:|---:|---:|
| Primary10Hz-cap trace | 3 | 4 | 7.92 | 0.801 |
| Mirrored points/side identities | 3 | 4 | 7.92 | 0.801 |
| Every7th observation invalidated | 3 | 4 | 5.64 | 0.601 |
| Older native15Hz trace, frozen counting code | 3 | 4 | 7.96 | 1.602 |
| Primary trace thinned to7.5Hz grid | 3 | 4 | 7.92 | 0.100 |
| Primary trace thinned to5Hz grid | 3 | 4 | 7.80 | 0 |

These variants test measurement/counter sensitivity, not the detector at a new live cadence. The15Hz trace came from the earlier native exploratory run; old traces lack the later explicit ambiguity field. Dynamic activity remains highly dependent on actually witnessed alternation and adjacent valid frames. The zero/low-rate results are retained, not converted to elapsed time.

A final focused native rendering test passed after the full suite and an actual rendered-primary-action red→green check: an attached phone-sized SwiftUI window retains2/6reps and shows a fully visible concise instruction with Resume camera primary and End set secondary, then the two-second clear-view instruction after acknowledgment. Both PNGs were visually inspected in private evidence. An earlier unattached blank capture is preserved as rejected evidence. These synthetic-callback renders verify UI presentation, not physical camera or Watch behavior.


## Independent-review correction

Review found that pause/resume while using manual or spoken manual input could acknowledge an earlier camera ambiguity. The fix preserves that pending acknowledgement until an explicit Resume with visual input selected; manual quantities and active time survive. Quick imported-video recovery retains its explicit Resume path. New public-API regressions failed first, then passed for quick reps, configured reps and configured seconds; the native spoken-entry path also passes.

Focused checks passed13XCTest and143Swift Testing cases, plus33affected native cases, with zero skips/failures. The native replay helper now loads the video track and orientation once through async asset APIs. Its bounded recheck of the existing ordinary-pushup control processed50frames and counted2/2; all sourcePTS, orientation, dimensions and raw trace bytes match the preserved earlier control exactly. This adds no independent source and does not replace the41primary results or their earlier compiled-source lineage. [Review correction receipt](review1-fix-receipt.json) records the exact current source/binary/config hashes and comparison. Existing AppIntents and simulator WatchConnectivity diagnostics remain visible for final review.
