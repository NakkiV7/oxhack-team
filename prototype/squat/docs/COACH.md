# The connected coaching journey

Profile and goals → personalised programme → camera assessment of a supported node → one cue → retry → measured comparison → saved evidence → skill progress → session report → weekly review → accepted goals. Built into the squat browser prototype and its server, on the Tiger Data stream that already holds every frame, rep and forecast. Code: [`coach.mjs`](../coach.mjs) (domain rules), [`coach-loop.mjs`](../coach-loop.mjs) (state machine), [`coach-gemini.mjs`](../coach-gemini.mjs) (context builder and six validated Gemini calls), [`coach-store.mjs`](../coach-store.mjs) (Tiger persistence), [`coach-service.mjs`](../coach-service.mjs) (reports and the weekly job), routes under `/coach/*` in [`server.mjs`](../server.mjs), the journey page [`coach.html`](../coach.html), and the loop card in [`index.html`](../index.html). Schema: [`prototype/shared/db/004_coaching.sql`](../../shared/db/004_coaching.sql).

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

Only `squat` and `pushup` have a measured contract (`CONTRACTS` in `coach.mjs`): squat lowering time (target 1.5 s, tolerance 0.15 s, pass = median within tolerance over three counted reps), push-up rep time (target 2.0 s, tolerance 0.25 s; the push-up counter has no phase durations, so the contract uses the whole rep and says so). Every other catalogue entry is practice-only: the tree labels it "AI assessment coming soon", allows practice logging, and the assessor is never invoked for it. Three logged practice sets complete a practice-only node (and unlock its dependents) without ever marking it verified.

## 3. Shared data

All of it is in the `spottr_cv` schema beside the stream: `profile` (timezone, survey, accepted goals), `programme` (versioned graph and rationale, provenance gemini or catalogue-fallback, active or superseded), `node_progress` (availability, practice, verification, exact qualifying evidence, criteria version, XP, badges), `coaching_attempt` (frozen target, baseline and retry reps, cue, computed outcome, Gemini explanation, interventions, status), `session_report`, `weekly_report` (period, timezone, cutoff, input fingerprint, status pending/generating/ready/failed/stale, facts, narrative, proposed goals, research refs), `research_source` (hash-keyed, origin discovered or supplied, access level, findings with page evidence). Reps and forecasts are referenced by workout id, never copied. Writes are keyed: a finished attempt never moves backwards, practice is counted once per workout, an assessment and the progress it earns commit in one transaction, the same weekly inputs produce the same report.

## 4. Coach → retry → verify

States: setup → baseline → preparing_cue → cue_ready → ready_to_retry → retry → verifying → result, plus paused and cancelled. The camera must be running with hips and knees tracked before the baseline starts. Three counted reps with the metric measured make the baseline; the loop asks the server for one cue (Gemini call 1, validated: allowed action, correct target id, real evidence ids, no numbers that are not in the evidence, `maintain_target` only when the baseline already meets the target; otherwise the deterministic cue); the target and rule are frozen when the cue arrives; the person presses **Start retry**; three counted retry reps; the application computes the comparison (median absolute error against the target over all valid reps, "similar" within half the tolerance, "unable" below three valid reps or when the retry moved through less than 85% of the baseline range); the attempt and the node progress it earns are saved together; Gemini call 2 explains the computed result and cannot change it. Stop is always available. A camera interruption pauses; a camera change after the baseline makes the attempt unable to assess. The baseline already meeting the target yields `maintain_target` and still counts as evidence. An HRT cue delivered during the attempt is recorded on it.

## 5. Reports and the weekly review

Session report: calculated facts with ids (duration, exercise, counted reps, median lowering, clean-form count, each coaching attempt's medians and result, forecasts stored and resolved, biometrics explicitly absent), a timeline (reps, cues, attempts), and an optional Gemini narrative generated once and saved apart from the facts. Weekly review: the most recently completed calendar week against the one before, in the profile's timezone (or the week in progress on request, labelled as such); facts for coverage, reps by exercise, comparisons with no percentage from a zero baseline, coaching attempts by result, verified milestones, accepted goals, biometrics; a Gemini narrative and one to three proposed goals validated against the programme (kinds practice_node, repeat_assessment, metric_target, practice_preparation; counts 1 to 14); research references from the saved collection; "why this goal?" answered from the report's facts only. Goals change nothing until accepted; accepted goals are stored on the profile and feed the next programme generation. Generation is idempotent by user, period and input fingerprint; a concurrent request shares the row; new data makes the old report stale and yields a new version. The job entry point: `node coach-weekly-job.mjs [user]`.

## 6. Research

Discovery uses Gemini with search grounding; only sources the search actually returned are kept, as metadata-level sources with the grounding entry point. A supplied PDF (under 8 MB) is read once by hash: question, design, population, intervention, outcomes, findings, limitations, relevance, quoted passages with page numbers, and whether the full text or only an abstract was available. Documents are evidence, not instructions. Weekly reviews cite saved sources by id only when a sentence rests on them.

## 7. Run and demo

```bash
cd prototype/squat && npm run ui          # http://localhost:3002/coach is the journey, / is the camera page
```

`SPOTTR_USER_ID` names the local user (default `nakki`); `?user=demo` switches to the demo account. Demo: Profile → save → Generate my programme → Programme tab → **Assess with camera** on Squats → camera on, three reps, cue spoken, **Start retry**, three reps, result and milestone → Reports → the session report → Weekly review → **Review this week so far** → expand a research citation (after adding a paper or a search) → **Why this goal?** → accept a goal → Profile shows it. "About the same" and "unable to assess" are valid results and look intentional.

## 8. What is measured, what is generated

Measured: every number (phase durations, medians, errors, counts, XP, dates). Generated: the cue wording, the explanation wording, the programme's node selection and wording within the catalogue, narratives, proposed goal wording, document summaries. Every generated text cites fact or evidence ids and is rejected when it cites unknown ids or states numbers that are not in the facts.

## 9. Tests

`test/coach.test.mjs`: capabilities, programme validation and fallback placement, comparison classes and the shorter-retry refusal, deterministic cue, node contract and idempotent rewards, the state machine (late and foreign cues, frozen target, pause, camera change, cancel), facts and week boundaries, goal validation, Gemini validation and fallbacks with a fake provider, keyed store writes.
