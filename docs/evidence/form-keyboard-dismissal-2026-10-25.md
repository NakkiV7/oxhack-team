# Connection and manual-form keyboard dismissal

Verified on the existing iPhone simulator on 25 October 2026. Coach settings, side-camera pairing and manual workout logging now support explicit keyboard **Done**, downward form scrolling and tapping their explanatory text to dismiss the keyboard. Edited and cleared drafts remain unchanged until the user explicitly saves or cancels.

The initial UI run (`05:15:23_c017bde2`) failed all three cases at the missing Done action. The final implementation uses a shared SwiftUI `KeyboardDismissBar` through `safeAreaInset`. The initial keyboard-toolbar implementation produced runtime “Invalid frame dimension” warnings; a Spacer-only probe did not resolve them and was reverted. The final runs below recorded zero runtime warnings.

## Final acceptance

- `05:24:22_a97949fd`: **Manual workout and side-camera settings both passed**, covering Done, downward scroll, explanatory-text tap, draft preservation and Cancel. Manual Cancel left the exercise history unchanged; pairing Cancel retained the original address.
- Coach passed the dismissal and draft checks in that run, but XCTest failed to target the reopened settings toolbar correctly (a stale parent produced a `(-1, -1)` hit). Root’s direct CUA Cancel/reopen check succeeded and showed the original connection. The final test uses a cold launch after Cancel to verify the persisted connection without that transition ambiguity.
- `05:31:21_01cf285c`: **Coach settings passed 1/1**, 58.1 seconds, including its final persisted-connection check, with zero runtime warnings. Production source was unchanged between the two final runs.

Thus all three cases passed **across two final runs**, rather than in one combined run. Test query corrections used exact-label predicates for explanatory text exceeding XCTest’s 128-character lookup limit.

## Scope and limits

Every test used a fresh UUID data namespace. These checks did not send provider requests, save a pairing, or start side-camera capture. The side-camera navigation passes through Start session, which can enter the phone-camera simulator path; this receipt does not assert that every camera request was absent. Test code did not inspect or alter secure token values.

Independent source reviews found no change to explicit Save/Forget behavior or interference with fields and buttons. Physical iPhone keyboard acceptance remains pending.
