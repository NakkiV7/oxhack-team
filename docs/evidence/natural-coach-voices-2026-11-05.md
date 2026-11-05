# Natural offline coach voices

5 November 2026. Build 22 replaces Maya and Leo's system-speech coaching with prerecorded ElevenLabs audio. These changes continue the native consumer experience on `codex/spottr-demo-consolidation`.

## Delivered behaviour

Each original coach has 72 bundled recordings across Gentle, Encouraging and Direct styles. Each style covers stop/discomfort, tracking, alignment, target reached, rest, completion, a slower rep and eight rotating encouragement phrases. Style changes encouragement delivery; form and safety instructions remain calm. Maya uses a warm female recording voice and Leo a calm male recording voice. Coach choices keep the existing abstract colour/waveform artwork.

Playback reads local app resources. There are no ElevenLabs credentials, provider requests, tokens or synthesis costs during a workout. The explicit Local voice option still uses iPhone system speech. Existing Arnold coaching and Arnold/Goggins rep recordings remain intact; Goggins rep audio is optional and its general coaching path is unchanged.

Tracking prompts finish naturally once they start, including after their starting deadline, through the existing cue controller. Later ordinary prompts are dropped while tracking speech plays. Stop can interrupt. Mute, pause and cancellation still stop playback. A clip whose preparation finishes after its freshness deadline never starts. A missing or unplayable stop recording falls back immediately to system speech. Phrase rotation remains independent for each event and style.

Natural recordings use the spoken playback audio session with ducking and release it on stop/completion. This makes coach audio audible with the silent switch while allowing other audio to resume. Hardware route, silent-switch and interruption acceptance still require a physical-phone check.

## Authoring and assets

The authorised workspace was used only to author fixed app-owned coaching text. The new key is restricted to speech generation, voice reading and usage checks, expires after one day, has automatic leak disabling enabled and has a 10,000-credit limit. It is held privately outside source control and never enters either application bundle. No upgrade, purchase or overage was enabled. The workspace reported paid overage disabled.

All 144 requests succeeded on their first attempt. The API reported **3,658 credits** total. Each request has a private exclusive attempt record and response receipt; ambiguous requests are never automatically repeated. The two earlier web auditions are separate from this API total.

Authoring used [Eleven v4](https://elevenlabs.io/docs/overview/models) through the [speech conversion API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert). Source MP3s and private receipts live on the SSD-backed development volume. Delivered clips are mono 22,050 Hz at 64 kbps, with leading/trailing silence trimmed and levels normalised with peak limiting. The 144 delivered MP3s total **3,597,377 bytes**. Public manifests contain text, filenames, byte counts, hashes and decode properties, without API credentials or private voice IDs.

## Verification

Before implementation, native tests reproduced original coaches using system speech instead of recordings, missing rotation/tracking/safety behaviour and an ambient audio session. The asset check failed before the banks existed. The focused native voice suite first passed 54 cases. After the activation regression fix, full native checks pass **230 cases**, with the same four pre-existing `MembershipStoreKitTests` excluded because simulator StoreKit setup reports `notEntitled`. This does not claim paid-purchase acceptance.

The shared core passes **131 XCTest plus 262 Swift Testing cases**. The gateway passes **99 cases**, including every new recording's decode, mono/sample-rate, duration, hash, audible level and peak-headroom checks. Three old gateway tests still expected the smaller catalogue; they now check the expanded camera support, equipment filtering and agreement between the two catalogue adapters. Runtime gateway functionality was not added to the consumer app. The Pi suite passes 28 cases and static checks pass.

Code review caught a further synchronous-activation freshness gap. The complete voice-class red run executed 23 tests and reproduced two assertion failures. Audio-session preparation now precedes the final deadline check; an expired prepared output is stopped and releases its session. Re-review found the issue resolved. One earlier filtered run executed zero tests and is not counted. A later native launch stalled; that result was interrupted and preserved. Restarting the same existing simulator restored execution, and the corrected full native run passed all 230 cases.

The existing onboarding UI journey passes using isolated test storage and the shared existing iPhone simulator. [Actual trainer-selection screenshot](../media/natural-coach-voices-2026-11-05/trainer-selection.png). No simulator was created or erased and Chrome was not used. No model training or HPC work was started. Protected build 17 and Vendor files retain their baseline content and metadata exactly.

Physical listening, Bluetooth routing, mixing with music, phone interruptions and real-camera coaching remain device checks. Automated audio checks establish valid playable files and measured levels, not a human judgment of voice quality. Existing camera-counting and Watch telemetry acceptance limits remain unchanged.

## Release

Version **0.1 (22)** is signed for iPhone and Watch. IPA **45,332,614 bytes**, SHA-256 `c211c89eaf3fb2e3f88bf60eb5102143dbabd553244b2927aefc44e5845081fc`. Both strict signatures, HealthKit entitlements/profiles and binary/dSYM UUIDs pass. All **243 MP3s** match source bytes; the canonical Full-pose model is unchanged. The actual temporary authoring-key bytes were checked absent from both delivered application bundles. All **349 frozen release inputs** remained unchanged through the corrected archive. The earlier unuploaded activation-gap candidate remains preserved separately on the SSD.

Apple validation and distribution state are recorded below once verified. Build 21 remains the prior approved release until Apple accepts build 22.
