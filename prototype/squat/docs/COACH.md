# The connected coaching journey

Profile and goals → personalised programme → camera assessment of a supported node → one cue → retry → measured comparison → saved evidence → skill progress → session report → weekly review → accepted goals. Built into the squat browser prototype and its server, on the Tiger Data stream that already holds every frame, rep and forecast. Code: [`coach.mjs`](../coach.mjs) (domain rules, placement, levels and attributes), [`coach-loop.mjs`](../coach-loop.mjs) (state machine), [`coach-gemini.mjs`](../coach-gemini.mjs) (context builder and six validated Gemini calls), [`coach-store.mjs`](../coach-store.mjs) (Tiger persistence), [`coach-service.mjs`](../coach-service.mjs) (reports and the weekly job), routes under `/coach/*` in [`server.mjs`](../server.mjs), the journey page [`coach.html`](../coach.html) with its modules in [`coach-ui/`](../coach-ui) (map, survey, reports, emblems), and the loop card in [`index.html`](../index.html). Schema: [`prototype/shared/db/004_coaching.sql`](../../shared/db/004_coaching.sql).

## 1. Implementation map

| Area | Status | Where |
|---|---|---|
| Squat and push-up tracking, rep events with phase durations | reuse as-is | `squat.mjs`, push-up prototype |
| Tiger stream (frames, reps, workouts, HRT predictions and outcomes) | reuse as-is | `prototype/shared` |
| Exercise catalogue and prerequisite graph (19 exercises, the native app's ids and rules) | mirrored, not duplicated as a second source: the native `ExerciseCatalog`/`SkillGraph` stay authoritative for the native app; this copy carries the same ids, levels and support links | `coach.mjs` |
| Gemini gateway contracts (facts with ids, outputs that cite them) | extended: the same grounding rule, new structured calls | `coach-gemini.mjs` |
| Cue scheduler and voice | reuse as-is: the coaching cue and the explanation go through the page's `say()` queue with the same priorities, cooldown and stop | `index.html` |
| HRT forecasts | reuse: a predictive cue delivered during an attempt is recorded as an intervention on the attempt; forecasts of the set appear in the session report | `index.html`, `coach-service.mjs` |
| Skill tree with persisted progress, XP, badges, unlocks | new (the native tree is local and unpublished) | `coach.html`, `node_progress` |
| Coach → retry → verify | new | `coach-loop.mjs`, loop card |
| Session report, weekly review, goal acceptance | new | `coach-service.mjs`, `coach.html` |
| Research discovery and supplied-PDF analysis | new | `coach-gemini.mjs`, `research_source` |
| Biometrics | unverified upstream: no Watch or Presage readings exist in Tiger; reports say so explicitly and never substitute zeros | |
| Native app integration | not done: the native app has no Tiger connection and cannot be built on this machine; the journey lives in the browser prototype | |

## 2. Capability boundary

Every catalogue exercise has exactly one capability (`capability()` in `coach.mjs`), shown as a badge on the map and in the step panel:

| Capability | Exercises | What the app does |
|---|---|---|
| Camera assessment | squat | The squat page times the lowering phase and runs coach → retry → verify; passing verifies the step. Contract: target 1.5 s, tolerance 0.15 s, median of three counted reps. |
| Camera counting | push-up | The push-up page at :3001 counts reps; inside the path the step is logged as practice. It never opens the squat assessor. |
| Practice log | everything else | Self-reported practice. Practice counts once per calendar day in the profile's timezone (key `node:YYYY-MM-DD`); three practice days complete the step and unlock its dependents. It is never shown as AI-verified. |

The squat page also refuses to start the loop for any node that is not an assessable squat, whatever the link says.

## 2a. The training path (Programme screen)

**Survey ("Build my training path").** Six stages and a review: goal (squat or push-up path), starting point (concrete statements such as "I can squat, but want help with control", or "I'm not sure"), an optional camera check, what is nearby (wall, raised surface, stable support), routine (minutes and sessions per week), and focus, coaching style and movements to leave out. Answers are saved as they are given (`POST /coach/survey`), so closing and coming back resumes. The review lists every answer with an Edit link that returns to the review. Answers from the earlier survey (a band such as "intermediate", style "direct") are mapped onto today's options.

**Placement.** `placeStart()` turns the answers into the furthest start they support and the list of allowed starts. "Not sure", "new" or a left-out movement start at the foundation. A camera check counts only with three valid squats recorded under node `placement-check` in the last seven days; the camera page opens it with `/?check=squat`.

**Gemini, within bounds.** `generateProgramme()` sends the usable catalogue (equipment and left-out movements already removed, each entry with its capability, criteria and allowed prerequisites) and the answers. Gemini picks the steps, the optional branch, the start, the practice targets and the wording. It must use the rule's start unless the focus is "learn the movement" or the answer is "not sure". `validateProgramme()` checks ids, links, the optional branch (it gates nothing and names the step it supports), targets (sets 1 to 4, at most 1.5 times the catalogue goal, no more sessions than planned), equipment, left-out movements and the route. One repair attempt follows a failure; after that the catalogue fallback is used and labelled as such.

**Preview, then save.** `POST /coach/programme/preview` generates without saving and returns the graph, the rationale, the provenance and a diff against the active version: start and goal changes, new steps, steps leaving, progress carried over, and progress kept in history. Nothing changes until **Start my path** or **Save as version N** (`POST /coach/programme/accept`, which validates again). Saving copies progress rows for every step the new version keeps, in the same transaction, and never deletes the old version. There is no one-click regenerate.

**Map.** `coach-ui/map.mjs` lays the graph out from the graph alone (main chain by catalogue level, side steps in their own lanes), so progress never moves a node. Horizontal when the whole path fits at 72% scale or better, vertical otherwise. Node shapes: crest for the goal, hexagon for camera milestones, circle for practice steps, a smaller violet circle for the optional branch. States: current, available, verified, practice complete, not required for your start, locked. Every node is a button with a full text label; arrow keys move between steps, Home jumps to the current step, End to the goal, Enter opens the step. **List view** shows the same steps as a list.

**Step panel.** Why this step, what to practise (sets, reps, sessions per week), what comes before (with Go links), how it completes, how it is assessed, and the rewards. The main action depends on state and capability: **Go to …** for a locked step, **Assess with camera** for squats, **Log practice** otherwise, and a disabled **Logged today** once today's practice is in. On narrower screens the panel becomes a bottom sheet.

**Level and attributes.** The programme level is a game score: practice days +10 XP, first verified completion +50, verified again on a second day +100; level L starts at 50·L·(L−1) XP. It counts across all versions and is never presented as fitness. The three attributes are measured separately and each has a "How is this calculated?" note:

| Attribute | Calculation | Shown when |
|---|---|---|
| Tempo | share of timed squats in coaching attempts in the last 30 days within the tolerance of the target | at least 3 timed squats |
| Consistency | share of those squats within ±10% of the person's own median | at least 5 timed squats |
| Practice | days this week with logged practice or an assessment, against planned sessions | always |

Without enough evidence an attribute reads "Not assessed yet".

**Motion and access.** Unlock, XP and attribute changes animate once, from a per-user snapshot in the browser. `prefers-reduced-motion` turns every animation off and keeps the map fully drawn. The page works from the cached copy when the server is unreachable, with actions paused.

## 3. Shared data

All of it is in the `spottr_cv` schema beside the stream: `profile` (timezone, survey, accepted goals), `programme` (versioned graph and rationale, provenance gemini or catalogue-fallback, active or superseded), `node_progress` (availability, practice, verification, exact qualifying evidence, criteria version, XP, badges), `coaching_attempt` (frozen target, baseline and retry reps, cue, computed outcome, Gemini explanation, interventions, status), `session_report`, `weekly_report` (period, timezone, cutoff, input fingerprint, status pending/generating/ready/failed/stale, facts, narrative, proposed goals, research refs), `research_source` (hash-keyed, origin discovered or supplied, access level, findings with page evidence). Migration `005_path_v2.sql` adds `node_progress.practice_log`, the list of daily practice keys. Reps and forecasts are referenced by workout id, never copied. Writes are keyed: a finished attempt never moves backwards, practice is counted once per workout, an assessment and the progress it earns commit in one transaction, the same weekly inputs produce the same report.

## 4. Coach → retry → verify

States: setup → baseline → preparing_cue → cue_ready → ready_to_retry → retry → verifying → result, plus paused and cancelled. The camera must be running with hips and knees tracked before the baseline starts. Three counted reps with the metric measured make the baseline; the loop asks the server for one cue (Gemini call 1, validated: allowed action, correct target id, real evidence ids, no numbers that are not in the evidence, `maintain_target` only when the baseline already meets the target; otherwise the deterministic cue); the target and rule are frozen when the cue arrives; the person presses **Start retry**; three counted retry reps; the application computes the comparison (median absolute error against the target over all valid reps, "similar" within half the tolerance, "unable" below three valid reps or when the retry moved through less than 85% of the baseline range); the attempt and the node progress it earns are saved together; Gemini call 2 explains the computed result and cannot change it. Stop is always available. A camera interruption pauses; a camera change after the baseline makes the attempt unable to assess. The baseline already meeting the target yields `maintain_target` and still counts as evidence. An HRT cue delivered during the attempt is recorded on it.

## 5. Reports and the weekly review

Session report: calculated facts with ids (duration, exercise, counted reps, median lowering, clean-form count, each coaching attempt's medians and result, forecasts stored and resolved, biometrics explicitly absent), a timeline (reps, cues, attempts), and an optional Gemini narrative generated once and saved apart from the facts. Weekly review: the most recently completed calendar week against the one before, in the profile's timezone (or the week in progress on request, labelled as such); facts for coverage, reps by exercise, comparisons with no percentage from a zero baseline, coaching attempts by result, verified milestones, accepted goals, biometrics; a Gemini narrative and one to three proposed goals validated against the programme (kinds practice_node, repeat_assessment, metric_target, practice_preparation; counts 1 to 14); research references from the saved collection; "why this goal?" answered from the report's facts only. Goals change nothing until accepted; accepted goals are stored on the profile and feed the next programme generation. Generation is idempotent by user, period and input fingerprint; a concurrent request shares the row; new data makes the old report stale and yields a new version. The job entry point: `node coach-weekly-job.mjs [user]`.

Both reports are laid out to be read, not scanned for numbers: a one-line headline, stat tiles (with week-on-week changes on the review, and no percentage from a zero week), a lowering-time chart with the target band, each coaching attempt as a before/after line against the target, "What stood out" cards that cite their facts, and next week's quests as editable cards. The full list of calculated facts stays one click away at the bottom.

## 6. Research

Discovery uses Gemini with search grounding; only sources the search actually returned are kept, as metadata-level sources with the grounding entry point. A supplied PDF (under 8 MB) is read once by hash: question, design, population, intervention, outcomes, findings, limitations, relevance, quoted passages with page numbers, and whether the full text or only an abstract was available. Documents are evidence, not instructions. Weekly reviews cite saved sources by id only when a sentence rests on them.

## 7. Run and demo

```bash
cd prototype/squat && npm run ui          # http://localhost:3002/coach is the journey, / is the camera page
```

`SPOTTR_USER_ID` names the local user (default `nakki`); `?user=<any id>` opens another account, and a new id starts at the empty state. The judges' click path is in [DEMO.md](DEMO.md).

Routes: `GET /coach/me` (profile, active programme with progress, level, attributes, catalogue with capabilities, contracts), `POST /coach/survey`, `POST /coach/programme/preview`, `POST /coach/programme/accept`, `POST /coach/practice`, plus the report, weekly, goal, research and attempt routes described below.

## 8. What is measured, what is generated

Measured: every number (phase durations, medians, errors, counts, XP, dates). Generated: the cue wording, the explanation wording, the programme's node selection and wording within the catalogue, narratives, proposed goal wording, document summaries. Every generated text cites fact or evidence ids and is rejected when it cites unknown ids or states numbers that are not in the facts.

## 9. Tests

`test/path.test.mjs`: criteria versions, ability bands, distinct valid paths for five survey profiles, placement with and without a camera check, validation rejections, levels, attributes, the version diff, Gemini bounds and fallback with a fake provider, the daily practice key, progress carry-over on save, and the deterministic map layout and node states.

`test/coach.test.mjs`: capabilities, programme validation and fallback placement, comparison classes and the shorter-retry refusal, deterministic cue, node contract and idempotent rewards, the state machine (late and foreign cues, frozen target, pause, camera change, cancel), facts and week boundaries, goal validation, Gemini validation and fallbacks with a fake provider, keyed store writes.
