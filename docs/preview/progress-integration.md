# Preview progress integration

Route **only** the explicitly enabled preview store to:

```swift
DemoProgressView(store: store, profile: profileStore.profile)
```

The caller owns mode isolation and seeding. This view never seeds, persists, connects a device or makes a provider request. It consumes `store.history`, shows an empty state for empty input and sorts every workout list by newest date first. Weekly totals/mix come from `WeekReport`, so the visible week follows the existing calendar interval rather than claiming a rolling seven-day total.

Requires the coordinated fixture lane's `DemoPreviewData.insight(for:) -> DemoPreviewInsight?` contract. The fixture API guards exact sample records; unknown or modified records show factual totals without a grade. The numeric ring is clamped to 0–100, alongside the letter grade. Green denotes 80+, amber 60–79, red below 60; grade, number and accessible spoken label communicate the result without relying on colour. The displayed grade explanation includes the A+ through D− scale and explicitly identifies authored sample effort rather than health/readiness.

Workout cards open an insight containing the authored summary/rationale, separate effort and achievement scores and actual `WorkoutReport` set facts. **Open full workout report** reuses `SessionReportView`; that existing screen offers optional user-triggered Gemini generation, with no automatic generation on navigation. No report, store, profile or project file is changed by this lane.

## Coordinated verification

`Tests/UI/DemoProgressFlowTests.swift` was written before implementation. Native compilation and simulator execution are reserved to the integration chat and have **not** been performed in this lane. Root should include the source/test files through its project generator and execute:

```
SpottrUITests/DemoProgressFlowTests/testFreshProgressHasNoPreviewAndExplicitPreviewOpensSampleInsights
```

The test uses a unique data namespace, verifies normal empty progress, explicitly enables account preview, opens Insights, taps its first sample workout and opens the existing full report. Account toggle integration is `testflight-preview-toggle`.

| Selector | Meaning |
| --- | --- |
| `demo-progress-dashboard` | Preview overview scroll view |
| `demo-progress-empty` | Empty history state; no fixture fallback |
| `demo-progress-week` | Current calendar week's actual totals |
| `demo-progress-workout-mix` | Sets by workout category |
| `demo-progress-insights` | Direct Insights navigation |
| `demo-progress-workout-<UUID>` | Recent workout navigation |
| `demo-workout-insights` | Insights list, newest first |
| `demo-insight-workout-<UUID>` | Insights workout navigation |
| `demo-workout-detail-<UUID>` | Sample workout detail |
| `demo-workout-full-report` | Existing report navigation |
| `demo-grade-explanation` | Sample scoring explanation |

Visual checks pending integration: small iPhone and accessibility text sizes, VoiceOver labels, workout order against fixture dates, zero-history preview, and mode switching back to unchanged real history. No physical, provider or deployed acceptance is claimed.
