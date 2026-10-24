#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-all}"
[[ $# -le 1 && ( "$mode" == all || "$mode" == --static ) ]] || { printf 'Usage: %s [--static]\n' "$0" >&2; exit 2; }

for script in scripts/*.sh; do bash -n "$script"; done
ruby -c scripts/generate-project.rb
ruby -rjson -e 'files = Dir.glob(["Native/**/*.json", "Tests/**/*.json", "integrations/**/*.json", "server/*.json"]); files.reject! { |path| path.start_with?("Native/Vendor/") }; files.each { |path| JSON.parse(File.read(path)) }; puts "JSON syntax: #{files.length} files passed"'
if [[ -f server/package.json ]]; then
  command -v node >/dev/null 2>&1 || { printf 'Node 22.9+ is needed for gateway syntax checks.\n' >&2; exit 1; }
  node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 9)) { console.error("Node 22.9+ required"); process.exit(1); }'
  for source in server/src/*.mjs server/test/*.mjs; do
    [[ ! -f "$source" ]] || node --check "$source"
  done
fi
if [[ -d hardware/pi ]]; then
  command -v python3 >/dev/null 2>&1 || { printf 'Python 3.10+ is needed for Pi companion checks.\n' >&2; exit 1; }
  python3 -c 'import ast, pathlib, sys; assert sys.version_info >= (3, 10), "Python 3.10+ required"; [ast.parse(p.read_text()) for p in pathlib.Path("hardware/pi").glob("*.py")]'
fi
[[ "$mode" != --static ]] || { printf 'Static checks passed. No builds, tests or network requests run.\n'; exit 0; }

command -v swift >/dev/null 2>&1 || { printf 'Swift 6 is required for the shared behavior tests.\n' >&2; exit 1; }
if [[ -f server/package.json && ! -d server/node_modules/zod ]]; then
  printf 'Gateway dependencies missing. Run (cd server && npm ci), then rerun checks.\n' >&2
  exit 1
fi
swift test
if [[ -f server/package.json ]]; then (cd server && npm test); fi
if [[ -d hardware/pi ]]; then python3 -m unittest discover -s hardware/pi -v; fi
printf 'Offline checks passed. Run relevant native/device smoke tests in Xcode; no native build or live provider call was run here.\n'
