# Paired Watch simulator acceptance

Scope: Spottr running through a paired iPhone/46mm Apple Watch simulator session on 24 October 2026. This is simulator UI and companion-command evidence. It does not establish physical Watch pairing, HealthKit sensor capture, clinical accuracy or release acceptance.

## Observed walkthrough

The root session reports exercising Pause, Resume, End set, Next set and Finish through the paired-simulator workflow. These observations belong to that walkthrough; the layout-editing agent did not repeat it or run another build. No additional repetition counts, timings or sensor values are inferred here.

| Control | State to verify in the paired workflow |
|---|---|
| Pause | Session pauses and the prominent control becomes Resume. |
| Resume | Session returns to active and the prominent control becomes Pause. |
| End set | The ended set reaches the phone and the Watch offers Next set. |
| Next set | The next set becomes available through the paired session. |
| Finish | The Watch shows Session complete and directs review to iPhone. |

The initial footer contrast check failed visually: Next set existed in accessibility but black text inherited onto its black prominent capsule. The subsequent paired-simulator screenshot showed a readable white Pause label after an explicit white foreground was applied to prominent controls. Bordered controls retained black labels.

Session screenshot references, currently temporary files:

- Contrast RED: `/var/folders/zs/2tq7h99n0g9drgncqt4crppr0000gr/T/screenshot_optimized_30541af3-d0a1-4746-85ae-1fe38fe66f90.jpg`.
- Contrast GREEN / compact-layout RED: `/var/folders/zs/2tq7h99n0g9drgncqt4crppr0000gr/T/screenshot_optimized_86e1d060-ad04-456d-bb74-595c45059b48.jpg`. Pause is readable, while the cue and HR row require scrolling below the initial viewport.

## Compact-layout target

The active layout now uses one caption-sized brand/exercise header, a 36-point base counter that scales with Dynamic Type, three-point internal spacing, the HR row immediately after the count, then the cue. The footer remains pinned through `safeAreaInset`. Idle and completed screens retain their separate brand heading. Secondary recording/finish actions and status remain scrollable below the essentials.

Manual GREEN acceptance remains pending root's build and screenshots:

- At default Dynamic Type on the 46mm Watch, active Squats shows the header, count/target, complete cue, HR row and footer without scrolling, overlap or clipping.
- A configured timed hold shows observed active seconds and its seconds target, the complete hold cue, HR row and appropriate Start/Pause/Resume/End controls.
- Paused and rest states show their current instructions and readable Resume/Next set controls.
- At larger Dynamic Type or with a long exercise/cue, full text remains reachable by scrolling. There are no fixed content heights, forced tiny text scales or cue truncation limits.
- Footer command behavior remains consistent with the paired workflow above.

HR is displayed as `— bpm` when no fresh valid Watch reading is available. That is missing data, not a zero reading or simulated biometrics. Simulator command/UI acceptance must not be presented as evidence of a real Watch recording heart rate or motion.

## Follow-up acceptance, 24 October 2026 20:48 UTC

A fresh Device Hub walkthrough exposed the complete ready cue falling below the footer at default size. The follow-up removes unused navigation, shares one header row between exercise and HR, uses a 32-point scalable count, and shows brief Watch-specific cues. The final default-size Squats screen now shows the exercise, missing-HR marker, count/target, entire cue and both readable footer controls without scrolling. Secondary recording remains below the first viewport. See [the actual simulator screenshot](evidence/watch-compact-2026-10-24.jpg).

The exact staged Watch simulator build passed without warnings (`build_sim_2026-10-24T20-47-53-144Z_pid4129_422c5f40.log`). Configured timed-hold and larger Dynamic Type screenshots remain pending; the scrolling path is retained. The seven callback-lifecycle cases and 142-case shared suite pass separately; these do not substitute for physical HealthKit acceptance.
