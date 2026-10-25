# History persistence audit — 25 October 2026

`TrainingStore.persist` previously saved the complete history and immediately loaded/decoded it again on the main actor. It now uses the records returned by `HistoryStore.save` after its atomic write succeeds, in the same reverse order used by the UI. Existing callers can ignore the result. This removes one whole-file read/decode per save without changing operation scheduling or the JSON format.

## Synthetic baseline

Measured before the change at source HEAD `325e42952a36b4b2d3d41ec21aa02194dc734de4`; original `HistoryStore.swift` SHA-256 `a7c089972585aed3ad08f567f4038ca6239eeb3b218cff8abf19bc990ca3bb0a`. The executable compiled the actual `Shared/Core` sources with Swift 6.4, optimized for arm64 macOS, with one compiler thread. No real history, native app build, device, sensor or provider was used.

Each session contained one 12-rep set and 600 synthetic one-second telemetry envelopes, each with three scalar readings. Three repetitions per history size used a warm filesystem cache. Values are medians in milliseconds; paired persist is the median of each save plus its immediately following reload, rather than the sum of separate medians.

| Sessions | JSON bytes | Load | Save | Extra reload | Previous paired persist | Pretty export |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 1,299,241 | 33.06 | 65.47 | 34.27 | 99.74 | 73.12 |
| 50 | 6,496,201 | 221.43 | 465.26 | 159.99 | 616.38 | 387.41 |
| 100 | 12,992,401 | 309.41 | 684.51 | 331.24 | 1,049.14 | 752.93 |

The removed phase is visible in these measurements; these are **not** measured before/after app timings. Small samples and shared-host scheduling caused variation. Runtime was 13.67 seconds; peak process RSS was 256,409,600 bytes, with zero reported swaps. Generated JSON, executable and module cache were removed after inspection. No physical-device hitch or frame-rate improvement is claimed.

## Contract and remaining limits

The direct public-API test first failed to compile because `save` returned `Void` instead of `[SessionRecord]`. After the minimal implementation, nine focused SwiftPM checks passed, including returned records matching reopened storage, replacement moving to the end without duplicates, unchanged durable bytes after an encoding failure, filesystem failure returning no success value, export/clear/corruption, retention beyond 100 sessions and companion isolation. The filesystem case uses a regular file blocking the parent directory; it does not simulate power loss or storage exhaustion.

All production history operations still execute synchronously through `TrainingStore` on the main actor. There is no new task, suspension, queue or stale completion; the existing save/clear/export invocation order is preserved. A failed save keeps the UI's prior history and reports its existing error. Manual logging can still inspect the committed history immediately. Startup decoding, the save's initial load/encode/write, and export remain proportional to history size. `HistoryStore` itself does not provide cross-instance/process locking or additional durability guarantees beyond Foundation's atomic replacement.

A later background repository would need one owner for load/save/clear/export, an ordered clear barrier, stale-result protection and explicit completion/error handling before changing the current immediate-save UI. Detached writes alone could restore deleted history or reorder snapshots. That broader change and physical-device profiling remain pending. Native app compilation/data-control tests were not run in this lane while another agent used the native test lane.

Focused command:

```sh
swift test --filter 'historySave|failedHistorySave|historyFilesystemFailure|historyExport|historyClear|unreadableHistory|historyRetainsEarnedProgress|companion'
```

## Native rendering and verification

Skills now evaluates its complete progress once per body evaluation and shares that value with the header, attributes and selected layout. Progress uses a `LazyVStack` so offscreen session cards can defer constructing their detailed reports. Neither change alters progress rules, source labels, report calculations or navigation order; no measured rendering latency improvement is claimed.

On the existing Musalli-Test iOS 26.5 simulator, the baseline grid/linear navigation check passed. After the view refactor, all four `SkillsFlowTests` and both `ReportFlowTests` passed. The Skills build log contains two App Intents metadata-extraction warnings because those targets do not depend on AppIntents; the tests still passed. The test-written global Skills layout was returned to its default grid value; the initial sandbox value was not established reliably. Workouts used unique test namespaces.

After the persistence API change, an ad-hoc-signed simulator build/run succeeded, and the native `ProfileDataControlsTests` check passed, including immediate save/readback, export, active-workout deletion refusal and isolated clear behavior. An initial command named the nonexistent `SpottrNativeTests` test target and ran no tests; the corrected `SpottrTests` command passed. A combined core run then passed one XCTest and 31 Swift Testing functions covering history, skill progression and reports. No physical device, provider, voice or sensor was used for these checks.

Local receipts: `test_sim_2026-10-24T23-47-04-884Z_pid81613_e94a5b04.log` (Skills), `test_sim_2026-10-24T23-48-41-195Z_pid81613_23dec276.log` (reports), `build_run_sim_2026-10-24T23-51-18-703Z_pid4129_072ffbea.log`, and `test_sim_2026-10-24T23-53-51-869Z_pid4129_16dbd810.log` (native data controls).

## Bounded reproduction

Save the following as `main.swift` in a newly created temporary directory. From the repository root, compile with the command below and run against that same temporary directory. The probe uses synthetic data, generates approximately 87 MiB including pretty exports, and uses no network. Run once, then remove only the temporary directory you created. With the new API this still measures the former extra reload explicitly for comparison; no extra reload is performed by the new native persistence call.

```sh
# Set probe_dir to your newly created temporary directory containing main.swift.
swiftc -swift-version 5 -O -whole-module-optimization -num-threads 1 \
  -parse-as-library -module-cache-path "$probe_dir/module-cache" \
  Shared/Core/*.swift "$probe_dir/main.swift" -o "$probe_dir/probe"
/usr/bin/time -l "$probe_dir/probe" "$probe_dir"
```

```swift
import Foundation

@main struct HistoryCostProbe {
    static func measured<T>(_ action: () throws -> T) rethrows -> (T, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try action()
        return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    static func fixture(_ index: Int, samples: Int) -> SessionRecord {
        let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
        let start = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 86400))
        let telemetry = (0..<samples).map { offset -> WatchTelemetry in
            let date = start.addingTimeInterval(Double(offset))
            return WatchTelemetry(sessionID: id, sentAt: date,
                heartRate: SensorReading(value: 100, date: date),
                accelerationG: SensorReading(value: 1, date: date),
                rotationRadiansPerSecond: SensorReading(value: 0, date: date))
        }
        let set = SetRecord(id: UUID(), exercise: .squat, number: 1, reps: 12, target: 12,
            activeSeconds: Double(samples), source: .camera, reason: .voluntary,
            repDurations: Array(repeating: 1.2, count: 12))
        return SessionRecord(id: id, date: start, sets: [set], telemetry: telemetry)
    }
    static func median(_ numbers: [Double]) -> Double { numbers.sorted()[numbers.count / 2] }
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var checksum = 0
        for count in [10, 50, 100] {
            try autoreleasepool {
                let records = (0..<count).map { fixture($0, samples: 600) }
                let seed = try JSONEncoder().encode(records)
                let store = HistoryStore(url: directory.appendingPathComponent("history-\(count).json"))
                let export = directory.appendingPathComponent("export-\(count).json")
                try seed.write(to: store.url, options: .atomic)
                checksum += try store.load().count
                var saves: [Double] = [], reloads: [Double] = [], exports: [Double] = [], initial: [Double] = []
                for _ in 0..<3 {
                    let (_, initialMS) = try measured { checksum += try store.load().count }
                    let (_, saveMS) = try measured { try store.save(records.last!) }
                    let (_, reloadMS) = try measured { checksum += Array(try store.load().reversed()).count }
                    let (_, exportMS) = try measured { try store.export(to: export) }
                    saves.append(saveMS); reloads.append(reloadMS); exports.append(exportMS); initial.append(initialMS)
                }
                let result: [String: Any] = ["sessions": count, "telemetryPerSession": 600, "historyBytes": seed.count,
                    "iterations": 3, "loadMedianMs": median(initial), "saveMedianMs": median(saves),
                    "extraReloadMedianMs": median(reloads), "currentPersistMedianMs": median(zip(saves, reloads).map(+)),
                    "exportMedianMs": median(exports), "allSaveMs": saves, "allReloadMs": reloads]
                let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: output, as: UTF8.self))
            }
        }
        print("syntheticChecksum=\(checksum)")
    }
}
```
