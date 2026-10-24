# Teammate integration review — 24 October 2026

Reviewed Azhar's `68021a28` push-up prototype and Misha's `landing/index.html` on the shared checkout after the `1c81972` fast-forward. Existing dirty native, hardware and project files were preserved. This review changes prototype tests/documentation only; it does not establish physical camera, phone, Watch or provider acceptance.

## Offline evidence

`cd prototype/pushup && npm test`: **19 passed, 0 failed**. The original 15 checks cover geometry, counting, one rep-time example and guarded coach questions. Four added HTTP behavior checks cover control-code rejection, command forwarding only with a Mac subscriber, five failed-code lockout, coach-off failure and state replay/malformed JSON. Each HTTP check copies the two server modules into a temporary directory, uses an ephemeral local port and an empty provider key, suppresses server stdout (which contains the control code), then removes its temporary token and files. No provider requests, model downloads or real video were used.

The browser timer, summary and pacing functions and the prototype SwiftUI app were inspected from source. Their rendered/device behavior has not been accepted by this review.

## Prototype findings

| Finding | Evidence and consequence | Integration decision |
|---|---|---|
| LAN reads and chat are unauthenticated | `server.mjs` handles `/events`, `/state` and `/ask` before its loopback gate; `/events` includes JPEG frames and replays coach/Q&A. The code protects `/control` only. Raw TCP in `ios/pushup-ios/PushupClient.swift` uses plain HTTP. | Trusted-network prototype only. Do not copy this transport into native Spottr. Native secondary camera work has a separate authenticated/TLS boundary. |
| Rejected questions are shared before validation | `/ask` inserts and broadcasts a question before calling `ask(...)`; its injection/rate limits prevent model calls but do not prevent these shared-chat entries. Logs retain the last 50 entries across workouts until server restart. | A shared native chat would need session scope, pairing/access checks and validation before broadcast. Reuse the native grounded gateway contracts rather than adding a second Gemini client. |
| Loop boundaries and large sampling gaps affect rep timing | Synthetic public-API replay with elbow angles `[170,170,120,70,70,120,170,170,170]`: timestamps `[9.6,9.7,9.8,9.9,10,.1,.2,.3,.4]` produce one counted rep with `secs: null`; timestamps `[0,.1,.2,.3,.4,30.1,30.2,30.3,30.4]` produce one counted rep with `secs: 30`. `index.html` supplies `video.currentTime` for looping uploads and the counter retains movement across the loop. | Before treating replay pacing as evidence, reset movement on seek/loop, prolonged tracking loss and invalid time; exclude invalid durations. Native already resets nonmonotonic timestamps/gaps over 0.75 s and admits only 0.6–15 s cycles. |
| Variation changes reset reps while retaining elapsed time | The variation handler calls `setVariation` and clears history without `clockReset`; summary time can include the preceding variation while reps describe the new one. | Decide whether changing variation begins a new workout, then test the whole timer/count/summary behavior together. |
| Tempo is descriptive | `timeClass` compares a rep to the mean of earlier counted timed reps after two examples; `paceStats` compares the final three to all earlier reps after six. Good-form filtering is not applied. Faster is tinted green; a comment equates slowing with fatigue. | Present seconds and change as observations. Faster is not intrinsically better and slowing does not establish fatigue. |
| Form counts have a different contract | Prototype records full-depth reps separately from `good` reps and labels issues with thresholds up to 165° body line. Native uses graded body-line handling and a different debounced counter. | Do not replace native thresholds or relabel its count as a validated good-form score. Use labelled failure clips to justify any shared policy change. |

## Native parity without duplication

| Azhar feature | Existing native boundary | Useful remaining work |
|---|---|---|
| Aspect correction | `Shared/Core/PoseGeometry.swift` multiplies normalized x/y by frame width/height before measuring. | Already present. Add comparable labelled clips if needed; no new geometry pipeline. |
| Active timer and pause/resume | `TrainingSession.elapsed/pause/resume`, `TrainingStore` and `SessionViews`; pause resets partial movement. | Already present. Exercise the current UI and source/phase transitions. |
| Remote controls | `TrainingStore` consumes companion pause/resume commands. | Use existing Watch/session identity handling. A new Mac remote is a separate product decision. |
| Per-rep tempo and mean | `RepCounter.lastRepDuration`, `TrainingSession.repDurations`, saved `SetRecord` and `WorkoutReport.averageRepSeconds`; report UI already displays mean. | Optional per-rep list, valid sample count and fastest/slowest from the same stored durations. Keep manual/untimed sets explicitly missing. |
| Slowing trend | `CoachingPolicy` already has a deterministic slower-rep reason and cue priority. | Reuse its evidence and terminology in a report; avoid a second competing pacing policy. |
| Workout summary | Native set/session records, history and deterministic reports already exist. | Add focused summary presentation if user acceptance reveals a gap; no second persistence store. |
| Shared coach Q&A | Native `CoachModel`, gateway, semantic grounding and local chat UI exist. | Defer shared multi-device chat until access/session/retention requirements exist. |

Timing definitions must remain explicit: prototype `secs` is lowering onset to return up; native duration is an armed top-to-top cycle, including time at the top. These values cannot be combined or compared as the same measurement without an agreed contract and behavioral fixtures.

## Initial landing handoff (superseded by PR #38)

These were findings against the initial page, with line numbers from that snapshot. [PR #38](https://github.com/NakkiV7/oxhack-team/pull/38) subsequently corrected the availability links, provider wording, sample-image labels and asset packaging. Use the [current landing guide](../landing/README.md) for its present state and remaining browser acceptance; the historical findings below are not a current defect list.

- Both App Store buttons use the acknowledged placeholder `https://apps.apple.com/app/spottr` (`landing/index.html:658,868`). Replace them with a verified project/demo destination and truthful development availability label before publication; no public Spottr listing was verified here.
- “All tracking and coaching runs locally” (`:761`) conflicts with optional Gemini gateway coaching. State that pose counting and deterministic cues work offline; optional AI coaching requires the configured network gateway.
- ElevenLabs audible playback/queue claims (`:779`), recovery-based Watch rest suggestions (`:743`) and fully grounded Gemini cue phrasing (`:752`) need current end-to-end evidence. The integration ledger currently records pending acceptance; keep planned features labelled accordingly.
- “0ms cloud latency” (`:851`) is not a measured inference latency result, and “no privacy concerns” (`:734`) is an absolute claim. Describe on-device pose processing without those claims.
- The five referenced `../design/*.png` assets exist, but the page depends on serving the repository parent, or copying them into the deployment tree. They are design renders, not accepted native screenshots. Label illustrative/sample content (including the Watch's hard-coded 142 BPM and 8 reps) and replace the hero with current native captures when available.
- The local design handoff calls for a visible Skills tour; this page currently has no Skills section. Publication/layout/keyboard/accessibility and external-link checks remain with the landing owner. This review did not edit their page or deploy it.
