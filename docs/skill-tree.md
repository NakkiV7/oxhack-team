# Skill tree

Skills offers a connected grid and a linear list of the same 19 exercises. The chosen layout is remembered locally. Every node opens its exercise instructions and logging controls, including challenges whose prerequisites are pending.

Both layouts distinguish Earned (green seal), Available (blue circle), Locked (darkened card and lock), and Preview (open lock, explicitly not earned). The existing catalogue supplies levels I–V where those levels exist; shorter families keep their real catalogue length. Raster exercise artwork is reused. The linear tree names every remaining prerequisite and shows separate manual/camera goal-set counts. Grid nodes announce those counts and remaining prerequisites to VoiceOver; exercise details show each parent's earned state.

Grid cards scale with the standard text sizes and pan horizontally on narrow screens. At accessibility text sizes Skills shows the wrapping linear tree and a single XP column automatically, without overwriting the saved grid/linear preference. The legend wraps vertically when it cannot fit across the screen.

Earn a challenge with three goal-meeting sets across two local calendar days, plus all of its incoming prerequisites. The graph combines each family's earlier level with selected supporting challenges: plank supports push-ups, side plank supports close-grip push-ups, balance supports reverse lunges, mobility supports assisted single-leg squats, and plank supports mountain climbers. Practice before unlocking is retained.

A green connection means its source prerequisite is earned. A challenge with two parents can therefore have one green connection while remaining locked until the other parent is earned. Preview access never colours a connection green. An earned-state change has one 0.35-second colour/width transition, disabled by Reduce Motion; there is no continuous pulse or animation on entry.

Manual and camera sets contribute with their source shown in exercise details. Video replays and discomfort-stopped sets do not earn challenge progress. XP remains a deterministic game score, not a measured strength, recovery or readiness estimate. The graph controls achievements; it does not restrict which exercises someone can practise.

Manual evidence is self-report; camera counts do not certify form or fitness. Optional onboarding baseline answers suggest practice only, without awarding sets, days, points, connections or achievements. Preview access also leaves earned progress unchanged.

Add exercises in `ExerciseCatalog`, prerequisites in `SkillGraph`, and behavior cases in `SkillGraphTests`. Keep edges acyclic and check both layouts. This is the first unreleased graph version; changing its prerequisites can change previously computed completion states.

## Verification and coordinated native acceptance — 25 October 2026

Core regression cases cover partially earned branching prerequisites, invalid/nonexistent connections, preview without grants, mixed manual/camera achievement evidence, replay exclusion, local-day requirements, prerequisite gating and baseline suggestions without earned progress. The two new cases were authored first; the focused RED failed on the absent `pendingPrerequisiteIDs` / `isConnectionEarned` APIs, then both passed after implementation.

Executed on this PR's isolated worktree:

- `swift test --scratch-path /tmp/spottr-skill-tree-red`: 90 XCTest and 125 Swift Testing cases passed, no failures or compiler warnings.
- `./scripts/check.sh --static`: passed shell/Ruby/JSON/gateway/Pi syntax checks.
- `cd server && npm ci --ignore-scripts --no-audit --no-fund && npm test`: 85 offline tests passed.
- `python3 -m unittest discover -s hardware/pi -v`: 23 offline tests passed.
- `git diff --check`: passed.

Native build, simulator execution and visual acceptance for this polish are pending the primary chat's shared queue. No project, signing, TrainingStore, profile or onboarding edits are required. Existing Swift files were edited in place; project regeneration is unnecessary for this PR. Run these exact selectors using the existing iPhone simulator:

```text
SpottrUITests/SkillsFlowTests/testLinearTreeExplainsLocksAndPreviewWithoutEarningChallenges
SpottrUITests/SkillsFlowTests/testAccessibilityTextUsesLinearTreeWithoutChangingSavedLayout
SpottrUITests/SkillsFlowTests/testExpandedGridPreviewNeverClaimsEarnedProgress
SpottrUITests/SkillsFlowTests/testTreeAndLinearViewsShareExerciseDetailsAndRememberSelection
SpottrUITests/SkillsFlowTests/testManualTrainingEarnsVisibleProgressAndPersists
SpottrUITests/SkillsFlowTests/testOptionalOnboardingBaselineSuggestsPracticeWithoutLoggingSets
```

Visual checks still required: narrow-screen collapsed/expanded grid panning through levels I–V and cross-family edges; legible dark locked cards versus earned/available/preview; standard and largest accessibility text without clipping; VoiceOver reading order, lock hints and source counts; a partially earned two-parent branch; no motion on entry/preview; a single transition on actual earning and no transition with Reduce Motion on. Use isolated synthetic history for earned states, never real workout data or fabricated device evidence. Existing UI coverage predates this polish and does not establish acceptance of these changes. No physiological or camera-accuracy validation is implied.
