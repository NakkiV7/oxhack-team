#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
watch_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/spottr-watch-recorder.XXXXXX")"
trap 'rm -rf "$watch_test_dir"' EXIT
for sdk in HealthKit CoreMotion WatchKit; do
  swiftc -swift-version 5 -emit-module -emit-library -module-name "$sdk" \
    "Tests/WatchRecorder/$sdk.swift" -emit-module-path "$watch_test_dir/$sdk.swiftmodule" \
    -o "$watch_test_dir/lib$sdk.dylib"
done
swiftc -swift-version 5 -parse-as-library -I "$watch_test_dir" -L "$watch_test_dir" \
  -lHealthKit -lCoreMotion -Xlinker -rpath -Xlinker "$watch_test_dir" \
  Shared/Core/WatchCaptureLifecycle.swift Shared/Core/Telemetry.swift \
  Native/Watch/WorkoutRecorder.swift Tests/WatchRecorder/CollectionFailureTests.swift \
  -o "$watch_test_dir/watch-recorder-tests"
"$watch_test_dir/watch-recorder-tests"
swiftc -swift-version 5 -parse-as-library -I "$watch_test_dir" -L "$watch_test_dir" \
  -lHealthKit -lCoreMotion -lWatchKit -Xlinker -rpath -Xlinker "$watch_test_dir" \
  Shared/Core/*.swift Native/Watch/WorkoutRecorder.swift Native/Watch/WatchStore.swift \
  Tests/WatchRecorder/CompanionLink.swift Tests/WatchRecorder/WatchStoreTests.swift \
  -o "$watch_test_dir/watch-store-tests"
"$watch_test_dir/watch-store-tests"
