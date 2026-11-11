#!/usr/bin/env bash
# Local functional suite. Each case gets a fresh Factorio process and a retained log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p tmp/test-logs
failed=0

run() {
  local name=$1
  shift
  echo "test: $name"
  if "$ROOT/tools/factorio-test.sh" "$@"; then
    echo "test: $name passed"
  else
    echo "test: $name FAILED" >&2
    failed=1
  fi
  cp .factorio-test/last-write.log "tmp/test-logs/$name.log"
}

for name in tech tc-none tc-unpowered tc-zone tc-signals tc-pick tc-ignore tc-chunk tc-wires tc-blueprint tc-gui tc-fast steel-shell; do
  run "$name" mods space-artillery/playtest "$name 3600" 4000
done
for name in math hull damage combat tracking lifecycle; do
  run "core-$name" mods space-artillery/core "$name" 2100
done
# Remove the old save so a failed save test cannot be masked by a prior run's file.
rm -f .factorio-test/write/saves/_autosave-core-reload.zip
run core-save --save-scenario mods space-artillery/core core-reload
run core-reload --test-save mods core-reload reload 2100

if (( failed )); then echo "test: suite FAILED; logs in tmp/test-logs" >&2; exit 1; fi
echo "test: all 21 cases passed; logs in tmp/test-logs"
