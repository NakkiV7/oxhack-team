# CV event port — 25 October 2026

## Scope and plan

Start: `origin/main` at `196698be08b4f305e9a6ac34dc64df8ac71f47b0` in an isolated managed worktree. Review `origin/nakki-squat-model` at `3d90c3f56dc15a6e18a8890149b8fcb3dcd22a6d` and [issue #4's latest review](https://github.com/NakkiV7/oxhack-team/issues/4#issuecomment-6394267154).

1. Reproduce the historical browser syntax failure and check the latest exact head before making a fix.
2. Add behavior-first tests and a small dependency-free event adapter under `prototype/shared/`. Reuse the browser counters' accepted `counted`, `good`, `n`, `secs` and `faults` facts without importing their detector, thresholds, voice queue or servers.
3. Provide synthetic good/form-warning/slow/stop JSON replay cases and a scope/freshness selector. Preserve camera/replay/fixture provenance and explicit camera opt-in. No networking, persistence, inference or automatic playback.
4. Run offline checks, review the diff and open a small PR. Native detector/camera/TrainingStore/SDK wiring and release remain with the primary chat.

The module is an integration boundary and authored replay input, not a second native analyzer or a new audio owner. Native consumption remains a coordinated follow-up.

## Exact-head review

The historical `83b760c` squat module fails a network-free `node --check --input-type=module` with `SyntaxError: Identifier 'b' has already been declared` (extracted module line 417). The same extraction/parser check **passes** on latest `3d90c3f`; `hrtRender` now uses `bd` for bounds. The correction is already upstream, so this port adds no redundant syntax fix and imports none of that page.

The following are source findings at **`3d90c3f`**, not live exploit, persistence or browser acceptance results:

| Gate | Evidence and integration consequence |
| --- | --- |
| Request authorization | Squat `server.mjs:165–172,402,438–450` uses loopback restriction for coaching/telemetry but chooses identity from `?user=` or a default. These routes have no owner token/Origin guard. Loopback is a network boundary, not user authentication. Do not expose them as the native gateway. |
| Owner/session scope | `server.mjs:232–238` lists all squat workouts and accepts a workout ID for reports. `coach-service.mjs:20–30` reads that workout without an owner check, then saves a report for the selected user. `coach-store.mjs:112–125` reads by workout ID and updates reports on workout-ID conflict. Retain the existing owner-scoped gateway instead. |
| Explicit opt-in | UI `326–334` selects/prewarms the first voice on load. `server.mjs:159` migrates Tiger on configuration; UI `624–637` posts analysed observations automatically. Camera start itself **does** require a user action (`476–489`); that permission does not authorize LAN frame publication, cloud telemetry or synthesis. |
| Cancellation and delivery | UI `773–791` awaits cue/explanation work, then reads mutable `cl` and updates/speaks even if the attempt was cancelled or replaced. A rejected `cueReady` falls through to `cueFailed` and accesses `cl.cue.text`. Keep native generation/expiry/deduplication guards and recheck captured context after every await. Record delivered only on actual playback acceptance. |
| Replay and loss | UI `503–511,557–572` normally loops video while counter time uses `video.currentTime`; complete pose absence skips `counter.update`. Regressing media time and unfinished attempts across loss remain gates. Each replay pass/seek needs a new generation and movement reset; do not stitch a rep across either. |
| Voice and research | UI `317,350–365` retains discomfort-dismissive motivation, unexpired priority-3 counts and a non-preemptive queue. HRT/model/paper claims remain separate from native tracking. No training, artifact evaluation, accuracy benchmark, video provenance acceptance or clinical validation was performed here. |

Useful ideas retained: counted versus good-form facts stay distinct; slow ascent is an observed flag rather than inferred fatigue; stable attempt/session identity protects asynchronous boundaries. No voice, Tiger, coaching journey or research implementation is imported.

## Reusable local contract

`prototype/shared/cv-feedback.mjs` exports:

- `repFeedback({id, scope, exercise, source, atMs, record})`: accepts existing browser record fields `n`, `counted`, `good`, optional `secs` and `faults`. Strict booleans, positive counted rep numbers and finite positive durations; missing duration remains `null`. `good` describes the supplied counter's judgement, not independent form validation. Personal-rule versus baseline labels remain the caller's explicit choice; neither is overwritten.
- `stopFeedback({id, scope, exercise, source, atMs})`: an explicit discomfort signal, never a detector prediction. It contains no rep facts.
- `selectFeedback({events, context, nowMs})`: validates serialized events, admits only active matching owner/session/generation/exercise/source and prioritizes stop, form, pacing, good. Same-priority ties prefer the newest observation. Ordinary events expire after 3,000 ms; stop remains relevant only in its active matching generation. Camera events require literal `cameraOptIn: true`.

`scope` contains captured `ownerId`, `sessionId` and `generation` strings. These local labels are **not authentication**. IDs are bounded opaque strings; native adapters can use UUIDs as in the fixtures. `exercise` is `pushUp` or `squat`. `source` is `camera`, `replay` or `fixture`; browser `video` must be explicitly mapped to `replay`, never defaulted to camera. `atMs`, expiry and `nowMs` use the same caller-supplied session clock in milliseconds (not wall time). Stop/reset/source change/seek/loop and pause/resume must retire the old generation. The selector does not correct regressing media clocks or reset an analyzer.

The module performs no capture, fetch, playback, storage or provider work. Camera opt-in gates local selection; it does not grant camera permission or provider/cloud consent. Provider opt-in has no effect here. Any later provider adapter must use the existing authenticated, bounded gateway with separate explicit consent and no automatic paid retry/prewarm.

The selector is stateless and does not count reps, deduplicate delivery, run a queue or mark anything spoken. Keep native `RepCounter`, `CoachingPolicy` and `VoiceCuePlaybackController` authoritative. Rotate generation and call native cancellation on pause/stop/reset/source change; never restart playback from late completion. Feed accepted rep facts through the existing source-aware path once, rather than incrementing the native count from these fixtures.

| Output | Native handoff |
| --- | --- |
| `good` | Display accepted rep facts. No additional spoken cue is necessary. |
| `form-warning` | Candidate `.coaching(.form)` with finite expiry. |
| `slow` | Candidate `.coaching(.pacing)` only when the upstream counter supplied `slow ascent`; never a fatigue/health claim. |
| `stop` | Explicit user-discomfort `.coaching(.stop)`; preempts lower priority through the existing native controller. |

`prototype/shared/fixtures/cv-feedback.json` provides complete portable **authored synthetic** outputs for good, counted form-warning, slow, uncounted partial and stop. They contain no footage, landmarks, private identity or sensor readings. Fixtures intentionally span both exercises; filter by exercise rather than combining their counts. Replay fixtures in fixture context and preserve that source in every report. They are contract examples, not algorithm or accuracy evidence.

## Offline validation and primary handoff

Run from the PR worktree:

```sh
node --test prototype/shared/test/*.test.mjs prototype/pushup/test/pushup.test.mjs prototype/pushup/test/client-workout.test.mjs
node --check prototype/shared/cv-feedback.mjs
git diff --check
```

Observed: **52 tests passed, 0 failures** (11 adapter/fixture checks and 41 existing push-up checks); syntax and diff checks passed. Browser module parsing used exact Git blobs, regex extraction of `<script type="module">`, and Node's parser on stdin; it did not execute imports or page initialization. Historical parser failure and current parser success are separate from browser/device acceptance.

Native regression selectors prepared for the primary's coordinated queue:

```sh
swift test --filter 'VoiceCuePlaybackTests|countsOnlyAfterReturningFromBottomToTop|losesIncompleteRepWhenTrackingIsUnreliable|rejectsBrokenMovementContinuity|doesNotCountHalfRepsOrOneFrameAtDepth|resetDropsIncompleteRepButPreservesCount|measuresAnglesInImageSpaceRatherThanStretchedNormalizedSpace|measuresPushupBodyLineSeparatelyFromArmDepth'
```

For the existing native iOS test target, select `VoiceFeedbackTests` and `PoseDetectorTests`. The core rep/pose tests use top-level Swift Testing functions, rather than XCTest classes named after their files. No native/shared simulator, camera, model, provider, server or database acceptance was run by this lane. Native fixture decoding/wiring and actual UI/device checks remain with primary. No TestFlight upload or merge is included.
