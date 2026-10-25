# Synthetic preview fixtures

`Shared/Core/DemoPreviewData.swift` is a pure opt-in data factory. It has no storage, file, device or network access. It does not seed history or change a profile. The app owner must enable preview explicitly and persist these objects only in the separate preview directory; fresh real profiles remain empty. Mode switching and preservation of real data belong to app integration.

Public contract:

- `DemoPreviewData.sessions(referenceDate: Date, calendar: Calendar = .current) -> [SessionRecord]`: seven synthetic sessions, oldest first, at calendar-day offsets −6 through 0. Inject both date and calendar in tests. IDs remain stable across calls and date shifts so reseeding can deduplicate them. A non-finite date returns no sessions.
- `DemoPreviewData.profile: LocalProfile`: Demo Alex, four-day goal, strength/mobility interests; no body measurements.
- `DemoPreviewData.insight(for: SessionRecord) -> DemoPreviewInsight?`: returns authored content only when ID and all fixture facts match. Modified fixtures and real records receive nil. Public fields: `sessionID`, `title`, `summary`, `grade`, `score`, `rationale`, `achievementScore`, `effortScore`, `sourceLabel`.

Render `sourceLabel` (Synthetic preview) with insights. Every session, including camera-source examples, is fictional. Existing `WorkoutReport(record:)` reads the same repetitions, holds, times and sources. Manual logs use self-report origin and never acquire camera tempo. Camera examples cover only supported push-ups/squats. No Watch, heart-rate, energy, motion, health or readiness fixtures are generated because the existing signal schema identifies real Watch providers.

Achievement is the rounded mean percentage of each set target completed (each capped at 100%). Effort is an explicitly authored demo value, not a sensor estimate or a real user's report. Score is their integer mean. Display grades span A+ to D− using thresholds 97/93/90, 87/83/80, 77/73/70, 67/63/below; grades assess only the fictional plan completion and authored effort. Seven examples progress from D− to A+ without changing how real sessions are evaluated. Do not use this API to grade real users.

Core selector: `swift test --filter DemoPreviewTests`. The suite covers reproducible calendar dates across the UK clock change, globally unique fixture IDs, Codable reopening, truthful report projections, absent physiology, guarded insight lookup, and lack of automatic real-history population. Native UI, mode switching and physical camera/device acceptance require the primary integration lane; this fixture work provides no such acceptance evidence.
