# Weekly Coach approval: simulator UI acceptance

25 October 2026. Actual CUA interaction used the existing Musalli-Test iPhone simulator, installed 03:23 binary (root-reported), and an isolated synthetic namespace. Responses came from the bounded private loopback fixture, not Gemini. This is UI and wire-contract evidence, not provider or exercise-quality validation.

## Passed flow

1. Preserved app preferences privately, changed only the gateway URL through Coach settings, and left the existing secure token value intact. The fixture recorded zero attempts before the explicit request.
2. Entered an unsent synthetic draft requesting short squat practice, made Monday–Friday available, and reduced the weekly target to three. Explicitly tapped **Propose my week**. The accepted request contained that draft, `Europe/London`, start date `2026-10-25`, available offsets `[1,2,3,4,5]` and target `3`.
3. The response visibly identified itself as a synthetic fixture. All three workout switches started off, and approval was disabled with nothing selected. Selected Monday only, then used its destination menu to move it to Thursday.
4. Explicitly approved the selection. The saved UI showed Thursday 29 October, one squat set of two reps, and a separate **Start this workout** action. Decoding the saved preference confirmed exactly one selected date, `2026-10-29`; no separate single-workout plan was created. No workout was started or logged during this pass.
5. Removed only this synthetic saved week through its confirmation dialog and restored the original gateway URL through settings. The entire decoded preference dictionary matched the before-backup exactly. Capture Keyboard was restored off; the temporary mirror viewport was reset, localhost zoom restored to 25%, and only the task tab was closed. The app was left on Today.

The fixture stopped after **one request and zero provider calls**; port 8846 was no longer listening. An initial startup failure caused by the temporarily checked-out branch lacking the weekly contract module was resolved before any request by restoring the frozen weekly branch.

## Limits

No saved-day Start, actual exercise, physical device, camera, audio, live Gemini request or physiological recovery assessment was exercised. Prior chat history was empty: the optional chat-to-proposal conversation check remains untested here. History files were not independently compared byte-for-byte; the UI never entered a workout. A transient incorrect connection draft was cancelled before saving; the populated secure field was retained on the successful restoration.

[Saved weekly plan — unchanged synthetic simulator capture](coach-week-approved-ui-2026-10-25.jpg)

Screenshot SHA-256: `69bcf147ceb0f96fb7db23a9e62be1960f0a71eb1264908f972523e4eec186c0`.
