# Demo app: Omar's build plus the training path and Insights

Branch `nakki/app-demo` is Omar's latest native build (`feat/native-demo-ready`, preview workspace, demo Coach, voices,
Presage, dual camera, measurements) with current `main` merged (Misha's calendar and statistics work) and exactly three
additions. Nothing of Omar's build is removed or restyled.

| Area | `feat/native-demo-ready` | This branch |
| --- | --- | --- |
| Today, Progress, Coach, preview mode, voices, camera | As built | Unchanged |
| Skills tab | Challenge tree | The same tree until a path is built, then the personalised training path; the tree stays under "All challenges" |
| Bottom menu | Today, Progress, Skills, Coach | Today, Progress, Skills, **Insights**, Coach |
| Reports, weekly review, research | Session reports under Progress; weekly summary under Coach | Also together in Insights: every session report, the weekly review with quests, and the research library |
| Calendar | Web page only (`landing/calendar.html`) | Insights → Calendar, from the phone's own history: month grid, day details, streaks, five-week heatmap. No Tiger card. |

## The additions

- **Skills tab**: survey, Gemini plan checked by the app with the catalogue path as a labelled fallback, preview with what changes, skill map or list, step sheet, level and measured attributes. Details in [training-path-skills.md](training-path-skills.md).
- **Insights tab** (`Native/iOS/InsightsView.swift`):
  - **Calendar**: training days from the history on the phone (video replays never count), camera-tracked and logged days marked, today ringed. A day shows total reps, active time, average Watch heart rate when recorded, every set, and a link to each session report. Below: current and longest streak, days trained this month, and a five-week heatmap.
    For presentations the calendar also shows about five sample days a week over the last six weeks (never today, never on a day with real training). They are drawn faded with a dashed ring, the day detail says "Sample", and a "Hide samples" button under the grid turns them off (`insights.sampleCalendar`). Reports and Weekly read real history only.
  - **Reports**: every recorded or logged session, newest first, opening Omar's existing `SessionReportView`.
  - **Weekly**: this week against last for training days (against the weekly target), sessions, sets and reps, with "New this week" instead of a percentage from zero; the average rep time; Omar's `CoachSummaryCard` for the Gemini weekly review; and quests built from the training path and the weekly target.
  - **Research**: the reviewed guidance library bundled with the app (`coach-guidance.json`), each source with its audience and a link.
- **Calendar logic** in Core (`Shared/Core/TrainingCalendar.swift`, tested): training days, the month grid on the calendar's first weekday, streaks, and the week-on-week comparison.

Preview mode keeps its own path data in the same `Preview` folder as Omar's preview workspace, so synthetic preview
sessions never mix with real ones.

## Running it

The project file is committed on this branch, so it builds as checked out:

```bash
open Spottr.xcodeproj
```

On a device, pick a signing team for the Spottr and SpottrWatch targets. A personal team needs its own bundle
identifiers.
