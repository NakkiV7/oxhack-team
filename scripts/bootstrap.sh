#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${SPOTTR_EXPERIMENTAL_PRESAGE:-0}" in
  0|1) ;;
  *) printf 'SPOTTR_EXPERIMENTAL_PRESAGE must be 0 or 1.\n' >&2; exit 2 ;;
esac

fail() { printf 'Setup: %s\n' "$1" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Missing $1. $2"; }

[[ "$(uname -s)" == Darwin ]] || fail 'The native app needs macOS and Xcode. See README.md for the optional Node gateway.'
require_command xcodebuild 'Install/select Xcode yourself, then rerun bootstrap.'
require_command xcrun 'Select Xcode command-line tools, then rerun bootstrap.'
require_command swift 'Select a Swift 6 Xcode toolchain, then rerun bootstrap.'
require_command ruby 'Install Ruby and the xcodeproj gem in your preferred environment.'
require_command curl 'Install curl before fetching the pinned SDK.'
require_command unzip 'Install unzip before fetching the pinned SDK.'
require_command shasum 'Install shasum before verifying the pinned SDK.'
if [[ "${SPOTTR_EXPERIMENTAL_PRESAGE:-0}" == 1 ]]; then
  require_command codesign 'Select Xcode command-line tools before verifying the experimental Presage SDK.'
fi

xcodebuild -version || fail 'Xcode is not ready. Open Xcode to finish its setup and select its developer directory.'
for sdk in iphoneos watchos; do
  sdk_version="$(xcrun --sdk "$sdk" --show-sdk-version)" || fail "The $sdk SDK is unavailable. Install its Xcode platform support."
  [[ "${sdk_version%%.*}" -ge 26 ]] || fail "The generated app needs $sdk SDK 26 or later; found $sdk_version."
done
ruby -e 'require "xcodeproj"' 2>/dev/null || fail 'Ruby cannot load xcodeproj. Install the xcodeproj gem yourself, then rerun bootstrap.'

bash scripts/fetch-mediapipe.sh
bash scripts/fetch-presage.sh
ruby scripts/generate-project.rb
if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  printf 'Created ignored .env from placeholders; edit it privately only if using the gateway.\n'
fi

printf 'Native setup ready. Open Spottr.xcodeproj and choose an existing simulator.\n'
printf 'Optional gateway: install Node 22.9+, then run (cd server && npm ci). No provider keys are needed for local training.\n'
printf 'Run ./scripts/check.sh after gateway dependency setup, or ./scripts/check.sh --static for syntax checks.\n'
