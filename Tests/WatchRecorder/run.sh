#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
watch_test_root="${SPOTTR_WATCH_TEST_ROOT:-/Volumes/Spottr Development/watch-telemetry-tests}"
mkdir -p "$watch_test_root"
watch_test_dir="$(mktemp -d "$watch_test_root/recorder.XXXXXX")"
mkdir -p "$watch_test_dir/tmp"
export TMPDIR="$watch_test_dir/tmp/"
cp -R Shared/Core "$watch_test_dir/Core"
trap 'rm -rf "$watch_test_dir"' EXIT
swiftc -module-cache-path "$watch_test_dir/module-cache" -swift-version 5 -parse-as-library \
  "$watch_test_dir/Core/Telemetry.swift" Tests/WatchRecorder/MotionContractTests.swift \
  -o "$watch_test_dir/motion-contract-tests"
"$watch_test_dir/motion-contract-tests"
for sdk in HealthKit CoreMotion WatchKit; do
  swiftc -module-cache-path "$watch_test_dir/module-cache" -swift-version 5 -emit-module -emit-library -module-name "$sdk" \
    "Tests/WatchRecorder/$sdk.swift" -emit-module-path "$watch_test_dir/$sdk.swiftmodule" \
    -o "$watch_test_dir/lib$sdk.dylib"
done
swiftc -module-cache-path "$watch_test_dir/module-cache" -swift-version 5 -parse-as-library -I "$watch_test_dir" -L "$watch_test_dir" \
  -lHealthKit -lCoreMotion -Xlinker -rpath -Xlinker "$watch_test_dir" \
  "$watch_test_dir/Core/WatchCaptureLifecycle.swift" "$watch_test_dir/Core/Telemetry.swift" "$watch_test_dir/Core/WatchMotionAccumulator.swift" \
  Native/Watch/WorkoutRecorder.swift Tests/WatchRecorder/CollectionFailureTests.swift \
  -o "$watch_test_dir/watch-recorder-tests"
"$watch_test_dir/watch-recorder-tests"
swiftc -module-cache-path "$watch_test_dir/module-cache" -swift-version 5 -parse-as-library -I "$watch_test_dir" -L "$watch_test_dir" \
  -lHealthKit -lCoreMotion -lWatchKit -Xlinker -rpath -Xlinker "$watch_test_dir" \
  "$watch_test_dir"/Core/*.swift Native/Watch/WorkoutRecorder.swift Native/Watch/WatchStore.swift \
  Tests/WatchRecorder/CompanionLink.swift Tests/WatchRecorder/WatchStoreTests.swift \
  -o "$watch_test_dir/watch-store-tests"
"$watch_test_dir/watch-store-tests"
