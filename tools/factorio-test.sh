#!/usr/bin/env bash
# Run one Factorio headless test scenario (2.1.24+ --test-scenario) in an isolated
# config, so the user's saves, mods and settings are never touched.
#
# Usage: tools/factorio-test.sh MODS_DIR MOD/SCENARIO [TEST_ARG] [TICKS]
#        tools/factorio-test.sh --graphics MODS_DIR SAVE_NAME TICKS
#        tools/factorio-test.sh --client MODS_DIR MOD/SCENARIO SECONDS
#        tools/factorio-test.sh --play MODS_DIR MOD/SCENARIO
#        tools/factorio-test.sh --test-save MODS_DIR SAVE_NAME TEST_ARG [TICKS]
#        tools/factorio-test.sh --save-scenario MODS_DIR MOD/SCENARIO SAVE_NAME
#   --play        start the game client in MOD/SCENARIO for a human to play, and return
#                 immediately (the game keeps running until you quit it)
#   --client      start the normal game client in MOD/SCENARIO (--load-scenario, rendering
#                 on, script.test_arg is nil) and close it after SECONDS (max 600).
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

FACTORIO="${FACTORIO:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"

die() { echo "factorio-test: $*" >&2; exit 2; }
check_scenario() { [[ $1 =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]] || die "bad scenario: $1"; }
# log lines that mean the client run failed
ERRORS="Error while|non-recoverable|Exception at tick"

graphics=0 client=0 play=0 test_save=0 save_scenario=0
if [[ ${1:-} == --play ]]; then
  play=1
  shift
  [[ $# -eq 2 ]] || die "usage: $0 --play MODS_DIR MOD/SCENARIO"
  mods=$1 scenario=$2 ticks=0
  check_scenario "$scenario"
elif [[ ${1:-} == --client ]]; then
  client=1
  shift
  [[ $# -eq 3 ]] || die "usage: $0 --client MODS_DIR MOD/SCENARIO SECONDS"
  mods=$1 scenario=$2 secs=$3 ticks=0
  check_scenario "$scenario"
  [[ $secs =~ ^[0-9]+$ ]] && (( secs > 0 && secs <= 600 )) || die "bad seconds: $secs"
elif [[ ${1:-} == --save-scenario ]]; then
  save_scenario=1
  shift
  [[ $# -eq 3 ]] || die "usage: $0 --save-scenario MODS_DIR MOD/SCENARIO SAVE_NAME"
  mods=$1 scenario=$2 save=$3 ticks=0
  check_scenario "$scenario"
  [[ $save =~ ^[A-Za-z0-9_-]+$ ]] || die "bad save name: $save"
elif [[ ${1:-} == --test-save ]]; then
  test_save=1
  shift
  [[ $# -ge 3 && $# -le 4 ]] || die "usage: $0 --test-save MODS_DIR SAVE_NAME TEST_ARG [TICKS]"
  mods=$1 save=$2 arg=$3 ticks=${4:-6000}
  [[ $save =~ ^[A-Za-z0-9_-]+$ ]] || die "bad save name: $save"
  [[ $arg =~ ^[A-Za-z0-9_.\ -]*$ ]] || die "bad test arg: $arg"
elif [[ ${1:-} == --graphics ]]; then
  graphics=1
  shift
  [[ $# -eq 3 ]] || die "usage: $0 --graphics MODS_DIR SAVE_NAME TICKS"
  mods=$1 save=$2 ticks=$3
  [[ $save =~ ^[A-Za-z0-9_-]+$ ]] || die "bad save name: $save"
else
  [[ $# -ge 2 && $# -le 4 ]] || die "usage: $0 MODS_DIR MOD/SCENARIO [TEST_ARG] [TICKS]"
  mods=$1 scenario=$2 arg=${3:-} ticks=${4:-6000}
  check_scenario "$scenario"
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
if (( save_scenario )); then
  # Test mode does not service autosave requests. Create the fixture in a local server.
  cat > "$work/server-settings.json" <<EOF
{"name":"Core test fixture","description":"Local save/load test","tags":[],"max_players":0,
"visibility":{"public":false,"lan":false},"username":"","password":"","token":"","game_password":"",
"require_user_verification":false,"max_upload_in_kilobytes_per_second":0,"max_upload_slots":5,
"minimum_latency_in_ticks":0,"max_heartbeats_per_second":60,"ignore_player_limit_for_returning_players":false,
"allow_commands":"admins-only","autosave_interval":0,"autosave_slots":1,"afk_autokick_interval":0,
"auto_pause":false,"auto_pause_when_players_connect":false,"only_admins_can_pause_the_game":true,
"autosave_only_on_server":true,"non_blocking_saving":false}
EOF
  savefile=$work/write/saves/_autosave-$save.zip
  rm -f "$savefile"
  server_port=$(python3 -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
  cmd+=(--start-server-load-scenario "$scenario" --server-settings "$work/server-settings.json" --bind 127.0.0.1 --port "$server_port")
  "${cmd[@]}" > "$log" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null || true' EXIT
  saved=0
  for (( i = 0; i < 30; i++ )); do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    if grep -qE "$ERRORS" "$log" 2>/dev/null; then break; fi
    if [[ -s $savefile ]] && grep -q 'Saving finished' "$log"; then saved=1; break; fi
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  trap - EXIT
  if (( ! saved )); then
    tail -n 20 "$log"
    die "scenario did not write $savefile"
  fi
  awk '/^\[CORE\]/ || /Saving to|Saving finished/ { print }' "$log"
  exit 0
elif (( play )); then
  cmd+=(--load-scenario "$scenario")
  nohup "${cmd[@]}" > "$log" 2>&1 &
  echo "factorio-test: game started (pid $!), log=$log"
  echo "factorio-test: screenshots land in $work/$mode/script-output"
  exit 0
elif (( client )); then
  cmd+=(--load-scenario "$scenario" --disable-audio)
  "${cmd[@]}" > "$log" 2>&1 &
  pid=$!
  failed=0
  for (( i = 0; i < secs; i++ )); do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    if grep -qE "$ERRORS" "$log" 2>/dev/null; then
      failed=1
      break
    fi
    if grep -q "CAPTURE_COMPLETE" "$log" 2>/dev/null; then
      echo "factorio-test: CAPTURE_COMPLETE received"
      sleep 1
      break
    fi
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  if grep -qE "$ERRORS" "$log" 2>/dev/null; then failed=1; fi
  awk '/^\[/ || /Error/ { print }' "$log"
  if (( failed )); then
    tail -n 25 "$log"
    exit 1
  fi
  echo "factorio-test: client closed; screenshots:"
  ls "$work/$mode/script-output"
  exit 0
elif (( graphics )); then
  savefile=$work/write/saves/_autosave-$save.zip
  [[ -f $savefile ]] || die "no save at $savefile (call game.auto_save(\"$save\") in a test first)"
  cmd+=(--benchmark-graphics "$savefile" --benchmark-ticks "$ticks")
elif (( test_save )); then
  savefile=$work/write/saves/_autosave-$save.zip
  [[ -f $savefile ]] || die "no save at $savefile"
  cmd+=(--test-save "$savefile" --test-ticks "$ticks" --test-arg "$arg")
else
  cmd+=(--test-scenario "$scenario" --test-ticks "$ticks")
  [[ -n $arg ]] && cmd+=(--test-arg "$arg")
fi

status=0
"${cmd[@]}" > "$log" 2>&1 || status=$?

if (( ! graphics && status == 0 )) && ! grep -q 'Test passed at tick' "$log"; then
  echo "factorio-test: scenario exited without an explicit passing result" >&2
  status=1
fi

awk '/^\[/ || /RunTest/ { print } /Error while|non-recoverable/ { n = 8 } n-- > 0 { print }' "$log"
echo "factorio-test: exit=$status log=$log"
exit $status
