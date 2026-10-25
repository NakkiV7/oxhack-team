# Session reports

Progress opens a report with the saved history currently on this iPhone. Large
reps, hold seconds and set totals stay separate from recorded active time. Each
set names its exercise, quantity and source; tempo/rest detail, recording
explanations and explicit cloud sync are collapsed. Opening a report or a
disclosure does not request Gemini or upload history.

The local highlight uses recorded evidence only. Pain/discomfort takes priority;
form difficulty or failure receives neutral review copy. Empty work and video
replays receive no activity milestone. First activity means the first non-video
reps/hold in the supplied saved history, not a lifetime first. Without supplied
history, or for a future-dated report, the highlight stays neutral.

A rep best compares the largest current single set with strictly earlier sets
of the same exercise and input source. It does not sum sets, compare manual with
camera, count the current record as a baseline, or claim improved strength or
fitness. Clearing local history also removes those comparison baselines.

Heart-rate and wrist-motion charts retain measured timestamps, deduplication and
blank gaps over 12 seconds. Each chart shows distinct reading count, first-to-last
span and gap count. Span is not continuous coverage; no completeness percentage,
interpolation, exact set boundaries or form judgement is inferred.

Focused behavior checks live in `Tests/Core/WorkoutReportTests.swift`. Run with
`swift test --scratch-path .local/report-polish-build --filter 'report|Report|categoryAndTotals|highlight|firstActivity|difficultOrPainful|signalCoverage|recordedBest'`.
Native compilation, report layout at larger text sizes, disclosure interaction
and simulator acceptance are separate checks owned by the root task.

This report slice changes no persisted-history, Watch telemetry, gateway or Tiger schema. Separate skip metadata is introduced by the adaptive-check-in slice.

Skipped steps appear in their own section with planned exercise/quantity and the explicit choice. They do not appear under completed sets. A skip-only record has a local-history note instead of an upload action; mixed records explain that only completed work can sync. The weekly empty-work message refers to completed sets, so a saved check-in is not contradicted by “no sessions” copy.

Independent source review found no highlight/source/timestamp-comparison defect. Its one wording correction is the weekly completed-set message above. Actual simulator report/disclosure acceptance and the final app build are coordinated separately; provider, sensor and physical acceptance are not claimed.
