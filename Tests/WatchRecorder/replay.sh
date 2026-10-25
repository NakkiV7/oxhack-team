#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
replay_dir="$(mktemp -d "${TMPDIR:-/tmp}/spottr-watch-replay.XXXXXX")"
trap 'rm -rf "$replay_dir"' EXIT
swiftc -swift-version 5 -emit-module -emit-library -module-name WatchConnectivity \
  Tests/WatchRecorder/WatchConnectivity.swift -emit-module-path "$replay_dir/WatchConnectivity.swiftmodule" \
  -o "$replay_dir/libWatchConnectivity.dylib"
swiftc -swift-version 5 -parse-as-library -I "$replay_dir" -L "$replay_dir" \
  -lWatchConnectivity -Xlinker -rpath -Xlinker "$replay_dir" \
  Shared/Core/*.swift Shared/Apple/CompanionLink.swift Tests/WatchRecorder/TelemetryReplayTests.swift \
  -o "$replay_dir/replay-tests"
"$replay_dir/replay-tests"
