# Coordinated native report checks after #130

PR #130 merged at `39e112223da77a96de97701bf8ad2eea4f3f18d2` on 25 October 2026.
Its original core/SDK-double checks did not establish native app or rendered UI
acceptance. The coordinated follow-up below now supplies that scoped native
evidence. The primary chat retains combined-app integration and release checks. Physical Watch acceptance remains Omar's separate
checklist in [watch-sensor-report-acceptance.md](watch-sensor-report-acceptance.md).

## Synthetic populated reports

`Tests/UI/Fixtures/watch-populated.json` contains one explicitly synthetic session:
HR/motion readings, a corrected HR sample, cached duplicates, a real timeline gap,
foreign/pre-session samples that must be excluded, and two separate recording totals
(2.5 and 0.4 kcal). `watch-partial.json` contains one acceleration reading plus stale
HR/rotation: both stale signals stay unavailable, and energy is absent.

A new Core behavior test loads these exact files through the real SessionRecord
decoder and report projection. The UI selectors use the normal Progress/report
flow, no provider calls or live sensor injection. Fixtures are never bundled into
production, and there are no TrainingStore/App/project changes or runtime fixture
switches. Their dates use the existing Foundation reference epoch.

After primary builds and installs its app on an already-owned simulator, obtain
that app's **data container** (not bundle) using its chosen simulator UUID. Pass the
container and fixture directory to this one-time seed command. It writes exclusively
to two reserved test namespaces and refuses to replace different existing history.
Do not point it at real phone data. Repeated runs with identical fixture bytes are safe.

```bash
python3 - "$SPOTTR_TEST_DATA_CONTAINER" "$SPOTTR_REPORT_FIXTURE_DIRECTORY" <<'PY'
import pathlib, sys
container, fixtures = map(pathlib.Path, sys.argv[1:])
if not container.is_dir():
    raise SystemExit('Expected an existing simulator app data container')
for namespace, name in [
    ('E2733504-C099-43BC-BF15-A59F7FB6EE62', 'watch-populated'),
    ('0FE03F3B-0411-4F0B-AEE9-E066958ABF4F', 'watch-partial'),
]:
    target = container / 'Library/Application Support/Spottr' / namespace / 'history.json'
    data = (fixtures / (name + '.json')).read_bytes()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if target.read_bytes() != data:
            raise SystemExit('Refusing to overwrite different namespace history: ' + namespace)
        continue
    with target.open('xb') as output:
        output.write(data)
PY
```

Run these selectors serially in the primary's existing native queue:

- `SpottrUITests/ReportFlowTests/testSavedSessionOpensReportWithActualExerciseAndSignalAbsence`
- `SpottrUITests/ReportFlowTests/testPopulatedWatchReportKeepsSourcesAndRecordingTotalsReadable`
- `SpottrUITests/ReportFlowTests/testPopulatedWatchReportAtAccessibilityTextSize`
- `SpottrUITests/ReportFlowTests/testPartialWatchReportLeavesStaleHeartAndRotationUnavailable`

The populated/partial selectors require seeding; they fail explicitly if history is
absent. The original missing-sensor selector uses its own random empty namespace.
The large-text selector requests UIKit's largest accessibility category through the
per-launch override, leaving global simulator settings untouched. Verify the text
size in its screenshots rather than treating the launch request as proof.

Keep xcresult, build logs and screenshot attachments with the tested commit and
configuration. Inspect source/unit labels, separate energy totals and sparse points,
HR/motion gap segments, missing-state text, readable means/maxima and scroll access
at default and largest text. Tests attach screenshots named **Synthetic** for those
sections; fixtures do not constitute real Watch readings. A passing UI assertion is
separate from visual inspection and physical-device acceptance.

## Coordinated execution: passed, with a visual defect fixed

The primary explicitly released a serialized queue slot after the crash probe and
retained-delegate checks finished. Only the existing Musalli-Test iOS 26.5 simulator
and existing Watch watchOS 26.5 destination were used. No device reset/erase, new
simulators, global text-size changes, signing changes or release/upload occurred.
Native dependencies were linked from existing ignored vendor files; no download.

The source for the final app/test run is committed as
`780cef0eea3af23c41c26a8d6b2bc1e5dcd5e4f9`. It builds on the #130 baseline plus the
acceptance fixtures. It does **not** include primary's evolving voice/Presage/camera
integration; primary must install its own build for combined acceptance.

| Check | Actual result |
| --- | --- |
| iPhone Debug build-for-testing | Passed, 62.9 sec, on fixture commit `7ec68ae`; final UI run rebuilt the changed iPhone source successfully |
| Watch Debug scheme build | Passed, 4.7 sec, on `7ec68ae`; no Watch source changed in the subsequent chart fix |
| Initial four report UI selectors | 4 passed / 0 failed / 0 skipped, 109.7 sec; screenshot inspection still found the chart defect below |
| Failing regression before the chart fix | Default populated selector failed because the explicit elapsed-time axis context was absent; original screenshots separately demonstrate collisions/truncation |
| Final four report UI selectors | 4 passed / 0 failed / 0 skipped, 122.3 sec |
| Largest accessibility detail capture | 1 passed / 0 failed / 0 skipped, 63.8 sec; extra energy-axis and rotation-endpoint screenshots |
| Core fixture/report checks | `swift test`: 126 passed; fixture test first failed for missing inputs, then passed against the exact JSON files; Core source unchanged by the chart fix |
| Fixture seeding safety | Temporary-directory check verified scoped writes, identical retry and refusal to overwrite different history |
| Patch whitespace | `git diff --check`: clean |

Visual inspection of the initial passing run found overlapping y-axis labels at
largest accessibility type: the axis fonts grew while plot heights stayed fixed.
Long absolute-time x labels also truncated at default size. The fix scales plot
height with caption text size, limits y-axis density and anchors compact elapsed
time labels at the first/last observations. A single observation has one zero-time
label. Each chart explicitly states its time origin; it does not imply a session
boundary. Underlying measurement/as-of dates and gap segments are unchanged.

Reviewed default, partial and largest-text screenshots show readable axes and
endpoints, correct units/source labels, distinct 2.5/0.4 kcal recording totals,
blank gaps, observed mean/max, and unavailable stale/missing signals. Largest-type
charts require scrolling; supplemental captures inspect their lower axes rather
than treating a partially visible chart as complete visual evidence.

All raw logs, xcresults and screenshots remain local under this worktree's ignored
`.local/watch-native-acceptance/`:

- `logs/iphone-build.log`, `logs/watch-build.log`, `logs/core-126.log`
- `logs/report-ui-axis-red.log`, `results/report-ui-axis-red.xcresult`
- `logs/report-ui-axis-final.log`, `results/report-ui-axis-final.xcresult`
- `logs/report-ui-large-detail.log`, `results/report-ui-large-detail.xcresult`
- `screenshots/manifest.json` (before), `screenshots-final/manifest.json` (after),
  `screenshots-large-detail/manifest.json` (additional full-axis captures)

The queue was released back to primary and the `spottr-phone` XcodeBuildMCP profile
restored. Only synthetic namespace history was added. The simulator's installed
app is this isolated acceptance build; primary was told to reinstall its own
integration build. Physical Watch acceptance remains pending Omar.
