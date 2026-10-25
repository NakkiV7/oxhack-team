# Arnold preview cue bank — 25 October 2026

## Local app acceptance — 25 October 2026

The current iOS build passed all 12 DemoVoicePlayback tests and the combined 39-case native run, including actual bundle decoding without playback, TrainingStore → policy → bridge → cached audio, cancellation/expiry and once-only completion. The local phone build 0.1 (6) contains all 12 MP3s and the Watch companion; installation and launch succeeded. Human audible confirmation remains separate and pending. No provider requests are required for preview Arnold cues. Recovery variants remain dormant until an explicit, separately implemented ended-set/fatigue resolver exists.


This bank is for TestFlight preview only. Arnold is an operator-assigned label for a generated account voice, with no real-person identity claim. The original five explicitly authorized requests produced five MP3s (143 characters). Omar then requested more variation: four additional requests produced four additional MP3s (48 characters), without retries. A later personality/completion request added three more clips (93 characters). The bank now contains twelve clips, 284 characters total. Every file decoded successfully through ffmpeg without playing aloud: 22,050 Hz, durations 0.84–2.74 seconds. Audio quality and iPhone playback remain pending. `Native/Resources/DemoVoice/arnold/manifest.json` records exact phrases, SHA-256 hashes, sanitized request receipts, response character-cost headers, account usage reads and decode evidence. No credentials or provider voice IDs are bundled.

The estimate before generation was 71.5 Flash credits for this bank (91.5 including a conservative 40-character prior attempt at the documented half-credit rate). The key's existing 100-credit cap and one-day expiry were never changed. Provider response `character-cost` headers were 6, 6, 6, 7, 7; immediate account-wide subscription reads were 4046 before and after. These are observations, not a final billing claim. The restricted key rejected a read-only model-list check with 401; no permissions were expanded. No Roger synthesis or history recovery was performed in this lane.

## Parent integration contract

- Merge existing steady-rhythm policy commit `27781a103cca15dae1c78ea152d75f48c1068587` and MP3 validator fix `843398fec876cf9fa3578118fa0801c3feb1e71b` (the lane has equivalent cherry-picks). The preview change adds `VoiceCue.reason` with a default of nil, and passes the decision reason through `CoachingVoiceBridge`. Existing callers stay source compatible; controller priority, expiry, cancellation, duplicate suppression and opt-in behavior are unchanged.
- Instantiate `DemoVoicePlayback` only when `DemoVoicePlayback.isAvailable(preview: isPreview, coach: selectedCoach)` is true: preview plus Arnold. All other selections continue using the existing configured/live/local route. The adapter has no network client, gateway, token, provider call or audio queue. Selection itself does not play audio.
- Add `Native/iOS/DemoVoicePlayback.swift` and `Tests/iOS/DemoVoicePlaybackTests.swift` to their native targets. Include `Native/Resources/DemoVoice` as a **folder reference**, preserving `DemoVoice/arnold/*.mp3` in the bundle. Parent owns the generator/project changes. The default loader deliberately requires this subdirectory, preventing accidental collisions with unrelated assets.
- `.steadyRhythm` plus `.pacing` rotates positive-1 through positive-5; `.slowerRep` plus `.pacing` rotates slower-1 through slower-4. Explicit recovery rotates recovery/recovery-2. Each category advances independently; interleaved workout reasons cannot make a category repeat the same clip. Tracking, alignment, reached-target, rest reminders and unspecified reasons preserve the original local wording. The choice never uses text matching, zero rep count, missing tracking or inferred fatigue.
- `recoveryReason:` is an injected resolver returning `DemoVoiceRecoveryReason.endedSet` or `.fatigue` **only for the exact ID of an actual explicit ended-set/fatigue event**. Default is nil. Only a `.rest` cue with nil ordinary coaching reason can select recovery. Do not derive recovery from tracking gaps, elapsed rest, zero reps or lack of progress. Until an actual event is supplied the recovery asset stays dormant.
- Stop priority or discomfort reason always interrupts cached audio and speaks the original local cue immediately. No cached encouragement substitutes for safety words. Missing/invalid audio completes without retry, provider request or claiming playback.
- UI should identify Arnold as “Preview · bundled cues · offline” when applicable; David stays local/configured until a bank exists. Keep live integration setup/privacy docs in `docs/voice-feedback.md`; this bank does not verify live synthesis on the deployed gateway.

## Native verification handoff

Tests were written before the adapter and recovery contract. Native compiler/build execution was prohibited for this delegated lane, so these fixtures are **unrun** here; no native RED/GREEN claim is made. Parent should run:

```text
SpottrTests/DemoVoicePlaybackTests
SpottrTests/VoiceCuePlaybackTests (if in native target; otherwise Core SwiftPM)
SpottrTests/LocalVoicePlaybackTests
SpottrTests/RemoteVoicePlaybackTests
SpottrTests/VoiceFeedbackTests
```

The twelve native cases exercise preview/Arnold routing, safe reason/priority selection, explicit recovery gating, local stop interruption, stale callbacks, original tracking/rest words, invalid timestamps, missing/rejected assets and controller cancellation. They use injected silent outputs. The bundle case checks the actual app-bundle resource paths and decodes all twelve files without calling play. Physical-device audible acceptance is still required.

References: [Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [Flash pricing](https://elevenlabs.io/blog/meet-flash), [current pricing range](https://elevenlabs.io/pricing).

## Executed checks

- `node --test server/test/voice.test.mjs`: 15 passed.
- `node --test server/test/demo-voice-assets.test.mjs`: 2 passed.
- `cd server && npm test`: 96 passed, 0 failed, 0 skipped.
- ffprobe plus full ffmpeg decode: all five clips passed silently.
- `git diff --check`: passed.

The first focused server launch lacked worktree dependencies and exited before tests; pointing the ignored node_modules link at the existing primary dependency installation resolved it. No native compiler, simulator, physical device or browser was used.

## Additional variation and simulation — user-authorized follow-up

The follow-up preflight refreshed subscription usage to 4078 (41 above the original 4037 baseline). Four phrases totaling 48 characters were bounded at a conservative one credit per new character: 41 + 48 = 89, below the unchanged 100-credit cap. The requests returned 200 and reported character-cost headers 3, 2, 4, 2. Immediate post-request account usage remained 4078; this is not final billing evidence. No settings, expiry, permissions or account plan changed. The original five-clip receipt stays intact; `manifest.json.expansions` records the new authorization, preflight and receipts.

The asset test first failed as expected (five clips present, nine expected), then passed after generation and full silent decode of all nine files. Independent category rotation and a multi-event workout simulation were added to `SpottrTests/DemoVoicePlaybackTests`. The simulation feeds the real `VoiceCuePlaybackController` and `DemoVoicePlayback`: opt-in consumes old events, a fresh pacing event starts once, duplicate/expired/lower-priority events do not start, discomfort interrupts with original local speech, stale callbacks do not clear stop, and pause/mute/generation changes cancel audio. Injected silent outputs record actual play calls; this does not establish audible speaker output.

Omar explicitly approved coordinating native simulation with the main Spottr chat, which retains ownership of simulator/compiler/project changes. Execution results will be recorded after that lane runs the updated fixtures.

Follow-up executed checks: all 96 server tests passed against the nine-clip bank, and isolated `swift test --filter VoiceCuePlaybackTests` passed 8/8. These Core tests exercise the actual shared controller; the native DemoVoicePlayback/TrainingStore/app-bundle fixtures remain with the main compiler lane.

### Executed adapter simulation on macOS

The permitted isolated SwiftPM harness ran the actual current `DemoVoicePlayback` and shared `VoiceCuePlaybackController`: **11 tests passed, zero failures**, 0.927 seconds after a 147-second build, on arm64 macOS. All nine MP3s decoded through AVAudioPlayer without `play()`. The actual adapter was copied unchanged apart from adding the Core module import. Real boundary declarations were extracted verbatim from the primary remote adapter; the local-driver host copy guards the iOS-only audio-session assignment; test resources use Bundle.module instead of Bundle.main. Production iOS sources were not altered for the harness.

Re-run this preserved local harness with `swift test --package-path .local/voice-simulation-harness`. Its local `acceptance.json` records source hashes and exact adaptations. This establishes the real adapter/controller behavior with silent outputs and actual media decoding. It does not establish iOS app-bundle packaging, TrainingStore routing or audible iPhone output; the main chat retains those integration checks.

## Personality and completed-workout sign-off — 25 October 2026

Omar explicitly requested more personality, longer encouragement and “We'll be back” on workout completion. Three further successful requests added:

- `completion`: “We'll be back.” — 0.975 seconds.
- `positive-5`: “Strong work. One controlled rep at a time. You've got it.” — 2.740 seconds.
- `slower-4`: “Easy. Stay in control.” — 1.393 seconds.

The bank now holds twelve files / 284 characters, with five positive and four slower variants, two recovery variants and one completion sign-off. The new batch was 93 characters, estimated46.5 Flash credits. Refreshed observed usage before was4089 versus original4037; estimated52 +46.5 =98.5 stayed within the unchanged100-credit key cap. Actual response character-cost headers were3/13/5; immediate post-call account usage remained4089. No retries, permission expansion, cap/expiry change or billing-finality claim. Every new file fully decoded silently at22050Hz. No audible acceptance is claimed.

### Minimal completion integration contract

`CoachingReason.workoutCompleted` is an explicit lifecycle reason; the coaching policy does not infer or emit it from rep counts, missed tracking, fatigue, a target cue or elapsed rest. `VoiceCuePlaybackController` accepts this reason **only** with `.coaching(.rest)` in `.finished`; ordinary coaching/chat remain blocked in `.finished`, and completion is blocked in active/rest/paused/idle phases. Completion interrupts ordinary workout audio, but cannot interrupt an active stop. It retains the existing ID/generation, expiry, opt-in and duplicate gates. Muted or expired completion events do not replay on later enabling.

Root owns actual `TrainingStore` event emission. Emit a single stable event only when an actual nonempty workout finishes with feedback already enabled, app active and no discomfort stop. Cancel preceding ordinary coaching first; bind the new event to the post-finish session/generation and retain it until its original deadline. Reopening a report, repeated finish calls, importing history, canceled/empty sessions and enabling feedback after finishing must not create a new event. Update `Palette.coaching` to handle the new enum case. `RemoteVoicePlayback` may route this reason through the injected preview bank only; it must never request completion synthesis from the live gateway. The gateway's existing coaching-only contract stays intact.

The controller tests first failed to compile for the missing reason, then failed behaviorally because the previous controller suppressed finished speech and allowed the reason during active/rest. Three completion controller regressions and one adapter simulation cover the corrected contract. Native iOS store/resource verification remains coordinated with the main chat.

Personality/completion acceptance: `swift test --filter VoiceCuePlaybackTests` passed11/11 after the observed compile and behavioral REDs. The isolated actual-adapter SwiftPM harness passed12/12, including completed-workout once/mute, independent5positive/4slower rotation and AVAudioPlayer decode of all12files. Asset/provenance tests passed2/2 after9-versus12RED. The iOS TrainingStore finish emission and app-resource packaging remain with the main integration lane.
