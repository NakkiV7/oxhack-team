# Consistent audio and expanded on-device movement tracking

## Intent and authority

Omar wants Spottr to behave like a finished workout app: speech starts and ends consistently with actions, ordinary audio finishes naturally, and as many useful levelled exercises as possible have real computer-vision counting. This continues his existing instruction to implement improvements autonomously. Once ALL changes and checks are complete, install the completed app on his physical iPhone. Do not install an intermediate build.

## Fixed constraints

- Native iPhone/Watch app, Swift, existing MediaPipe Full pose model and deterministic on-device geometry/state machines. No runtime paid AI or tokens, no new model training/HPC work.
- Preserve existing saved exercise IDs/units, counts, sets, histories, manual input and input switching. Do not invent observations across missing frames.
- No human-style faces. Keep the existing dark stick figures, mint joints and abstract coach icons.
- Do not use Chrome. Reuse existing simulators only; shared iPhone BF27AFBA-FF1E-4484-A3BD-42916CEB1170. Coordinate simulator use, preserve its data/apps, never create or erase one.
- Bulk builds, recordings, logs and receipts on /Volumes/Spottr Development (Extreme SSD-backed). Preserve build17 and Native/Vendor content and metadata, original untracked evidence and earlier releases.
- Test first using /Users/scsoc/.claude/TDD.md. Follow /Users/scsoc/.claude/AI.md for CV implementation/validation. Distinguish algorithm regression checks from physical accuracy acceptance.

## Audio contract

A cue's expiry limits when it may START, not how much of an already-playing sentence can be heard. Ordinary nil/repeated/cleared warnings and later low/equal-priority coaching must not cut an active recording. Never queue stale ordinary warnings. An urgent form cue may replace lower-priority encouragement; stop/pain interrupts immediately. Explicit mute, pause, abandoning/restarting a workout, input/coach change and app inactivity cancel audio consistently. Ending a set is a natural transition: finish the current sentence before a bounded recovery/closing cue, and do not restart a session-start line on each resume/input change. Finishing a workout permits its actual completion line once, with no overlap, duplicate callbacks or expired deferred speech. Starting a new set/session invalidates prior context. Stop must never wait behind ordinary speech. OS interruptions cannot leave the voice controller permanently busy; stale voice must not restart on return.

Preserve the 243 current bundled MP3s and local voice option. Fixed tracking text must suit front/side views and timed exercises: say progress/movement, not only reps/side view. Regenerate only necessary fixed lines within the existing authorised one-day 10,000-credit key cap (3,658 already used), with attempt receipts and no automatic POST retry. Do not ship the key. If authoring access is no longer valid, keep usable generic existing clips and do not silently substitute robotic speech for normal Maya/Leo coaching.

## Camera contract and catalogue

Use exercise-specific measurements, orientation checks, confidence, hysteresis, bounded gap recovery and limb continuity. Count a completed cycle only after observed start/range/return; do not reset saved quantities when tracking disappears. Do not fuse limbs, count jitter, static poses, wrong orientation, teleports or an unobserved full cycle. Preserve witnessed depth across a brief loss; a clear brief bottom should not require an artificially long pause. Tempo/pause prescriptions require observed timing rather than giving credit for invisible time. Report derived progress signals honestly; do not describe a proxy as a measured joint angle.

Existing manual catalogue entries should gain tracking where landmarks support it: bridges, lunges/split and assisted squats, alternating dead bugs/bird dogs, step jacks, mountain climbers, calf raises, seated knee extensions and wide/diamond push-up cycles. Hand placement, wall/chair contact, load and clinical form are not established merely by counting. Cat-cow stays a manual repetition exercise because shoulder/hip endpoints do not reliably measure spinal articulation. Keep its guide and practice fully available.

Add these 21 levelled entries without changing older IDs or units: quarterSquat, sitToStand, narrowSquat, tempoHalfSquat, pausedHalfSquat, forwardLunge, lateralLunge, supportedSplitSquat, standingKneeRaise, seatedMarch, standingHipAbduction, standingHipExtension, kneePlank, highPlank, wallPlank, kneeSidePlank, tandemBalance, frontArmRaise, lateralArmRaise, standingBicepsCurl, wallSlide. Target: 53 catalogue entries, up to 52 with camera support, subject to observable movement gates. Camera support means counting or observed timing for the selected movement, not an exercise classifier or clinical validation. Each entry needs levels, realistic starting targets, setup/support instructions, the correct camera view and matching faceless art. Existing skill-path chains/progress remain stable; variations are available through the exercise library.

Timed camera exercises require a separate observed-time accumulator: plank variants, wall sit, single-leg/tandem balance and a half-kneeling hip-flexor position qualify only while visible posture checks pass. High knees keeps its existing seconds unit and accumulates observed ongoing motion, including a short visible transition between lifts; standing idle must not earn activity time. Missing/invalid frames, long sampling gaps and pause accrue no observed seconds. Active session time remains distinct from observed exercise quantity. Switching camera/manual preserves quantity and labels mixed/manual quantity honestly. Historical timer records continue decoding unchanged.

## Integration and acceptance

The native capture pipeline must select the right tracker, preserve source generations, show the important joints for that movement, and expose meaningful feedback/quantity in the workout, reports and exports. Camera timings must not be called rep counts or AI-verified steps. Quick rep workouts exclude timed-only identities; timed exercises are available through configured workouts. No camera, microphone or Health readings are fabricated. Levelled guides use useful movement-specific stick figures rather than a squat/push-up fallback.

Regression coverage must include all profile families and mirrored limbs; portrait/landscape coordinates; incorrect orientation; partial/low-confidence poses; jitter/outliers; pauses; time rollback/duplicates/gaps; short visibility losses; timing prescriptions; alternating sides; source/coach changes; timed quantity/provenance; ordinary speech completion and action cancellation; recovery/completion once; OS interruptions and stale callbacks. Run complete core and gateway suites, relevant/full native checks with existing documented StoreKit limits, and selected UI checks on the existing simulator. Re-review significant fixes, audit the signed phone/Watch bundle and preserve evidence. Finally install the finished signed app on Omar's connected iPhone, preserving app data. Report any device trust/unlock/developer-mode blocker precisely if one occurs; do not create a simulator as a fallback.

## Builder choices

Exact geometry thresholds, profile decomposition, smoothing and new test fixture layout are implementation decisions. Make them explicit and regression-tested. Keep per-frame work bounded for 33 landmarks. Reuse current dependencies and resource folders. Record any reduction in the 52-camera target with its concrete observability reason. Do not mark a movement supported with a generic squat/elbow counter merely to reach the target.
