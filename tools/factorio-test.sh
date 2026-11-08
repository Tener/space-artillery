#!/usr/bin/env bash
# Run one Factorio headless test scenario (2.1.24+ --test-scenario) in an isolated
# config, so the user's saves, mods and settings are never touched.
#
# Usage: tools/factorio-test.sh MODS_DIR MOD/SCENARIO [TEST_ARG] [TICKS]
#        tools/factorio-test.sh --graphics MODS_DIR SAVE_NAME TICKS
#        tools/factorio-test.sh --client MODS_DIR MOD/SCENARIO SECONDS
#        tools/factorio-test.sh --play MODS_DIR MOD/SCENARIO
#   --play        start the game client in MOD/SCENARIO for a human to play, and return
#                 immediately (the game keeps running until you quit it)
#   --client      start the normal game client in MOD/SCENARIO (--load-scenario, rendering
#                 on, script.test_arg is nil) and close it after SECONDS (max 120).
#                 Opens a game window; screenshots land in .factorio-test/write/script-output
#   MODS_DIR      directory with mod-list.json and the mods to load
#   MOD/SCENARIO  scenario shipped inside a mod, e.g. aa-spike/spike
#   TEST_ARG      string passed to script.test_arg (letters, digits, space . _ -)
#   TICKS         --test-ticks timeout (default 6000), or benchmark ticks for --graphics
#   --graphics    replay a save written by a test via game.auto_save(SAVE_NAME) with
#                 rendering on (--benchmark-graphics), so game.take_screenshot works.
#                 Opens a game window; screenshots land in .factorio-test/write/script-output
#
# Prints script output lines starting with "[" plus errors; the full log is kept in
# .factorio-test/last-write.log (tests) or last-play.log (--play/--client, which also use
# their own write dir .factorio-test/play). Exit code is Factorio's: 0 pass, 1 fail/error.
set -euo pipefail

FACTORIO="$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio"

die() { echo "factorio-test: $*" >&2; exit 2; }

graphics=0 client=0 play=0
if [[ ${1:-} == --play ]]; then
  play=1
  shift
  [[ $# -eq 2 ]] || die "usage: $0 --play MODS_DIR MOD/SCENARIO"
  mods=$1 scenario=$2 ticks=0
  [[ $scenario =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]] || die "bad scenario: $scenario"
elif [[ ${1:-} == --client ]]; then
  client=1
  shift
  [[ $# -eq 3 ]] || die "usage: $0 --client MODS_DIR MOD/SCENARIO SECONDS"
  mods=$1 scenario=$2 secs=$3 ticks=0
  [[ $scenario =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]] || die "bad scenario: $scenario"
  [[ $secs =~ ^[0-9]+$ ]] && (( secs > 0 && secs <= 120 )) || die "bad seconds: $secs"
elif [[ ${1:-} == --graphics ]]; then
  graphics=1
  shift
  [[ $# -eq 3 ]] || die "usage: $0 --graphics MODS_DIR SAVE_NAME TICKS"
  mods=$1 save=$2 ticks=$3
  [[ $save =~ ^[A-Za-z0-9_-]+$ ]] || die "bad save name: $save"
else
  [[ $# -ge 2 && $# -le 4 ]] || die "usage: $0 MODS_DIR MOD/SCENARIO [TEST_ARG] [TICKS]"
  mods=$1 scenario=$2 arg=${3:-} ticks=${4:-6000}
  [[ $scenario =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]] || die "bad scenario: $scenario"
  [[ $arg =~ ^[A-Za-z0-9_.\ -]*$ ]] || die "bad test arg: $arg"
fi

[[ -f $mods/mod-list.json ]] || die "no mod-list.json in $mods"
[[ $ticks =~ ^[0-9]+$ ]] || die "bad ticks: $ticks"
[[ -x $FACTORIO ]] || die "factorio not found at $FACTORIO"

# Without this, a Steam copy launched directly restarts itself through Steam as a new
# process, so --client could not close the game it started.
export SteamAppId=427520

root=$(cd "$(dirname "$0")/.." && pwd)
work=$root/.factorio-test
# Interactive sessions get their own write dir (and lock), so headless tests can run
# while a playtest is open.
if (( play || client )); then mode=play; else mode=write; fi
mkdir -p "$work/$mode"
cat > "$work/config-$mode.ini" <<EOF
[path]
read-data=__PATH__executable__/../data
write-data=$work/$mode
EOF

log=$work/last-$mode.log
cmd=("$FACTORIO" --config "$work/config-$mode.ini" --mod-directory "$(cd "$mods" && pwd)")
if (( play )); then
  cmd+=(--load-scenario "$scenario")
  nohup "${cmd[@]}" > "$log" 2>&1 &
  echo "factorio-test: game started (pid $!), log=$log"
  echo "factorio-test: screenshots land in $work/$mode/script-output"
  exit 0
elif (( client )); then
  cmd+=(--load-scenario "$scenario")
  "${cmd[@]}" > "$log" 2>&1 &
  pid=$!
  for (( i = 0; i < secs; i++ )); do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    if grep -q "CAPTURE_COMPLETE" "$log" 2>/dev/null; then
      echo "factorio-test: CAPTURE_COMPLETE received"
      sleep 1
      break
    fi
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  awk '/^\[/ || /Error/ { print }' "$log"
  echo "factorio-test: client closed; screenshots:"
  ls "$work/$mode/script-output"
  exit 0
elif (( graphics )); then
  savefile=$work/write/saves/_autosave-$save.zip
  [[ -f $savefile ]] || die "no save at $savefile (call game.auto_save(\"$save\") in a test first)"
  cmd+=(--benchmark-graphics "$savefile" --benchmark-ticks "$ticks")
else
  cmd+=(--test-scenario "$scenario" --test-ticks "$ticks")
  [[ -n $arg ]] && cmd+=(--test-arg "$arg")
fi

status=0
"${cmd[@]}" > "$log" 2>&1 || status=$?

awk '/^\[/ || /RunTest/ { print } /Error while|non-recoverable/ { n = 8 } n-- > 0 { print }' "$log"
echo "factorio-test: exit=$status log=$log"
exit $status
