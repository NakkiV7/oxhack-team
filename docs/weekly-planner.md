# Weekly Coach planner

This local implementation adds an explicit weekly proposal alongside the existing saved workout. Offline contract/native behavior tests, actual simulator approval interaction and an ARM64 container check passed; live weekly Gemini output and physical exercise acceptance are separate gates. No live provider requests were made while implementing this slice.

Tap **Propose my week** to send the current draft, up to 20 recent conversation turns, recorded training facts, selected goals/weekly target and available support through the configured authenticated gateway. The optional profile name is not added automatically. Editing availability or a draft makes no request. The screen reports the operation actually running and offers Cancel; it does not show invented progress stages, private reasoning or a percentage. A retry repeats the failed operation and its captured instructions, rather than sending an earlier chat message.

Nothing in a proposed week is selected by default. Choose workout days, optionally move them to different available dates within that week, then approve and save. Generated exercise quantities are shown for review. Saving does not start a workout or create a history record. Each saved day has a separate **Start this workout** action using the existing configured session; only completed user-recorded work enters history. The separate saved single workout remains intact.

## Contract

Authenticated `POST /v1/week-proposal` uses the existing `generationID`, optional `message`, `history`, `facts` and `availableSupport`, plus:

```json
{"week":{"startDate":"2026-10-25","timeZone":"Europe/London","availableDays":[0,2,4],"targetDays":3}}
```

`availableDays` contains unique zero-based offsets from the chosen starting local date. There are 1–7 available dates and 1–7 requested workout days, capped by availability. Time zones must be recognised. Date arithmetic represents seven consecutive calendar dates across a daylight-saving change; it does not derive recovery or physiological readiness.

A proposed response has `generationID`, `status: "proposed"`, `weekStart`, `timeZone`, exactly seven ordered `days`, grounded `rationale`, and registry `guidanceIDs`. A day contains `date`, `kind: "workout" | "rest"` and `workout` (an existing workout proposal, or `null` for rest). There must be at least one workout and no more than `targetDays`; all workouts must fall on available dates. Each day has at most three unique canonical exercises, with the existing support, unit, quantity, rest and evidence limits. Unknown fields, stale generations, unsupported equipment, invented evidence IDs and invalid dates fail validation on both server and client.

A declined response has only `generationID`, `status: "declined"`, `reason: "unrelated" | "medical" | "urgent"`, and `guidanceIDs`. It cannot carry workout instructions. Native wording is curated for these reasons. Clear current chest-pain reports receive NHS escalation text without calling Gemini; unrelated and treatment requests have bounded refusal scenarios. Negated, quoted and historical symptom mentions are tested separately. Qualifiers bind to the symptom clause: an affirmative current chest symptom wins over an unrelated resolved symptom, an earlier event or a different negated mention. This is not comprehensive symptom screening, diagnosis or permission to resume exercise. Ambiguous language and generated advice still need appropriate scrutiny.

## Guidance and limits

The canonical [guidance registry](../Shared/Core/Resources/coach-guidance.json) is bundled in the app and read by the gateway. IDs resolve to reviewed NHS, NICE and UK Chief Medical Officers titles, URLs, short paraphrases and audience restrictions. The model chooses only known IDs; the UI builds links from registry URLs. Weekly rationale text cannot supply its own HTTP/HTTPS/www links. Urgent declines must include `nhs-chest-pain`. Citations use curated paraphrases, rather than model-generated quotations. General adult guidance is not a measured personal capacity, a compulsory minimum for a beginner, or clinical clearance. NICE body-size context is not an exercise prescription; this slice does not add BMI collection or calculations.

The request and validated response retain the 65,536-byte limit; messages retain the 4,000-character limit. Weekly generation has a 4,096-token output ceiling, existing provider timeout and no automatic retries. The optional owner-demo guard shares its finite nonrefundable provider-attempt budget, one active provider request, expiry and slow-read limits across chat, session proposal, report and weekly proposal. Deterministic refusals make no provider call. Tiger remains disabled when owner-demo mode is configured. A weekly grammar is deeper than a single workout; live Google compatibility and quality are not established by mocked transport tests. [Google documents structured-output schema support and complexity limits](https://ai.google.dev/gemini-api/docs/structured-output).

Approved weeks use a versioned `coach.approvedWeek` local preference, leaving `coach.approvedPlan` and session history unchanged. No server database migration, calendar export, reminder, scheduled execution, automatic completion matching or cloud synchronisation is added.

## Verification

RED receipts are retained privately under `.local/`: the new route returned 404, shared types were missing, and native compilation reported the missing weekly model API before implementation. Additional behavior failures demonstrated acceptance of invented source URLs, urgent refusals without the chest-pain reference, and a negation in another symptom clause masking current chest pain; focused fixes followed each failure.

- Server: `cd server && npm test`: 74/74 passed; weekly route/source checks (5) and scope scenarios (6) use mocked provider transport and no database.
- Shared: `swift test --scratch-path .local/weekly-core-build --filter CoachWeekPlanTests`: 4/4 passed after the strict decoder fixes. Full-suite verification is coordinated with the concurrent report changes before publication.
- Native: the later coordinated run passed 19 Coach, 11 configured-session and 7 lesson behavior tests without warnings (`test_sim_2026-10-25T02-57-43-566Z_pid4129_ad484f6a.log`). The subsequent actual app build succeeded at 03:23. These use fake transport, not a live weekly request.
- [Actual simulator approval receipt](evidence/coach-week-approval-ui-2026-10-25.md): one explicit fixture request, no days selected by default, one selected day moved and approved, separate Start action, no workout started. Preferences restored and fixture stopped; zero provider calls. Prior-conversation and saved-day Start interaction were not exercised in this pass.
- [Fresh ARM64 container receipt](evidence/container-weekly-verification-2026-10-25.md): 23 runtime hashes matched, including guidance; restricted runtime and HTTP boundaries passed. Fake weekly output accepted, invented guidance rejected, zero external calls. AMD64/hosted HTTPS remain unverified.
- Live weekly Gemini, physical/device and clinical acceptance remain pending; not claimed by these tests.
