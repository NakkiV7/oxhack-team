# Local voice feedback

Tracked camera workouts have an explicit **Voice feedback** toggle. It starts off for every new workout. Turning it on speaks only newly issued coaching events; existing text is not read back. Muting, pausing, ending a set, changing its generation, or leaving the workout cancels speech immediately.

Playback uses Apple's standard local `AVSpeechSynthesizer`, with the system managing its audio session. It sends no text to a provider and requires no API key. Stop cues interrupt ordinary coaching. Lower priority speech is dropped rather than queued, and expired or repeated events do not replay. The controller also prevents future chat speech from interrupting active coaching.

This first integration speaks existing deterministic coaching events for tracked workouts. Configured manual workouts, chat replies, historical reports, and Watch audio are outside its current scope. There is no gateway voice endpoint or ElevenLabs adapter.

## Acceptance

Offline controller tests use fake playback. Native tests use fake playback and a fake speech synthesizer, so they do not produce audio. They cover opt-in behavior, cancellation, event priority, expiry, session identity, and stale completion callbacks.

On 24 October 2026, the eight voice controller tests passed after observed RED failures for missing contracts, cancellation/priority/expiry behavior, and malformed text/time. The full SwiftPM core suite also passed. Following a separate lifecycle compile RED, the parent task ran all seven native voice tests successfully: two local-driver tests and five TrainingStore tests, including background cancellation and blocked rest coaching, in 15.5 seconds, with no warnings. Rest timing continues while the scene is nonactive; coaching and speech wait for the foreground. These checks verify fake playback behavior; audible acceptance and actual audio-route interruptions remain pending.

Audible acceptance requires an iPhone or simulator check: start a tracked workout, confirm voice is off, enable it, cause a new tracking or alignment cue, and confirm it speaks once. Pause or mute during speech and confirm immediate silence. Start another workout and confirm the toggle is off again. Replay/video input must not speak personal coaching. Verify music and other app audio behavior on a physical iPhone before describing audio coexistence as device-tested.

## Proposed optional gateway contract

This is a design handoff for Misha's later ElevenLabs work. No endpoint, paid synthesis, provider key, or remote audio playback is implemented by this change. Local voice remains the default playback provider after the user opts in. Selecting remote synthesis would require a separate explicit preference.

An authenticated `POST /v1/voice` could accept this bounded JSON body:

```json
{
  "generationID": "UUID",
  "sessionID": "UUID",
  "cueID": "UUID",
  "playbackToken": "fresh request UUID",
  "text": "Current deterministic coaching text",
  "priority": "form",
  "expiresAt": "2026-10-24T21:30:06.000Z"
}
```

The request uses the existing gateway Bearer authentication; provider credentials stay on the server and must never be bundled with the app. The server validates UUIDs, a known priority, nonblank text of at most 500 characters, and a short future UTC expiry before invoking a provider. Uptime values from local events must not be sent as wall-clock timestamps. Ordinary events retain their original six-second playback deadline; server latency cannot extend it. Stop cues always use immediate local playback so network latency cannot delay them.

A JSON response would echo `generationID`, `sessionID`, `cueID`, `playbackToken`, and `expiresAt`, plus an allowlisted `mimeType` and a bounded `audioBase64` payload. The opaque playback token identifies one pending client request; it is not an authentication credential. The client accepts audio only while all IDs, the token, original expiry, enabled preference, and current workout phase still match. Cancellation invalidates the token, cancels transport, and stops audio. Late responses are discarded. Neither retries nor another synthesis request occur automatically.

The gateway only synthesizes already selected cue text. Provider output cannot change cue priority, extend expiry, start a workout, execute a command, or override local coaching. Audio and text are untrusted response data with strict size/type validation. Existing coaching priority still decides whether a clip can start; chat cannot interrupt a current coaching cue. Cache, cost limits, provider consent, and exact payload/audio limits need agreement and tests before implementation.

Exact staged snapshot: seven native voice/scene cases passed in 36.2 seconds without warnings (`test_sim_2026-10-24T20-30-49-749Z_pid4129_b80bcf59.xcresult`). These fixtures use a fake synthesizer and do not prove audible output or audio-route behavior.
