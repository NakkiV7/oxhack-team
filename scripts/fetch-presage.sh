#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${SPOTTR_EXPERIMENTAL_PRESAGE:-0}" in
  0) printf 'Presage SDK skipped: experimental integration is disabled.\n'; exit 0 ;;
  1) ;;
  *) printf 'SPOTTR_EXPERIMENTAL_PRESAGE must be 0 or 1.\n' >&2; exit 2 ;;
esac
hash=eb99a609fc8069de020e0cf4328fb4a81a48b0aff7499348c6aa23e6fcb09947
destination=Native/Vendor/SmartSpectra.xcframework
marker=Native/Vendor/.spottr-presage-3.4.0
if [[ -d "$destination" ]]; then
  [[ -f "$marker" && "$(cat "$marker")" == "$hash" ]] || { echo 'Existing Presage framework has no matching version receipt; preserved.' >&2; exit 1; }
  codesign --verify --strict "$destination"
  exit 0
fi
mkdir -p Native/Vendor
temporary=$(mktemp -d Native/Vendor/.presage.XXXXXX)
trap 'rm -rf "$temporary"' EXIT
archive="${1:-$temporary/SmartSpectra.zip}"
if [[ $# == 0 ]]; then
  curl --fail --location --max-time 180 https://github.com/Presage-Security/SmartSpectra-Swift/releases/download/v3.4.0/SmartSpectra.xcframework.zip -o "$archive"
fi
echo "$hash  $archive" | shasum -a 256 -c -
unzip -q "$archive" -d "$temporary/unpacked"
codesign --verify --strict "$temporary/unpacked/SmartSpectra.xcframework"
mv "$temporary/unpacked/SmartSpectra.xcframework" "$destination"
echo "$hash" > "$marker"
