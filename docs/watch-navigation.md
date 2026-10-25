# Watch navigation — simulator checks and remaining gates

The compact Metrics change passed repeated simulator paging and large-text checks on 25 October 2026. The final normal-text build passed at 04:44 UTC without warnings; its skipped-state round trip also remained readable at a later capture. The finished page fitted after explicit iPhone Finish at 04:46 UTC. Issue [#110](https://github.com/NakkiV7/oxhack-team/issues/110) retains separate physical Crown and device checks. See the [dated acceptance receipt](evidence/watch-compact-navigation-2026-10-25.md).

## Observed failure before this change

Actual simulator CUA checks reproduced readable Metrics → Controls, followed by mostly blank Metrics on the reverse drag, with the exercise title near the bottom. In a temporary diagnostic, selection remained Metrics and the fresh active-session branch remained selected. The measured viewport was **204×159 points**; Metrics content was **204×249**. Its reported content origin moved from y=53 to y=−37, exactly the 90-point scroll-to-bottom offset, while visible presentation disagreed with that geometry. Rectangle intersection alone did not establish pixel visibility.

Removing the outer timeline did not prevent the failure. A separate Metrics-only ScrollView experiment produced an immediate off-viewport blank, then settled to readable content without another UI action. Restoring the original pager in the **04:24 UTC** build reproduced the partial blank, which remained at a later capture around **04:25 UTC** after independent documentation work. These observations identify a navigation acceptance gap; they do not prove a permanent empty-content bug, a framework defect, a timeline cause or physical-device behavior. The earlier horizontal-page and bounce experiments were reverted, and all temporary overlays were removed. See the [dated UI evidence](evidence/watch-recording-skip-ui-2026-10-25.md).

## Behavior

Metrics is now a compact fixed page, with no inner ScrollView. Exercise/set, quantity/target, fresh-or-missing BPM, a small explicit recording action and a short instruction share the page. Missing manual quantities and HR retain their dashes; a red HR value requires an actual fresh reading. The recording action still uses the existing guarded recorder and does not start automatically. Tapping compact Record opens Controls, where recording status/errors appear at the top.

Controls retains its ScrollView, command/confirmation behavior, full recording status/errors, retry action and complete instruction. Its Session details section repeats exercise, quantity/unit, BPM availability and set in scalable text for fuller reading and accessibility. Primary numeric typography is bounded for the fixed dashboard; this is not a global Dynamic Type cap. Long or critical status/discomfort text remains untruncated on Controls. Skipped/discomfort states hide the idle recording instruction as well as the guarded recording action. No telemetry fields, HealthKit permissions, thresholds, persistence or provider calls are added.

The original TimelineView, freshness validation, vertical paging style, page tags and session/generation command guards remain. This does not include the previous style experiments or diagnostic code.

## Observed simulator checks

- The 04:29 build passed two complete Ready Metrics → Controls → Metrics round trips using the reproduced up/down gestures, with both pages visible.
- Temporary largest-text SwiftUI environment overrides in the 04:39/04:40 builds kept Metrics within the 159-point viewport. Full Controls details and instructions were readable through three scrolls. Explicit Record displayed the complete unavailable-Health status, with no fabricated HR. The override was removed before the 04:42 normal build.
- At 04:43, skipped Metrics had no Record; Controls had no Start/Next/Record. End session → Cancel retained the same check-in.
- After the final 04:44 build, skipped Metrics → Controls → Metrics remained visible, including a later fresh capture after independent work. Controls showed the skipped status and End session, without the misleading idle recording note.
- After explicit Finish on iPhone at 04:46, the normal-text Watch page fitted the green completion mark, **Session complete** and **Your review is on iPhone.** The retained 1/3 header denotes the session position, not three completed sets.

These are root's actual build/CUA observations; this document's author did not independently operate the simulator. The [receipt](evidence/watch-compact-navigation-2026-10-25.md) retains unchanged captures and hashes.

## Remaining gates

Physical Crown behavior, Ultra screen fit, Health authorization, actual sensor freshness and workout recording/save require device acceptance. Simulator navigation does not establish these results or independently close #110.
