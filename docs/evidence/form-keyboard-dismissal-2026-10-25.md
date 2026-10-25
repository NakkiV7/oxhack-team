# Chat and form keyboard dismissal

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

## Chat Done and swipe handle follow-up

The new chat test first failed at the absent Done button (`05:42:09_92c4b248`). Chat now exposes the same bar while its composer is focused, with a visible handle and Done action. A downward, predominantly vertical drag on the bar clears focus. The gesture is confined to the bar; it does not attach to text editing or the whole conversation.

In `05:55:53_9c04bbe2`, the chat case **passed in 24.0 seconds**, with zero reported runtime warnings: Done and the handle swipe hid the real simulator keyboard and preserved the exact unsent draft. No Send/model request was started. That run deliberately included the next feature’s missing rewards-entry test, which failed as expected; the combined run was therefore **one pass and one failure**, not a fully passing suite.

An earlier combined chat/settings follow-up passed chat in 26.3 seconds, then exceeded the MCP 300-second limit while XCTest waited for repeated settings animation notifications. Root interrupted only that owned test process. This is not a settings regression pass. A subsequent direct CUA check on the same binary focused the existing connection URL without editing, used Done, visibly confirmed the keyboard was hidden and the URL unchanged, then left with Cancel. The three complete pre-handle form cases above remain separate evidence. Source review confirmed the shared bar still only clears field focus. The Watch currently has no text-entry field to dismiss; its workout navigation uses its existing pages and scrolling.
