# Arnold preview cue bank — 25 October 2026

This bank is for TestFlight preview only. Arnold is an operator-assigned label for a generated account voice, with no real-person identity claim. The original five explicitly authorized requests produced five MP3s (143 characters). Omar then requested more variation: four additional requests produced four additional MP3s (48 characters), without retries. The bank now contains nine clips, 191 characters total. Every file decoded successfully through ffmpeg without playing aloud: 22,050 Hz, durations 0.84–1.91 seconds. Audio quality and iPhone playback remain pending. `Native/Resources/DemoVoice/arnold/manifest.json` records exact phrases, SHA-256 hashes, sanitized request receipts, response character-cost headers, account usage reads and decode evidence. No credentials or provider voice IDs are bundled.

The estimate before generation was 71.5 Flash credits for this bank (91.5 including a conservative 40-character prior attempt at the documented half-credit rate). The key's existing 100-credit cap and one-day expiry were never changed. Provider response `character-cost` headers were 6, 6, 6, 7, 7; immediate account-wide subscription reads were 4046 before and after. These are observations, not a final billing claim. The restricted key rejected a read-only model-list check with 401; no permissions were expanded. No Roger synthesis or history recovery was performed in this lane.

## Parent integration contract

- Merge existing steady-rhythm policy commit `27781a103cca15dae1c78ea152d75f48c1068587` and MP3 validator fix `843398fec876cf9fa3578118fa0801c3feb1e71b` (the lane has equivalent cherry-picks). The preview change adds `VoiceCue.reason` with a default of nil, and passes the decision reason through `CoachingVoiceBridge`. Existing callers stay source compatible; controller priority, expiry, cancellation, duplicate suppression and opt-in behavior are unchanged.
- Instantiate `DemoVoicePlayback` only when `DemoVoicePlayback.isAvailable(preview: isPreview, coach: selectedCoach)` is true: preview plus Arnold. All other selections continue using the existing configured/live/local route. The adapter has no network client, gateway, token, provider call or audio queue. Selection itself does not play audio.
- Add `Native/iOS/DemoVoicePlayback.swift` and `Tests/iOS/DemoVoicePlaybackTests.swift` to their native targets. Include `Native/Resources/DemoVoice` as a **folder reference**, preserving `DemoVoice/arnold/*.mp3` in the bundle. Parent owns the generator/project changes. The default loader deliberately requires this subdirectory, preventing accidental collisions with unrelated assets.
- `.steadyRhythm` plus `.pacing` rotates positive-1 through positive-4; `.slowerRep` plus `.pacing` rotates slower-1 through slower-3. Explicit recovery rotates recovery/recovery-2. Each category advances independently; interleaved workout reasons cannot make a category repeat the same clip. Tracking, alignment, reached-target, rest reminders and unspecified reasons preserve the original local wording. The choice never uses text matching, zero rep count, missing tracking or inferred fatigue.
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

The eleven native cases exercise preview/Arnold routing, safe reason/priority selection, explicit recovery gating, local stop interruption, stale callbacks, original tracking/rest words, invalid timestamps, missing/rejected assets and controller cancellation. They use injected silent outputs. The bundle case checks the actual app-bundle resource paths and decodes all nine files without calling play. Physical-device audible acceptance is still required.

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
