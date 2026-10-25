# Watch sensor reports: software evidence and physical acceptance

25 October 2026. All fixture values are synthetic. No real physiology, paired-device
measurements or physical acceptance are claimed. No acquisition scope, account,
project/signing settings, TrainingStore or SessionRecord schema changes are needed.

## Contract

| Signal | Apple boundary | Transport/report meaning |
| --- | --- | --- |
| Heart rate | `HKStatistics.mostRecentQuantity()` in `count/min`, date from `mostRecentQuantityDateInterval().end` | bpm, HealthKit source label; latest accepted callback cannot regress to an older sample; equal-date corrections allowed |
| Active energy | `HKStatistics.sumQuantity()` in `.kilocalorie()`, statistics `endDate` | Cumulative kcal estimate for one recording UUID; keep original as-of time, deduplicate repeated observations, retain latest correction even if lower; do not add tick totals |
| Wrist acceleration | `CMDeviceMotion.userAcceleration`, magnitude of x/y/z | Gravity removed, g; Core Motion source label; sampled magnitude, no form or rep inference |
| Wrist rotation | `CMDeviceMotion.rotationRate`, magnitude of x/y/z | rad/s, Core Motion source label; unsigned magnitude, no anatomical range-of-motion inference |

Core Motion timestamps are seconds since boot. The recorder maps them using the
contemporaneous wall clock and `ProcessInfo.systemUptime`; it does not treat uptime
as Unix time. JSON inside WCSession's `Data` payload retains the existing Foundation
`JSONEncoder`/`JSONDecoder` date contract (seconds since 1 January 2001), distinct
from Unix seconds. Source labels describe the app's recorder path, not signed
provenance of arbitrarily edited/imported JSON.

Authoritative Apple references: [HR sample interval](https://developer.apple.com/documentation/healthkit/hkstatistics/mostrecentquantitydateinterval()),
[active energy](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned),
[motion timestamp](https://developer.apple.com/documentation/coremotion/cmlogitem/timestamp),
[acceleration](https://developer.apple.com/documentation/coremotion/cmacceleration),
[processed device motion](https://developer.apple.com/documentation/coremotion/cmdevicemotion).

Both phone session types reject wrong-session, non-increasing send timestamps,
finished-session and expired envelopes (12 seconds old, 2 seconds future tolerance).
The replay verifies existing behavior; it does not add disconnected backfill.
The Watch pauses when its retained phone snapshot expires (10 seconds). Reconnection
needs a newly accepted fresh snapshot. Same-session pause/resume retains the recording
identity; ending/changing sessions clears cached sensor state. Permission absence
cannot establish denial, zero readings or zero physical activity.

Reports additionally exclude sample dates before session start (2 seconds clock
skew tolerance), invalid HR/magnitudes, stale measurements relative to their send
time, and foreign-session samples. Distinct sample timestamps count once; the newest
send timestamp resolves a correction. HR and motion timeline gaps over 12 seconds
remain separate segments. Sample-weighted means and maxima are descriptive observed
values, not time-weighted coverage, readiness, zones or fitness changes.

Energy is shown as sparse points separately for each recording. The latest estimate
always keeps its as-of time; an old cumulative estimate is historical, not live or
silently converted to zero. Repeated cached cumulative values create no extra points.
Acceleration and rotation each have their own unavailable state. Existing local
history and export retain observations; energy remains excluded from Coach/cloud
requests by the existing contract checks.

## Software verification

- `swift test`: 125 tests passed, including two new report regressions: pre-session
  filtering/latest correction/source labels; cumulative timeline deduplication and
  separate runs. The new report API tests initially failed to compile because the
  timeline/provenance fields did not exist.
- `bash Tests/WatchRecorder/run.sh`: 11 recorder cases and 6 store cases passed against
  test-only SDK boundaries. The new HR case first failed on older/invalid callbacks
  replacing valid current readings, then passed after the guard. Added motion case
  verifies known signed axes become magnitudes in g and rad/s, and preserves the
  boot-relative sample date. These are not Apple's SDK implementations.
- `bash Tests/WatchRecorder/replay.sh`: real `CompanionLink` encoder/decoder → real
  tracking/configured session → real `HistoryStore` save/load/export → `WorkoutReport`.
  WCSession delivery alone is doubled. Verifies Foundation reference epoch, retained
  measurement dates/units, live/context duplicates, repeated cached values,
  out-of-order send times, wrong ownership, malformed JSON, expired transport,
  disconnected live-send suppression, stale retained context, missing HR,
  stale measurement in a fresh envelope, report gaps and cumulative energy.

No iPhone/Watch app builds, simulators or physical devices used in this lane. The report UI
changes have **not** yet had native compilation or rendered inspection. Primary owns
that queue. No changes to project membership are needed because existing source
files contain the components. Prepared selector:

`SpottrUITests/ReportFlowTests/testSavedSessionOpensReportWithActualExerciseAndSignalAbsence`

Primary should compile iPhone + Watch targets, execute that selector, and inspect a
populated report with one/multiple recordings at large Dynamic Type. Stable report
identifiers: `watch-energy-timeline`, `watch-active-energy-reading`,
`watch-acceleration-report`, `watch-rotation-report`. Populated source charts still
need coordinated native/human acceptance; core/SDK doubles cannot establish it.

## Omar's physical Watch checklist (all pending)

1. Record iPhone model/iOS, Watch model/watchOS, app build/commit and pairing state.
   Install matching phone/Watch build, open both apps, start a real strength session
   on phone, and explicitly choose Watch recording. Confirm authorization/startup
   does not claim successful recording before collection starts.
2. Exercise the OS permission choices, including missing HR/energy. Record only the
   choice actually made. If readings are absent, confirm unavailable text remains;
   do not infer denial from missing samples. Verify no synthetic/default physiology.
3. When real samples arrive, compare the displayed HR, cumulative active kcal and
   sample/as-of times with the actual recorder observations/Health workout within
   their update timing. Capture private evidence locally. Verify bpm/kcal labels,
   acceleration g and rotation rad/s; do not expect identical update frequencies.
4. Move the wrist gently, then keep still. Check actual motion availability and
   readable source-labelled charts/observed means/maxima. Small nonzero resting
   values are possible; no form-quality, zones or medical interpretation should appear.
5. Pause/resume on phone and Watch. Confirm no new paused telemetry, resumed samples
   retain their recording identity, and pre-resume cached samples are not freshened
   by new send times. Test delayed updates; unavailable/old HR must not look current.
6. Disconnect phone/Watch long enough for snapshot expiry; confirm controls disable
   and capture pauses. Reconnect, check a genuinely fresh snapshot resumes the
   appropriate state, and report gaps stay blank. A retained old context must not
   create a current reading or reconnect a finished session.
7. Finish explicitly, save, reopen report/history, relaunch phone and export locally.
   Match values, units and measurement/as-of timestamps. Confirm HR deduplication,
   motion gaps and kcal total equal latest estimate per recording, not tick sums.
8. Start a second recording and then a second phone session. Verify new recording
   totals remain separate, the phone session owns only its samples, old/late callbacks
   do not contaminate it, and no old readings appear before new callbacks.
9. Inspect smallest supported Watch/iPhone and large Dynamic Type, VoiceOver reading
   order, scrolling, and independent absent-signal states. Retain observed failures
   without claiming device acceptance from the automated checks.
