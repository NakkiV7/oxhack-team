# Gemini structured-output compatibility — 25 October 2026

The local gateway now omits `maxItems` only from the JSON schema sent to Gemini. Its authoritative Zod output contract still enforces every limit after generation. Context, other schema keywords, the 2,048 output-token budget, response-byte limits, authentication, timeout and explicit approval behavior are unchanged. There is no automatic retry or provider fallback.

## Observed boundary

Diagnosis used **four new provider attempts**: three native proposal actions and one direct synthetic comparison. Three subsequent native acceptance actions bring this investigation to **seven attempts** in total. The two temporary diagnostic runs each permitted one upstream request. They used the existing server credentials privately; Tiger was disabled. The diagnosis table's timestamps are UTC on **24 October**, before this document's date.

| Attempt | Observed result |
| --- | --- |
| Normal native Propose through port 8788, before diagnostic capture | UI displayed HTTP 502. Upstream status/message and usage were not captured; this attempt alone does not establish its cause. |
| Native Propose through diagnostic port 8842, 23:56:03.513 | Gemini HTTP 400, `INVALID_ARGUMENT`; 127-byte error body. Gateway returned 502 `provider_unavailable`. Freeform provider message was not retained in this first diagnostic. |
| One additional native Propose through port 8842, 23:57:41.594 | Gemini HTTP 400, `INVALID_ARGUMENT`: “Request contains an invalid argument.” Same gateway 502. No candidate, finish reason or usage metadata was supplied. |
| One controlled direct comparison, 23:59:08.982–23:59:10.339 | HTTP 200, `STOP`; three proposed items passed the **full original** output validator. |

The captured native request contained six honest empty-history/game-progress facts, no profile or equipment, and 15 permitted exercises. Its model was `gemini-3.5-flash-lite`; timeout was 20 seconds. No real workout, biometric stream or personal coaching assessment was used. Earlier successful synthetic gateway requests are separate historical evidence; their exact model/request bodies were not retained for an exact comparison.

## Controlled comparison

The original schema was reconstructed using the actual `jsonContract(outputContract(...))`, restoring its public `$schema` URI. Deep and serialized equality checks matched the entire captured request after the same URL sanitization. The experiment changed only these three outbound schema entries:

- `properties.items.maxItems`: 12
- `properties.items.items.properties.factIDs.maxItems`: 16
- `properties.rationale.properties.factIDs.maxItems`: 16

Request JSON SHA-256 before projection: `abd3539d83edafa06a15cea7f22f465610e82c0b85181c57f8ef256430105777`.

Request JSON SHA-256 after projection: `352890a440316e80613c5d55c9b98be43edd092c01dc0ab00c8609882ed7bd58`.

The successful response was 1,852 bytes; its combined answer text was **1,003 bytes**, not tokens. Reported usage was **876 prompt + 361 candidate = 1,237 total tokens**. The original validator accepted all three items. Private ignored receipts preserve comparison/schema hashes, changed paths and sanitized metadata; no headers, known credentials or full URLs were retained. The temporary diagnostic server was stopped.

Google's [structured-output limitations](https://ai.google.dev/gemini-api/docs/structured-output) identify nested array limits and other grammar branching as causes of HTTP 400 and suggest reducing or removing such limits. This single comparison supports the provider-only projection; it does **not** identify which individual `maxItems` entry caused rejection, guarantee every model/request will succeed, or prove generated recommendations follow from their cited facts.

## Offline regression and remaining acceptance

The new native-shaped provider-boundary regression first failed with **502 instead of 200** against a stub reproducing the captured rejection. After the projection it passed, while exact comparison proved all other schema keywords were preserved. Additional cases still rejected 13 unique exercises and 17 unique, supplied fact references in either an item or rationale. Existing stale-generation, unsupported exercise/unit, quantity, duplicate, total-set, summary, timeout, response-size and sanitization checks also passed.

Focused regressions: **2/2 passed**. Full `cd server && npm test`: **53/53 passed**, using offline fixtures with no provider/database calls. `outputContract` was not modified. The projection walks only the finite server-generated schema, never arbitrary request JSON.

## Native acceptance after the correction

On **25 October, before cleanup at 00:07:40 UTC**, the signed Musalli-Test iOS 26.5 app used the corrected real gateway on port 8788. Exactly three explicit actions generated one proposal, one weekly summary and one session summary; no automatic or manual retries were performed in this acceptance phase. All three rendered through the normal native validation/UI path. No provider usage or precise request latency was captured for these three actions.

The empty-history proposal displayed Squats (3 × 10 reps), Knee push-ups (3 × 8 reps) and Forearm plank (3 × 30 sec), each with 45-second rests. Its rationale correctly stated zero saved sessions. Selecting Squats left the other two switches off. **Approval was not submitted**, and no plan was persisted. This accepts display/independent selection for this response; it does not validate the suggested workload for a person.

A separate Debug-only fixture plan allowed one synthetic manual squat entry: **one set, two reps, no sensor data**, under namespace `1C1F074D-5673-4D6C-AC4C-29D8DFE517AF`. It was not a performed exercise or an approved Gemini plan. Deterministic Progress showed one session, one set and two reps, with a Manual badge. The detailed report retained zero recorded time and explained that bulk manual entries have no recorded duration.

- Weekly headline: “Your weekly history scope shows 1 saved session with 2 total reps.” Its insight identified one squat set with two self-reported manual reps; its focus was to continue recording sessions.
- Session headline: “Completed 1 manual session on 2026-10-25 featuring 2 reps of Squats.” Its insight identified one supplied session/two recorded reps; its focus was to continue logging sets.

Both complete generated cards, including focus and attribution, were inspected. Neither claimed heart rate, form quality, physiological readiness or physical exercise acceptance. Their agreement with this tiny synthetic record is a factual smoke check, not a broader coaching-quality evaluation. Chat has separate [earlier native acceptance](native-gemini-chat-2026-10-24.md).

Installed native executable SHA-256: `7cc4fba7956d242fea8e80321e0fc6646d84fe1194806a44cf5248d2cede9a02`. Corrected gateway source SHA-256: `a71396890de5f2a93010279d0a789ca03c4f30c1c27ab158b8c0a95066fa9d74`; unchanged contracts: `3d7813a2c3e5a21051e528271ae79a093da38888a903aceb7741ce8ad2683e57`.

After stopping the app, the exact synthetic history was hash-checked against a private backup and moved out of that simulator namespace. Its SHA-256 was `42eb796e371e0566420b3bbb13aae87a6f7bee96973c914efee98685d45218f1`; it held one session/one set and zero telemetry envelopes. No other history was changed. The saved URL was verified as `http://127.0.0.1:8788`, the existing Keychain token was preserved, no approved plan was present, and the app relaunched without fixture variables. Keyboard capture returned to off. The diagnostic server is stopped; the corrected normal gateway remains available with Tiger disabled.

These unchanged phone-only JPEG captures are 368 × 800 pixels:

| Capture | Bytes | SHA-256 |
| --- | ---: | --- |
| [Proposal selection](native-gemini-proposal-2026-10-25.jpg) | 50,603 | `42442600df68fa2a164b36c91a4599b03c849340138b4891d2b33e507ec6daf4` |
| [Weekly insight](native-gemini-weekly-2026-10-25.jpg) | 42,003 | `c87435a25d53765542a0ec78bdb14db7c1e456c644477209180dff9c3f1cedf2` |
| [Session insight](native-gemini-session-2026-10-25.jpg) | 46,606 | `235b4f97344dce19f70816f2b8158fb90a46bea6ee91299e1264b70e30f20874` |

Physical HTTPS networking, real-user factual review, generated-plan approval/execution in a live-provider rehearsal and broad request/model coverage remain pending. This server correction does not require a new native binary; TestFlight build 2's availability and device installation remain separate.
