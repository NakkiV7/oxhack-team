# Training rewards and goal artwork — 25 October 2026

**Source software checkpoint; not released in TestFlight 0.1 (5).** Shared rules merged in PR #123; native settings and artwork are recorded here.

Today separates protected streak days from actual training days, shows remaining freezes and presents total XP with its existing base/awarded-bonus breakdown. Profile opens explicit next-day window settings. Unreadable rewards are preserved and shown as unavailable. Unreadable training history also blocks reward advancement rather than being treated as empty activity.

A saved window starts the next local calendar day and lasts two elapsed hours. Today cannot be edited. Dates and timezone abbreviations come from the actual interval in the ledger’s pinned calendar; daylight-saving clock changes are explained. Cancel preserves the saved window. A sheet crossing midnight rejects saving with a close/reopen instruction; that branch was source-reviewed, not exercised in UI.

Two freezes can protect missed days in an active chain. Explicit approved rest dates do not consume them. Protected days are not exercise or XP. Existing qualifying-set rules and daily base-XP caps remain. Newly saved completions can receive an equal bonus within the active window; historical records receive no retroactive bonus, and repeated saves do not award twice.

## Recorded checks

| Checkpoint | Actual result |
| --- | --- |
| Exact-index shared suite, `.local/rewards-core-index-green.log`, 06:30:56 UTC | **90 XCTest + 123 Swift Testing passed**. |
| Focused native run `06:15:51_4fe00ea6` | **21/21 passed**, rather than the earlier proposed 23-case count. |
| Earlier combined run `06:20:53_3f200941` | **9/9 passed**: refresh 2, history-load failure 1, data removal 1, training flow 4 and rewards UI 1. |

The final rewards checkpoint `06:53:37_32edebe9` passed **25/25**: 24 native cases and the rewards UI case. A new recovered-history regression first produced three real assertion failures (actual RED `06:50:33_0ff55c73`): a restored same-day history incorrectly awarded 30 bonus XP instead of 10. The save path now reloads a known-good prior history after initial read failure, before computing the incremental award.

A separate corrupt-history Profile UI probe first failed (`06:57:23_747c58bf`), then passed **1/1** (`07:01:11_c26ae68f`): Profile shows unavailable history rather than invented zero totals. Its disposable namespace was removed after its corrupt file was verified unchanged. These final build logs retained known AppIntents metadata warnings; they were not warning-free.

Earlier NativeRewards 11 and Profile 4 checks passed separately; overlapping runs are not added into a global total. The history-load failure test first failed five assertions before its guard was added. The deletion regression first failed in `06:13:22_8fd7a817`: rewards-reset failure left prepared exports behind. Cleanup now precedes the separate rewards reset, so exports are removed while the failure remains reported.

The final UI case drafts **09:00**, confirms Tomorrow changed while Today did not, cancels and verifies the original window. It then explicitly saves **10:00–12:00** and verifies persistence after relaunch. It uses a fresh UUID namespace without provider calls or workout capture.

## Raster assets and remaining limits

Existing Strength is retained. Built-in imagegen produced seven individual PNGs: `stamina`, `mobility`, `balance`, `streak-complete`, `streak-incomplete`, `streak-freeze` and `xp-double`. Outputs were individually inspected and copied unchanged into same-named [asset catalogue imagesets](../../Native/Resources/Assets.xcassets). All are **1254×1254 RGBA**, with transparent pixels verified. No SVG, programmatic drawing, crop or image edit was used.

Physical acceptance remains pending. Watch complications and their extension signing are deferred in [the post-hackathon backlog](../POST-HACKATHON.md). No build 6 archive, Apple validation, upload or TestFlight availability is established here. The reported build-5 onboarding crash remains unresolved despite the original passing exact-source optimized simulator case and two expanded passing variants. A rewards-write failure preserves the saved workout and reports partial success; no pending-completion retry journal or bonus backfill is implemented.
