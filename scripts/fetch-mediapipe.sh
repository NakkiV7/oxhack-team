#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Native/Vendor
fetch() {
  local name="$1" hash="$2" archive="Native/Vendor/$1.zip"
  if [[ ! -d "Native/Vendor/$name.xcframework" ]]; then
    curl -fL --retry 2 "https://dl.google.com/cpdc/20261013-213039/$name-1.1.1.xcframework.zip" -o "$archive"
    echo "$hash  $archive" | shasum -a 256 -c -
    unzip -qo "$archive" -d Native/Vendor
    rm "$archive"
  fi
}
fetch MediaPipeTasksCommon 25690f3005c0405a7f27b6d273b4db241811d00fbb01c54004057ee1d0e983d8
fetch MediaPipeTaskGraphs e4d88ed65c101764ef90281a411b9942f369e48673d448eff1f934e1f68d9633
fetch MediaPipeTasksVision 755390ce853b062536899f0729321156d4cdceb263aa92c4bf3b2dd05fe640e0
