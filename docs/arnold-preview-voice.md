# Arnold preview cue bank — 25 October 2026

This bank is for TestFlight preview only. Arnold is an operator-assigned label for a generated account voice, with no real-person identity claim. Five explicitly authorized synthesis requests produced five MP3s, 143 text characters total, with no retries. Every file decoded successfully through ffmpeg without playing aloud: 22,050 Hz, durations 1.58–1.91 seconds. Audio quality and iPhone playback remain pending. `Native/Resources/DemoVoice/arnold/manifest.json` records exact phrases, SHA-256 hashes, sanitized request receipts, response character-cost headers, account usage reads and decode evidence. No credentials or provider voice IDs are bundled.

The estimate before generation was 71.5 Flash credits for this bank (91.5 including a conservative 40-character prior attempt at the documented half-credit rate). The key's existing 100-credit cap and one-day expiry were never changed. Provider response `character-cost` headers were 6, 6, 6, 7, 7; immediate account-wide subscription reads were 4046 before and after. These are observations, not a final billing claim. The restricted key rejected a read-only model-list check with 401; no permissions were expanded. No Roger synthesis or history recovery was performed in this lane.

## Parent integration contract

- Merge existing steady-rhythm policy commit `27781a103cca15dae1c78ea152d75f48c1068587` and MP3 validator fix `843398fec876cf9fa3578118fa0801c3feb1e71b` (the lane has equivalent cherry-picks). The preview change adds `VoiceCue.reason` with a default of nil, and passes the decision reason through `CoachingVoiceBridge`. Existing callers stay source compatible; controller priority, expiry, cancellation, duplicate suppression and opt-in behavior are unchanged.
- Instantiate `DemoVoicePlayback` only when `DemoVoicePlayback.isAvailable(preview: isPreview, coach: selectedCoach)` is true: preview plus Arnold. All other selections continue using the existing configured/live/local route. The adapter has no network client, gateway, token, provider call or audio queue. Selection itself does not play audio.
- Add `Native/iOS/DemoVoicePlayback.swift` and `Tests/iOS/DemoVoicePlaybackTests.swift` to their native targets. Include `Native/Resources/DemoVoice` as a **folder reference**, preserving `DemoVoice/arnold/*.mp3` in the bundle. Parent owns the generator/project changes. The default loader deliberately requires this subdirectory, preventing accidental collisions with unrelated assets.
- `.steadyRhythm` plus `.pacing` alternates positive-1/positive-2; `.slowerRep` plus `.pacing` alternates slower-1/slower-2. Tracking, alignment, reached-target, rest reminders and unspecified reasons preserve the original local wording. The choice never uses text matching, zero rep count, missing tracking or inferred fatigue.
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

The nine new native cases exercise preview/Arnold routing, safe reason/priority selection, explicit recovery gating, local stop interruption, stale callbacks, original tracking/rest words, invalid timestamps, missing/rejected assets and controller cancellation. They use injected silent outputs. The ninth case checks the actual app-bundle resource paths and decodes all five files without calling play. Physical-device audible acceptance is still required.

References: [Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [Flash pricing](https://elevenlabs.io/blog/meet-flash), [current pricing range](https://elevenlabs.io/pricing).

## Executed checks

- `node --test server/test/voice.test.mjs`: 15 passed.
- `node --test server/test/demo-voice-assets.test.mjs`: 2 passed.
- `cd server && npm test`: 96 passed, 0 failed, 0 skipped.
- ffprobe plus full ffmpeg decode: all five clips passed silently.
- `git diff --check`: passed.

The first focused server launch lacked worktree dependencies and exited before tests; pointing the ignored node_modules link at the existing primary dependency installation resolved it. No native compiler, simulator, physical device or browser was used.
