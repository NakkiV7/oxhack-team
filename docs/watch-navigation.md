# Watch navigation candidate — acceptance pending

Issue [#110](https://github.com/NakkiV7/oxhack-team/issues/110) remains open. The compact Metrics change is a candidate for the observed pager/scroll presentation problem; it has not yet passed a new build or rendered acceptance.

## Observed failure before this change

Actual simulator CUA checks reproduced readable Metrics → Controls, followed by mostly blank Metrics on the reverse drag, with the exercise title near the bottom. In a temporary diagnostic, selection remained Metrics and the fresh active-session branch remained selected. The measured viewport was **204×159 points**; Metrics content was **204×249**. Its reported content origin moved from y=53 to y=−37, exactly the 90-point scroll-to-bottom offset, while visible presentation disagreed with that geometry. Rectangle intersection alone did not establish pixel visibility.

Removing the outer timeline did not prevent the failure. A separate Metrics-only ScrollView experiment produced an immediate off-viewport blank, then settled to readable content without another UI action. Restoring the original pager in the **04:24 UTC** build reproduced the partial blank, which remained at a later capture around **04:25 UTC** after independent documentation work. These observations identify a navigation acceptance gap; they do not prove a permanent empty-content bug, a framework defect, a timeline cause or physical-device behavior. The earlier horizontal-page and bounce experiments were reverted, and all temporary overlays were removed. See the [dated UI evidence](evidence/watch-recording-skip-ui-2026-10-25.md).

## Candidate behavior

Metrics is now a compact fixed page, with no inner ScrollView. Exercise/set, quantity/target, fresh-or-missing BPM, a small explicit recording action and a short instruction share the page. Missing manual quantities and HR retain their dashes; a red HR value requires an actual fresh reading. The recording action still uses the existing guarded recorder and does not start automatically.

Controls retains its ScrollView, command/confirmation behavior, full recording status/errors, retry action and complete instruction. Its Session details section repeats exercise, quantity/unit, BPM availability and set in scalable text for fuller reading and accessibility. Primary numeric typography is bounded for the fixed dashboard; this is not a global Dynamic Type cap. Long or critical status/discomfort text remains untruncated on Controls. No telemetry fields, HealthKit permissions, thresholds, persistence or provider calls are added.

The original TimelineView, freshness validation, vertical paging style, page tags and session/generation command guards remain. This does not include the previous style experiments or diagnostic code.

## Required GREEN checks

- Compile the candidate, then repeatedly navigate Metrics → Controls → Metrics using the reproduced gestures. Check both the immediate display and a later fresh capture after useful independent work, with no intervening Watch gesture.
- Verify normal 159-point viewport fit and the largest accessibility text sizes: quantity, missing BPM, recording action and set/instruction remain discoverable; full Controls details and errors scroll readably.
- Verify the explicit recording action and truthful busy/unavailable state, without inventing sensor values. Confirm skip/discomfort blocks Next set and recording as before.
- Confirm End session → Cancel preserves the session; only explicit confirmation sends Finish. Check finished-page fit.
- Keep physical Crown, Ultra screen fit, Health authorization, actual sensors and recording/save as separate device gates. A build or one successful swipe does not close #110.

Only source changes were prepared for this candidate. No new build, UI interaction, recording or provider request was performed by its author.
