# Local voice feedback

Tracked camera workouts have an explicit **Voice feedback** toggle. It starts off for every new workout. Turning it on speaks only newly issued coaching events; existing text is not read back. Muting, pausing, ending a set, changing its generation, or leaving the workout cancels speech immediately.

Playback uses Apple's standard local `AVSpeechSynthesizer`, with the system managing its audio session. It sends no text to a provider and requires no API key. Stop cues interrupt ordinary coaching. Lower priority speech is dropped rather than queued, and expired or repeated events do not replay. The controller also prevents future chat speech from interrupting active coaching.

This first integration speaks existing deterministic coaching events for tracked workouts. Ordinary manual-workout coaching, chat replies, historical reports and Watch audio are outside its current scope. An explicitly reported discomfort stop is the exception: configured rep/hold sets create the same persistent stop event without camera tracking. It reaches the voice bridge only if feedback was already enabled. The toggle remains on camera sets; this does not add a manual-only opt-in screen. The optional gateway adapter below is separate; Native playback still uses the local driver.

## Acceptance

Offline controller tests use fake playback. Native tests use fake playback and a fake speech synthesizer, so they do not produce audio. They cover opt-in behavior, cancellation, event priority, expiry, session identity, and stale completion callbacks.

On 24 October 2026, the eight voice controller tests passed after observed RED failures for missing contracts, cancellation/priority/expiry behavior, and malformed text/time. The full SwiftPM core suite also passed. Following a separate lifecycle compile RED, the parent task ran all seven native voice tests successfully: two local-driver tests and five TrainingStore tests, including background cancellation and blocked rest coaching, in 15.5 seconds, with no warnings. Rest timing continues while the scene is nonactive; coaching and speech wait for the foreground. These checks verify fake playback behavior; audible acceptance and actual audio-route interruptions remain pending.

Audible acceptance requires an iPhone or simulator check: start a tracked workout, confirm voice is off, enable it, cause a new tracking or alignment cue, and confirm it speaks once. Pause or mute during speech and confirm immediate silence. Start another workout and confirm the toggle is off again. Replay/video input must not speak personal coaching. Verify music and other app audio behavior on a physical iPhone before describing audio coexistence as device-tested.

Configured discomfort regression (24 October): three native tests first failed because manual rep/hold stops had no coaching event. After the focused correction, 23 native coaching/voice/configured-flow checks passed in 27.1 seconds on the existing Musalli-Test simulator. The fixtures verify one stop event/speech request, stable context, no ordinary manual cues, no invented completed work, blocked continuation, repeated-stop idempotence and no replay after backgrounding. Fake playback does not establish audible device behavior. Result: `test_sim_2026-10-24T22-54-43-869Z_pid35007_a4052087.xcresult`.

## Optional ElevenLabs gateway adapter — 25 October 2026

The gateway now implements authenticated `GET /v1/voices` and `POST /v1/voice`, with mocked-provider acceptance only. No paid synthesis, account voice availability, audible output or Native remote playback has been verified. Local voice remains the default after opt-in; a future Native client must require a separate explicit remote-provider choice before sending cue text.

Configure these server-only values privately, then restart the gateway deliberately:

```text
ELEVENLABS_API_KEY=<existing account key>
ELEVENLABS_DAVID_VOICE_ID=<account-enabled voice ID>
ELEVENLABS_ARNOLD_VOICE_ID=<account-enabled voice ID>
ELEVENLABS_TIMEOUT_MS=5000
```

There are no default provider voice IDs. **David** and **Arnold** are operator-assigned display names, not claims about a person's identity, a voice clone or current account availability. Discovery returns only configured aliases, for example `{ "voices": [{"id":"david","name":"David"}], "availability":"configured_not_verified" }`. It never lists the account or calls ElevenLabs. An absent/invalid selected voice returns 503; no fallback voice is substituted. `/health` reports configuration only.

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

A successful JSON response echoes the validated request fields, including unchanged identity/expiry, plus `mimeType: "audio/mpeg"` and `audioBase64`. The opaque playback token identifies one pending request; it is not authentication. A future client must accept/decode audio only while all IDs, token, original expiry, preference and current workout phase still match. Muting, pausing, changing generation or leaving cancels transport and playback immediately. Server request disconnect aborts synthesis. Late responses return `voice_expired`; neither retries nor another synthesis request happen automatically.

The provider request contains only text and fixed `model_id: "eleven_flash_v2_5"`, using `mp3_22050_32`, a fixed HTTPS host and no redirects. Response MIME must be `audio/mpeg`; audio is capped at 256 KiB and checked for an initial complete MPEG-2 Layer III frame at 22.05 kHz/32 kbps, with an optional ID3 prefix. This is a format/header check, not a full media decode or audible-quality test. The response JSON is therefore bounded to roughly 351 KiB. The entire fetch/body read has a deadline of the smaller of the original expiry and configured 1–6000 ms timeout (default 5000 ms), also bounded by owner-demo expiry. Failures are sanitized; raw provider bodies, text and keys are not logged.

Only one new voice synthesis can be active per gateway. Other cache misses return `voice_busy` without queuing. Successful clips may be reused for ten minutes by actual provider voice ID/model/text hash, with at most 32 entries and 4 MiB total audio. The cache is in memory, never prewarmed or written to disk; restart discards it. Cache hits echo the new request context and still check expiry. A miss consumes the shared nonrefundable owner-demo attempt allowance, including failed/timed-out attempts; cached reuse consumes no new attempt. Expired demos reject discovery and cached audio too. Default local Gemini behavior is unchanged.

This adapter synthesizes selected text; it does not generate coaching or validate its factual/clinical meaning. Existing local priority/stop policy remains authoritative. Explicit remote choice sends text to ElevenLabs under the account's applicable provider retention settings; no zero-retention claim is made. The documented zero-retention parameter requires an eligible Enterprise account and is not silently enabled here.

The implementation reuses the voice/text-cache idea from Nakki's prototype on `origin/nakki-squat-model` at `32766d8eef01ece2070e63f0aeea4315805780fb`, preserving Misha's voice integration ownership. It does not import automatic prewarming, arbitrary client-supplied voice IDs, persona scripts, disk caches, schema migrations or browser streaming.

Offline evidence: `server/test/voice.test.mjs` first failed against absent routes; provider doubles now cover authentication, configured-only discovery, exact identity/expiry, strict limits, audio validation, cancellation, cache bounds, deadline/body stalls and shared owner-demo budget. These tests make no paid requests. Native client selection/playback, real account IDs/key and one explicitly authorized synthetic audible check remain separate work.

Primary references: [ElevenLabs Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [model IDs](https://elevenlabs.io/docs/overview/models), [Enterprise zero retention](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode).

Exact staged snapshot: seven native voice/scene cases passed in 36.2 seconds without warnings (`test_sim_2026-10-24T20-30-49-749Z_pid4129_b80bcf59.xcresult`). These fixtures use a fake synthesizer and do not prove audible output or audio-route behavior.
