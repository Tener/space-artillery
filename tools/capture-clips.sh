#!/usr/bin/env bash
# Film the clips scenario and cut the page loops from its takes, as MP4 and GIF.
# Usage: tools/capture-clips.sh [--encode-only] [OUT_DIR]
#   --encode-only  reuse the frames of the last capture
#   OUT_DIR        where the loops go (default tmp/clips, for review before publishing to docs/)
# Raw frames and the event manifest remain in .factorio-test/play/script-output/clips.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES_DIR="$ROOT/.factorio-test/play/script-output/clips"

capture=1
if [[ ${1:-} == --encode-only ]]; then capture=0; shift; fi
[[ $# -le 1 ]] || { echo "usage: $0 [--encode-only] [OUT_DIR]" >&2; exit 2; }
OUT_DIR="${1:-$ROOT/tmp/clips}"
command -v ffmpeg > /dev/null
command -v python3 > /dev/null
mkdir -p "$OUT_DIR" "$FRAMES_DIR"

if (( capture )); then
  # Remove only this scenario's outputs; unrelated script-output files are retained.
  find "$FRAMES_DIR" -maxdepth 1 -type f -name '*-frame-*.jpg' -delete
  if [[ -f "$FRAMES_DIR/manifest.json" ]]; then rm "$FRAMES_DIR/manifest.json"; fi
  "$ROOT/tools/factorio-test.sh" --client "$ROOT/mods" "space-artillery/clips" 600
fi

python3 - "$FRAMES_DIR" "$OUT_DIR" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

frames_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
manifest = json.loads((frames_dir / 'manifest.json').read_text())
fps = manifest['fps']
takes = {take['name']: take for take in manifest['takes']}
events = manifest['events']
CAMERAS = {'follow': ['follow'], 'tactical': ['tactical'], 'production': ['catch', 'cast', 'load']}

# A missing frame fails before any loop is written.
for take_name, cameras in CAMERAS.items():
    for camera in cameras:
        have = len(list(frames_dir.glob(f'{camera}-frame-*.jpg')))
        if have != takes[take_name]['frames']:
            raise SystemExit(f"{camera}: {have} frames, expected {takes[take_name]['frames']}")


def segment(camera, take_name, first_tick, last_tick, slow=False):
    """Frames of one camera between two game ticks, clamped to its take, and the rate to play
    them at: real time, or one filmed tick per output frame when slow."""
    take = takes[take_name]
    every = take['every']
    first = max(0, (first_tick - take['first']) // every)
    last = min(take['frames'] - 1, (last_tick - take['first']) // every)
    return camera, first, last - first + 1, fps if slow else 60 / every


def of_kind(kind, take_name=None):
    return [e for e in events if e['kind'] == kind and (take_name is None or e.get('take') == take_name)]


clips = {}

# Follow: one ride that ended in a kill, preferring a marked aim point and a big asteroid. It starts
# and ends on the cannon; the shell's flight and the first half second after impact are slowed down.
rides = sorted((e for e in of_kind('cycle') if e.get('kill')),
               key=lambda e: (not e.get('marked'), not e['kill'].startswith('big')))
if not rides:
    raise SystemExit('follow: no filmed shell killed its asteroid')
ride = rides[0]
clips['follow'] = [
    segment('follow', 'follow', ride['fire'] - 45, ride['fire'] - 1),
    segment('follow', 'follow', ride['fire'], ride['impact'] + 30, slow=True),
    segment('follow', 'follow', ride['impact'] + 31, ride['done']),
]

# Tactical: five seconds of the wide sector, then the change and seven seconds of the narrow one.
change = of_kind('sector')[0]['tick']
clips['tactical'] = [segment('tactical', 'tactical', change - 5 * 60, change + 7 * 60)]

# Production: catch, then a shell being cast, then a cannon loaded and firing.
production = takes['production']
casts = of_kind('cast')
loads = of_kind('load')
shots = of_kind('fire', 'production')
# the quickest load-then-fire of one cannon
pairs = [(shot['tick'] - load['tick'], load['tick'], shot['tick'])
         for load in loads for shot in shots if shot.get('gun') == load['gun'] and shot['tick'] >= load['tick']]
if not (casts and pairs):
    raise SystemExit('production: missing a cast, or a cannon loaded and then firing')
_, load_tick, shot_tick = min(pairs)
clips['production'] = [
    segment('catch', 'production', production['first'], production['first'] + 3 * 60),
    segment('cast', 'production', casts[0]['tick'] - 120, casts[0]['tick'] + 60),
    segment('load', 'production', max(load_tick - 60, shot_tick - 4 * 60), shot_tick + 60),
]

# Starfield noise and heavy dithering are what make these GIFs large; a light dither keeps the
# gradients without the bulk.
GIF = ('fps=12.5,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];'
       '[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle')
for name, segments in clips.items():
    inputs = []
    for camera, first, count, rate in segments:
        inputs += ['-framerate', str(rate), '-start_number', str(first), '-t', str(count / rate),
                   '-i', str(frames_dir / f'{camera}-frame-%04d.jpg')]
    joined = ''.join(f'[{i}:v]fps={fps}[s{i}];' for i in range(len(segments)))
    joined += ''.join(f'[s{i}]' for i in range(len(segments))) + f'concat=n={len(segments)}:v=1:a=0[v]'
    mp4, gif = out_dir / f'clip-{name}.mp4', out_dir / f'clip-{name}.gif'
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', *inputs, '-filter_complex', joined,
                    '-map', '[v]', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart',
                    str(mp4)], check=True)
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(mp4), '-filter_complex', GIF,
                    '-loop', '0', str(gif)], check=True)
    seconds = sum(count / rate for _, _, count, rate in segments)
    print(f'{name}: {seconds:.1f}s, mp4 {mp4.stat().st_size / 1e6:.1f} MB, gif {gif.stat().st_size / 1e6:.1f} MB')
PY
echo "Clips written to $OUT_DIR"
