# Voice feedback

Tracked camera workouts have an explicit **Voice feedback** toggle. It starts off for every new workout. Turning it on speaks only newly issued coaching events; existing text is not read back. Muting, pausing, ending a set, changing its generation, or leaving the workout cancels speech immediately.

Arnold is now the initial coach choice. It uses seventeen bundled ElevenLabs recordings for typed workout cues, including form, tracking, pacing, rest, completion and stop warnings. Local remains an explicit Apple speech choice; David remains an optional gateway voice. See [the current Arnold bank and acceptance](arnold-preview-voice.md).

Stop cues interrupt ordinary coaching. Arnold's stop recording is immediately available offline; if that recording cannot play, the local speech driver delivers the warning. Lower priority speech is dropped rather than queued, and expired or repeated events do not replay. Feedback does not read chat replies or historical reports. It remains off until enabled for a workout.

## Acceptance

Offline controller tests use fake playback. Native tests use fake playback and a fake speech synthesizer, so they do not produce audio. They cover opt-in behavior, cancellation, event priority, expiry, session identity, and stale completion callbacks.

On 24 October 2026, the eight voice controller tests passed after observed RED failures for missing contracts, cancellation/priority/expiry behavior, and malformed text/time. The full SwiftPM core suite also passed. Following a separate lifecycle compile RED, the parent task ran all seven native voice tests successfully: two local-driver tests and five TrainingStore tests, including background cancellation and blocked rest coaching, in 15.5 seconds, with no warnings. Rest timing continues while the scene is nonactive; coaching and speech wait for the foreground. These checks verify fake playback behavior; audible acceptance and actual audio-route interruptions remain pending.

Audible acceptance requires an iPhone or simulator check: start a tracked workout, confirm voice is off, enable it, cause a new tracking or alignment cue, and confirm it speaks once. Pause or mute during speech and confirm immediate silence. Start another workout and confirm the toggle is off again. Replay/video input must not speak personal coaching. Verify music and other app audio behavior on a physical iPhone before describing audio coexistence as device-tested.

Configured discomfort regression (24 October): three native tests first failed because manual rep/hold stops had no coaching event. After the focused correction, 23 native coaching/voice/configured-flow checks passed in 27.1 seconds on the existing Musalli-Test simulator. The fixtures verify one stop event/speech request, stable context, no ordinary manual cues, no invented completed work, blocked continuation, repeated-stop idempotence and no replay after backgrounding. Fake playback does not establish audible device behavior. Result: `test_sim_2026-10-24T22-54-43-869Z_pid35007_a4052087.xcresult`.

## Optional ElevenLabs gateway adapter — 25 October 2026

The gateway now implements authenticated `GET /v1/voices` and `POST /v1/voice`, with mocked-provider acceptance only. No paid synthesis, account voice availability or audible output has been verified. Native transport/playback behavior has offline test acceptance. Arnold is initially available offline; David requires an explicit configured selection before cue text can be sent.

Configure these server-only values privately, then restart the gateway deliberately:

```text
ELEVENLABS_API_KEY=<existing account key>
ELEVENLABS_DAVID_VOICE_ID=<account-enabled voice ID>
ELEVENLABS_ARNOLD_VOICE_ID=<account-enabled voice ID>
# Optional, separately configured shouting voice; never substituted if missing.
ELEVENLABS_DAVID_INTENSE_VOICE_ID=<account-enabled intense voice ID>
ELEVENLABS_TIMEOUT_MS=5000
```

There are no default provider voice IDs. **David** and **Arnold** are operator-assigned display names, not claims about a person's identity, a voice clone or current account availability. Discovery returns only configured aliases, for example `{ "voices": [{"id":"david","name":"David"}], "availability":"configured_not_verified" }`. David additionally advertises `tones:["calm","intense"]` only when his separate intense ID is configured. Discovery never lists the account or calls ElevenLabs. An absent/invalid selected voice or intense ID returns 503; no fallback voice is substituted. `/health` reports configuration only.

`POST /v1/voice` accepts exactly this JSON shape:

```json
{
  "generationID": "UUID",
  "sessionID": "UUID",
  "cueID": "UUID",
  "playbackToken": "fresh request UUID",
  "voice": "david",
  "text": "Current deterministic coaching text",
  "priority": "form",
  "expiresAt": "2026-10-24T21:30:06.000Z"
}
```

Both endpoints require the existing gateway Bearer token. Provider credentials and provider voice IDs stay on the server. The POST body is capped at 8 KiB: all four IDs must be UUIDs; `voice` is `david` or `arnold`; `priority` is `form`, `pacing` or `rest`; text is trimmed, nonblank, at most 500 characters and contains no control characters. Unknown fields are rejected. `expiresAt` is canonical UTC with milliseconds, strictly future and no more than six seconds away. Stop and chat priorities are rejected before synthesis; stop feedback remains immediate local playback. Uptime values must never be sent as wall-clock timestamps. The client supplies its original deadline once; server latency cannot extend it.

Optional `tone` accepts `calm` or `intense`; omitted tone keeps the original calm request/response shape. Intense is accepted only for David pacing cues and uses his separate intense provider ID/cache identity. Form, rest, stop, Arnold-intense and unknown tones are rejected before paid synthesis. Tone does not change priority, expiry, safety decisions or workout control.

A successful JSON response echoes the validated request fields, including unchanged identity/expiry, plus `mimeType: "audio/mpeg"` and `audioBase64`. The opaque playback token identifies one pending request; it is not authentication. The Native client accepts/decodes audio only while all IDs, token, original expiry, preference and current workout phase still match. Muting, pausing, changing generation or leaving cancels transport and playback immediately. Server request disconnect aborts synthesis. Late responses return `voice_expired`; neither retries nor another synthesis request happen automatically.

The provider request contains only text and fixed `model_id: "eleven_flash_v2_5"`, using `mp3_22050_32`, a fixed HTTPS host and no redirects. Response MIME must be `audio/mpeg`; audio is capped at 256 KiB and checked for an initial complete MPEG-2 Layer III frame at 22.05 kHz/32 kbps, with an optional ID3 prefix. This is a format/header check, not a full media decode or audible-quality test. The response JSON is therefore bounded to roughly 351 KiB. The entire fetch/body read has a deadline of the smaller of the original expiry and configured 1–6000 ms timeout (default 5000 ms), also bounded by owner-demo expiry. Failures are sanitized; raw provider bodies, text and keys are not logged.

Only one new voice synthesis can be active per gateway. Other cache misses return `voice_busy` without queuing. Successful clips may be reused for ten minutes by actual provider voice ID/model/text hash, with at most 32 entries and 4 MiB total audio. The cache is in memory, never prewarmed or written to disk; restart discards it. Cache hits echo the new request context and still check expiry. A miss consumes the shared nonrefundable owner-demo attempt allowance, including failed/timed-out attempts; cached reuse consumes no new attempt. Expired demos reject discovery and cached audio too. Default local Gemini behavior is unchanged.

This adapter synthesizes selected text; it does not generate coaching or validate its factual/clinical meaning. Existing local priority/stop policy remains authoritative. Explicit remote choice sends text to ElevenLabs under the account's applicable provider retention settings; no zero-retention claim is made. The documented zero-retention parameter requires an eligible Enterprise account and is not silently enabled here.

The implementation reuses the voice/text-cache idea from Nakki's prototype on `origin/nakki-squat-model` at `32766d8eef01ece2070e63f0aeea4315805780fb`, preserving Misha's voice integration ownership. It does not import automatic prewarming, arbitrary client-supplied voice IDs, persona scripts, disk caches, schema migrations or browser streaming.

Offline evidence: `server/test/voice.test.mjs` first failed against absent routes; provider doubles now cover authentication, configured-only discovery, exact identity/expiry, strict limits, audio validation, cancellation, cache bounds, deadline/body stalls and shared owner-demo budget. These tests make no paid requests. Real account synthesis and an explicitly authorized synthetic audible check remain separate acceptance steps.

`Native/iOS/RemoteVoicePlayback.swift` contains the optional adapter and bounded gateway client. TrainingStore owns one default instance, preserves injected playback, and exposes a separate coach picker in the existing workout voice controls. The picker lists Local, David and Arnold. Arnold is initially selected and available from bundled audio, including outside Preview; David is disabled until configured. Checking server configuration does not synthesize. Existing VoiceCuePlaybackController remains the opt-in/phase/priority gate. Stop uses cached Arnold when Arnold is selected, with immediate local speech only if that safety recording fails; other coaches retain local stop speech. Remote audio retains the original uptime deadline, uses a cancellable bounded URLSession stream with redirects blocked, checks exact response echoes and bounded base64, then decodes through AVAudioPlayer. A late request/completion cannot replace the active clip. It never silently switches a failed remote request to local speech. The tone rule only requests intense David for the exact positive pacing text “Keep a steady rhythm.” when discovery advertises that tone; existing caution/end-set/form/rest text stays calm. No current Core policy emits that positive rhythm text; actual contextual intense speech still needs an approved cue path. No new cue is invented by this adapter. No audible or physical-device acceptance is claimed.

Native acceptance on 25 October: the actual missing voice API compile RED preceded implementation. Nine remote-adapter cases and seven TrainingStore voice cases passed within a combined 37/37 native run (`test_sim_2026-10-25T07-35-57-251Z_pid19864_ac46d6c7.xcresult`, 81.0 seconds). They use injected transports and silent audio outputs; no provider synthesis or sound occurred. The same run passed the bundled human/blank pose fixture after SmartSpectra linking. Its raw runtime log also reported four duplicate Objective-C classes between SmartSpectra and MediaPipe; that separate SDK packaging risk remains unresolved despite the passing fixtures.

Primary references: [ElevenLabs Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [model IDs](https://elevenlabs.io/docs/overview/models), [Enterprise zero retention](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode).

Exact staged snapshot: seven native voice/scene cases passed in 36.2 seconds without warnings (`test_sim_2026-10-24T20-30-49-749Z_pid4129_b80bcf59.xcresult`). These fixtures use a fake synthesizer and do not prove audible output or audio-route behavior.
