# Camera execution inside configured workouts

Approved design for issue #19, 24 October 2026. Core and native routing are implemented with synthetic tests, and the configured iPhone UI flow passed. Watch instruction source behavior is verified; final Watch target compilation and physical acceptance remain separate. Existing manual/timed plans and the legacy fixed camera workout stay available. See [custom-workouts.md](custom-workouts.md) for current usage and evidence.

## User behavior

Only the exact catalogue IDs `pushup` and `squat` offer **Manual**, **iPhone camera** and **Pi side camera**. Variations, other rep exercises and holds keep their existing manual/timer behavior. Every queued set starts in Manual; selecting a camera is explicit and does not open it. The existing Start action starts that set and its selected camera. Selecting a plan, entering recovery, reaching a target or advancing the queue never starts capture or ends a set automatically.

The active camera screen shows the existing preview/pose overlay, observed count, planned target, local form/coaching text and pause/end controls. A zero count means zero CV-observed reps, not proof that the person did no exercise. Ending a started camera set may explicitly retain zero observed reps; finishing the workout still drops an unended set. Targets never fill the count.

Changing between Manual, phone and Pi after Start requires a confirmation that discards the current unsaved count, partial movement, timings and active clock. The new mode returns to preparation and needs another Start. Keep already completed sets. Keep the rest-before interval measured at the original first Start; do not relabel discarded active work as rest. Before the first Start, normal next-set preparation remains included in rest. There is no live video-replay mode in configured plans.

Pause/failure stops capture, clears preview/pose, invalidates generation and retains completed reps while dropping partial movement. Resume is explicit, uses a new generation and restarts only the selected camera. Permission denial, unavailable camera and Pi transport failure leave a visible paused state with confirmed Manual fallback. End, discomfort, next set, finish, new plan and a new legacy workout stop both workers and clear input/cues. Unsupported mode selection leaves the current state unchanged.

## State and persistence

`ConfigurableSession` owns current source, optional `RepCounter`, cue, observed rep durations and generation. An exact `Exercise(rawValue: current.exerciseID)` mapping gates camera support; it does not expand the catalogue or claim other adapters. `consume(sample:generation:)` requires `.camera`, active phase, `hasStarted`, matching generation and a supported exercise. It delegates counting/continuity to the existing `RepCounter`; `PoseGeometry` remains the only pose-to-measurement adapter. Preparation, paused, manual, rest and stale callbacks cannot count. No changes to thresholds, full-cycle rules or target-based completion.

Expose a single current actual-rep accessor: manual input remains optional; camera count comes from the counter. Manual entry cannot modify a camera set. `canEndSet`, stop reason, snapshot and save use this accessor. Preserve current actual active time, ordered queue metadata, discomfort latch and stable session/set identities.

Keep all configured completions in `SessionRecord.loggedSets` in queue order. Camera sets use the existing `source: .camera`, `seconds: 0`, actual count, target/number, active/rest timing and `quantityOrigin: nil`. Phone and Pi share camera provenance; transport choice is live native state, not a new physiological source. Manual sets retain `.selfReport` and holds `.activeTimer`.

Add only **`LoggedSet.repDurations: [Double]? = nil`** to persistent records. Populate it from completed observed camera cycles; never derive it from total set time or manual entries. Old records continue decoding with nil. Project it through `WorkoutReport` using the existing finite 0.6–15-second/count-matching timing rules. Existing report source badges, Coach facts and skill progression already understand `.camera` logged sets. Update the configured finished view so it does not label camera sets as manual. Do not split camera records into the legacy `sets` array, which would reorder mixed reports.

The app must retain actual counts rather than clamp them to a sync limit. The existing server caps observed reps/timing arrays at 200; exceeding that remains an explicit sync validation failure with the local record preserved, not silent truncation or auto-ending. Increasing that established limit is outside this change.

## Native routing and coaching

`TrainingStore` gets one small current tracking/context projection for the selected legacy or configured run: ID, generation, phase, supported exercise, source, started state and actual count. Use it in both workers' frame/state guards; additionally require the currently selected phone/Pi transport. Do not add another session engine or worker. Keep the legacy route's behavior and video source intact; reject legacy camera/video entry points while a configured run is present.

A native `ConfiguredInput` choice distinguishes Manual/phone/Pi while Core records only manual/camera provenance. Keep the choice separate from `usingSecondaryCamera`, which describes active transport and is cleared during teardown. `beginConfiguredSet` starts capture after the Core Begin succeeds. Source changes and all stopping transitions rotate/invalidate Core generation before old callbacks can publish. Pi cleanup still uses its existing lease-aware pending-start teardown.

Reuse `CoachingPolicy` by projecting an eligible configured camera set into the existing `CoachingInput`: configured ID/generation, exact base exercise, observed count/last duration/cue, approved current target, actual rest and that run's received Watch telemetry. Manual/unsupported steps cancel camera coaching; no fake substitute exercise is introduced. Discomfort supersedes ordinary camera speech even when no valid rep was completed. Profile goals remain expressed by the approved plan and existing explicit Coach context, not new physical-capacity rules.

Generalize `CoachingVoiceBridge` to accept the existing `VoiceCueContext` instead of requiring a `TrainingSession`; preserve the legacy convenience initializer/call where useful. Show the explicit Voice toggle in configured camera sessions and reset opt-in for a new plan. Preserve foreground/mute/expiry/priority behavior. Seed camera rhythm from both legacy camera sets and configured camera logged sets through the validated report projection; exclude manual, replay, form/discomfort and invalid timings. This uses the same policy, not a second cue engine.

## Watch and backend coordination

`CompanionSnapshot` uses configured actual count/cue and existing generation/command checks. Add optional `source` to `ConfiguredCompanionSnapshot`, with absent source meaning legacy manual behavior. Keep `enteredReps` for actual manual entry only. The Watch's small quantity/instruction adapter must show `snapshot.reps` and camera cue for camera source rather than an empty manual field and “enter actual reps” prompt. Watch controls never choose camera mode or supply counts; Start only executes the input already explicitly selected on the phone.

The backend owner implemented and tested the optional timing contract before sync acceptance. `server/src/tiger-contracts.mjs` needs an optional nullable bounded duration array on logged sets: only exact base pushup/squat, source camera, reps unit, zero seconds, no manual quantity origin; every duration finite and 0.6–15 seconds, array count matching actual reps, maximum 200. No SQL migration is needed because the immutable workout snapshot is JSONB. Add offline round-trip/replay/hash and invalid-source/timing tests. Existing manual/timer and legacy tracked-set contracts must stay green. This agent does not edit backend files without a separate assignment.

## Implementation files

Main implementation and tests:

- `Shared/Core/ConfigurableSession.swift`, `LoggedWorkout.swift`, `WorkoutReports.swift`, `Companion.swift`.
- `Native/iOS/TrainingStore.swift`, `ConfiguredSessionViews.swift`.
- Existing `Tests/Core/ConfigurableSessionTests.swift`, `WorkoutReportTests.swift`, `CompanionTests.swift`; existing `Tests/iOS/ConfiguredWorkoutFlowTests.swift` and `SecondaryCameraTrainingStoreTests.swift`.

Additional approved boundaries:

- `Shared/Core/CoachingPolicy.swift` and its tests for configured camera history seeding.
- `Native/iOS/CoachingVoiceBridge.swift` and existing coaching/voice tests for shared identity.
- `Native/Watch/SpottrWatchApp.swift` for the source-aware count/instruction adapter; no recorder/sensor changes.
- The existing CoachFlow UI test file for the mode/confirmation/manual-fallback flow; the integration owner handles project generation/builds.
- Backend contracts/tests owned by the gateway agent; `docs/custom-workouts.md` updated after implementation.

No PoseDetector/RepCounter/PoseGeometry threshold edits, new provider calls, model downloads, physical-device setup, signing, project generation or builds by this agent.

## RED sequence before production changes

1. **Core observed behavior:** base squat/pushup configured set counts the existing synthetic full-cycle samples, retains exact timings/source/order, and remains active after reaching/exceeding target until explicit End. Missing frames, unstarted/manual/hold/unsupported exercise and stale generation never count. Confirmed source reset discards only the current unsaved work and preserves completed rows/rest semantics.
2. **Continuity and persistence:** pause/resume and source/set/exercise transitions reject partial/stale cycles; finish/discomfort never invent a count; mixed camera→manual→hold records reopen with correct sources, timings, order and rest. Legacy records with no timing field still decode, and invalid camera timing does not produce report pacing.
3. **Native ownership:** inject the existing `VisionWorker` (default preserved) and fake Pi worker/client, with no real camera/network. Deliver valid frames from only the chosen worker; old state/frame callbacks after pause/end/reset/new plan/finish cannot alter count, image, cue or phase. Permission failure and Pi loss pause and stop, then require explicit resume/fallback. Existing legacy camera, replay and Pi transitions remain green.
4. **Coaching/Watch:** configured camera events carry configured identity/target/telemetry; stop interrupts form/pacing; mute/app inactivity/new plan suppress stale audio. Manual/replay never produce personal camera coaching. Snapshot round-trip shows observed counts and safe commands; absent source remains compatible. No real audio or biometric samples in routine tests.
5. **UI and sync:** actual saved mixed plan presents only supported camera choices; selecting a mode does not capture; cancellation of the reset dialog preserves work; confirmation resets to preparation; fallback allows manual completion and report/history reopening. Backend synthetic round-trip and invalid timing/source tests pass before claiming sync compatibility.

Start by adding the first two Core behavior tests and asking the integration owner to observe RED, then implement that slice. Proceed through native/UI/contract RED→GREEN in the same way. Synthetic count fixtures prove state-machine wiring, not physical counting accuracy. Actual phone/Pi sustained capture and audible acceptance remain distinct checks; the known Pi USB disconnect is not fixed by this feature.

### Isolated UI fixture procedure

`CoachFlowTests.testConfiguredCameraChoiceNeedsResetConfirmationAndOtherExercisesRemainManual` passes synthetic squat + plank JSON in `SPOTTR_APPROVED_PLAN_FIXTURE` with a fresh UUID `SPOTTR_DATA_NAMESPACE`. The fixture is intended for a DEBUG-only loader: require a valid UUID namespace, decode the normal `CoachSavedPlan` type, and use it only in memory. Missing/invalid namespaces and malformed JSON use the existing stored-plan path. Release builds exclude the fixture branch. The test must never seed, overwrite or clear the user's `coach.approvedPlan` preference.

The case confirms that manual count survives Cancel, confirmed source reset returns to preparation with zero camera observations and voice off, switching back to Manual requires Start again, and the following plank offers no camera choice. It never starts either camera or calls Gemini. It saves only explicitly ended self-reported reps in the isolated history namespace and drops the unstarted hold. First observe missing Start saved workout before adding the fixture loader; then observe the missing input menu before adding the production controls.
