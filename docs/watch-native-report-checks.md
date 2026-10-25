# Coordinated native report checks after #130

PR #130 merged at `39e112223da77a96de97701bf8ad2eea4f3f18d2` on 25 October 2026.
Its original core/SDK-double checks do not establish native app or rendered UI
acceptance. The primary chat owns native builds and simulator operations; leave
release gated on its results. Physical Watch acceptance remains Omar's separate
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

## Evidence to fill after execution

- iPhone/Watch build commit/configuration and result: pending primary queue.
- Four report selector results and xcresult: pending primary queue.
- Default/accessibility screenshot inspection: pending primary queue.
- Follow-up defects and fixes, if any: record actual failures here.
- Physical Watch checks: pending Omar, not performed by these tests.
