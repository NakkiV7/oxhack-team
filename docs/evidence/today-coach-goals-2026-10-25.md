# Today streak and Coach goal presentation

Base: `origin/main` at `bbd28c7`. The existing type is `StreakCard` in `GamificationViews.swift` (there is no `TodayStreakCard` at this revision). Today already renders the selected goal raster icons through `TodayView.trainingRhythm`; no Home changes are required. This patch changes only that card and private `CoachGoalContext` in production sources. Coach settings and skill-tree sources remain untouched.

The weekly label now reads “Weekly target” with a calendar, separated from its count. The header falls back to a vertical stack when its ideal horizontal width does not fit. Completed-today fire keeps the existing green raster; an active protected streak awaiting today's training reuses it with a warm hue; no active streak uses the existing grey raster. Text and VoiceOver explain the state independently of colour. No artwork is generated.

Coach's top context and its existing summary reuse the Strength/Stamina/Mobility/Balance raster images in an adaptive grid, with a calendar beside days/week. Decorative images are hidden from VoiceOver; the group reads its selected goals and weekly target once.

## Root native queue

Prepared before production edits, but **not executed** because root exclusively owns native compilation/simulators. Therefore no observed native red/green, compile, rendering, Dynamic Type or VoiceOver acceptance is claimed. Static checks and shared SwiftPM results are separate evidence.

- `RewardsFlowTests/testTodaySeparatesWeeklyTargetAndExplainsTheMissingStreakWithoutColour`: synthetic UUID data namespace, Today, `app.staticTexts["today-weekly-target"]` label `Weekly target`, value `0 of 3 training days this week`; `app.staticTexts["today-streak-status"]` value `No active streak. No training logged today.`; old combined text absent; rewards button hittable.
- `CoachFlowTests/testSavedProfileFocusAndWeeklyTargetAppearInCoachAndReportContextWithoutSending`: existing profile editing flow, then `app.staticTexts["coach-goal-context"]` and `app.staticTexts["coach-summary-goal-context"]` label `Training goals`, value `Mobility. Weekly target: 4 days per week.` No Send action/provider call.
- Root's profile autosave integration may require replacing this existing test's `save-profile` tap with its updated autosave flow; this branch deliberately keeps current-main profile behavior.

Render on root's existing small iPhone simulator at default and accessibility XXXL text sizes: select Strength, Stamina and Mobility; confirm all three raster icons on Today and at top of Coach; calendar beside Weekly target and days/week; no clipping, compressed text or overlapping chips. Check one selected goal and target 1, then all goals and target 7. Confirm wrapped header/goal rows stay readable and Training rewards remains reachable. Inspect the existing summary context too.

Use isolated synthetic reward histories to check: (1) no streak, grey; (2) protectedStreak > 0 and trainedToday false, warm fire plus explicit active status; (3) trainedToday true, original green fire. Freezes/rest protection still do not claim exercise. VoiceOver should read weekly progress, streak status and goal context without announcing decorative assets twice. Colour rendering remains an actual native render gate.

Skill-tree green completed borders are outside this patch. Coordinate PR129 with root and retain them during integration. This patch has no TestFlight upload; build 5 predates the icon work.

## Executed offline validation

- `swift test --jobs 2`: 125 shared-core behavior tests passed. This does not compile or exercise these SwiftUI changes.
- `bash scripts/check.sh --static`: passed shell/Ruby/JSON/gateway/Pi source syntax checks; does not compile SwiftUI.
- `git diff --check`: passed.
- Native UI tests, actual colour/layout/VoiceOver checks and device acceptance remain pending in root’s queue. No live provider call, Safari action, native build, simulator change, install or upload was performed.
