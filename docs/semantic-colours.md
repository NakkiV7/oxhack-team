# Semantic colours

The white theme keeps dark body text and uses restrained colour for actions and existing state. This is a presentation change: workout counts, targets, timing, source labels, skill rules and provider requests are unchanged.

| Meaning | Colour | Redundant information |
| --- | --- | --- |
| Primary action, selected control, available challenge | Blue `#245FC7` | Action title, selection/check icon and existing accessibility state |
| Completed/saved state or existing controlled-form cue | Green `#26745A` | Completion/checkmark or the unchanged observed cue text |
| Tracking, alignment or slower-rep adjustment | Amber `#8A6116` | Existing adjustment text; no recovery estimate |
| Stop, error and heart-rate category | Red `#AC3535` | Stop/error text; heart icon and bpm label for readings |
| Prerequisites pending or unavailable value | Muted `#62676E` | Lock/status icon, source text or missing-value placeholder |

Heart-rate colour identifies the data category, never a safe/unsafe zone or physiological recovery. Missing readings remain neutral. Weekly activity and wrist-motion charts use blue; heart-rate traces use red. Existing timestamps, gap segmentation, units and absence messages remain intact.

Camera badges use a pale blue tint; Manual and Video stay neutral. Their source text remains explicit. These colours do not rank measurement accuracy or turn manual/replay input into verified exercise. Saved-plan green means the save/approval state, not completed training.

Nominal solid-colour contrast is at least 5:1 against white and the existing `#F5F5F4` surface. White primary-button text on blue is approximately 5.94:1. These calculations do not replace inspection of actual rendered controls and disabled states.

## Acceptance and rollout

The visual RED was the observed black primary actions/heart-rate presentation and inconsistent available-skill colours. No token-mirroring tests were added. The foundation (palette, primary buttons, app tint and catalogue selections) passed the native phone build without warnings at 02:58 UTC. Actual CUA interaction verified blue Today/End/Done actions and a clearly disabled empty manual-entry action. Screen-specific changes ship with the separate Coach, report, profile and skill PRs; their acceptance is recorded in those guides.

| Screen/state | Check | Evidence |
| --- | --- | --- |
| Today, catalogue and Coach | Blue actions/selections; white labels; disabled states and catalogue keyboard/Start remain usable | Pending root build/visual receipt |
| Skills grid/list/detail | Green complete, blue available, muted prerequisites; existing labels/icons and practice access retained | Pending root visual receipt |
| Configured workout/rest/stop | Neutral missing HR; red observed HR icon/stop; typed adjustment colours; unchanged quantities/controls | Pending root visual receipt |
| Reports and profile/onboarding | Labelled red HR vs blue activity/motion; truthful source badges; selected/completed markers and readable text | Pending root visual receipt |

The Watch now uses a separate native black paged layout; see [Watch pages](watch-pages.md). Legacy live heart-rate emphasis and source-specific cue colour remain follow-up visual checks. Physical sensors, app installation, exercise accuracy and audible acceptance remain separate from this visual pass.
