# Bundled Arnold workout voice

Arnold is the initial coach selection in Preview and ordinary workouts. Voice feedback still starts off for each workout. Selecting Local explicitly uses Apple speech; Arnold plays bundled ElevenLabs recordings without a gateway or runtime voice credits.

## Cue bank

| Event | Recording | Words |
| --- | --- | --- |
| Tracking | tracking | Keep your whole body visible. |
| Alignment | alignment | Keep your body straight. |
| Planned target | target | Target reached. |
| Rest reminder | rest | Rest until ready. |
| Discomfort / stop | stop | Stop for pain or discomfort. |
| Workout finished | completion | We'll be back. |
| Steady rhythm | positive-1 through positive-5 | Five rotating encouragement clips |
| Slower rep | slower-1 through slower-4 | Four rotating control / pause clips |
| Explicit ended-set recovery | recovery, recovery-2 | Two rotating rest clips; no inferred fatigue |

The adapter selects recordings from typed reasons and priorities, never text guesses. Tracking, form, target, rest and safety events cannot become generic encouragement. Unknown ordinary events finish silently. No chat replies or reports are synthesized by this bank. The rest recording deliberately omits dynamic seconds.

Stop cancels ordinary audio and starts its local Arnold recording immediately, without an expiry or network wait. A missing, undecodable or unplayable stop recording falls back to immediate Apple speech so the warning is not lost. Other missing recordings do not silently change coaches or retry a provider.

## Loudness and provenance

All seventeen MP3s use mono 22,050 Hz / 32 kbps. Originals are decoded to float PCM, gain-adjusted toward -10 dBFS RMS, passed through a lookahead limiter (0.75 ceiling, automatic output gain off, 5 ms attack / 50 ms release), then encoded again. Final decoded mean levels range from -13.7 to -12.1 dBFS, with decoded peaks at or below -1.2 dBFS and measured true peaks below -0.5 dBFS. The recordings average 3.3 dB louder than their sources. Phone media volume and output route still affect actual listening volume.

`Native/Resources/DemoVoice/arnold/manifest.json` retains source hashes, final hashes, generation receipts and decoded measurements. The five added recordings used one successful request each, with provider-reported costs totalling 24 credits. The existing restricted key's 100-credit cap was unchanged; no paid retries, replacement keys or permission expansion were used. Keys and private voice identifiers remain outside the repository. Arnold is the account's generated voice label, not an identity claim.

## Verification

Observed RED: form/target/rest/stop events reached Apple speech instead of the requested cached files; the original positive-1 measured -15.9 dBFS and failed the new volume check; offline Arnold default selection failed its new behavior test. These checks drove the changes.

The isolated macOS SwiftPM harness compiles the real adapter and remote routing source, guards only iOS-specific audio-session calls, disables production Keychain configuration, and uses the actual bundled resources in test targets. It exercises playback decisions with recording outputs and decodes all MP3s through AVAudioPlayer; it does not claim audible phone playback. Native store integration and signing/install checks must run on the coordinated native lane.

Run `node --test server/test/demo-voice-assets.test.mjs` with ffmpeg installed to verify final hashes, decoding, volume and no clipping. The controller suite is `swift test --filter VoiceCuePlaybackTests`. Native selectors: `DemoVoicePlaybackTests`, `RemoteVoicePlaybackTests`, `PreviewVoiceIntegrationTests`, `WorkoutCompletionVoiceTests`, `PreviewRepCueTests`.

Physical acceptance remains open until a newly installed build speaks Arnold clearly for tracking/alignment, reps, rest/target and workout completion, and mute/pause stops it promptly. Build 0.1 (7) was reported quiet and still used Apple fallback; earlier passing tests do not supersede that negative human result.
