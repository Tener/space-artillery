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
  "$ROOT/tools/factorio-test.sh" --client "$ROOT/mods" "awesome-artillery/clips" 600
fi

python3 - "$FRAMES_DIR" "$OUT_DIR" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

frames_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
manifest = json.loads((frames_dir / 'manifest.json').read_text())
fps, every = manifest['fps'], manifest['frame_every']
takes = {take['name']: take for take in manifest['takes']}
events = manifest['events']
CAMERAS = {'follow': ['follow'], 'tactical': ['tactical'], 'production': ['catch', 'cast', 'load-left', 'load-right']}

# A missing frame fails before any loop is written.
for take_name, cameras in CAMERAS.items():
    for camera in cameras:
        have = len(list(frames_dir.glob(f'{camera}-frame-*.jpg')))
        if have != takes[take_name]['frames']:
            raise SystemExit(f"{camera}: {have} frames, expected {takes[take_name]['frames']}")


def segment(camera, take_name, first_tick, last_tick):
    """Frames of one camera between two game ticks, clamped to its take."""
    take = takes[take_name]
    first = max(0, (first_tick - take['first']) // every)
    last = min(take['frames'] - 1, (last_tick - take['first']) // every)
    return camera, first, last - first + 1


def of_kind(kind, take_name=None):
    return [e for e in events if e['kind'] == kind and (take_name is None or e.get('take') == take_name)]


clips = {}

# Follow: the rides that ended in a kill, marked aim point first; each starts and ends on the cannon.
rides = sorted((e for e in of_kind('cycle') if e.get('kill')), key=lambda e: not e.get('marked'))[:2]
if not rides:
    raise SystemExit('follow: no filmed shell killed its asteroid')
clips['follow'] = [segment('follow', 'follow', ride['fire'] - 45, ride['done']) for ride in sorted(rides, key=lambda e: e['fire'])]

# Tactical: five seconds of the wide sector, then the change and seven seconds of the narrow one.
change = of_kind('sector')[0]['tick']
clips['tactical'] = [segment('tactical', 'tactical', change - 5 * 60, change + 7 * 60)]

# Production: catch, then a shell being cast, then a cannon loaded and firing.
production = takes['production']
casts = of_kind('cast')
loads = of_kind('load')
shots = of_kind('fire', 'production')
# the quickest load-then-fire of one cannon, filmed by the camera on its pair
pairs = [(shot['tick'] - load['tick'], load['tick'], shot['tick'], load['gun'])
         for load in loads for shot in shots if shot.get('gun') == load['gun'] and shot['tick'] >= load['tick']]
if not (casts and pairs):
    raise SystemExit('production: missing a cast, or a cannon loaded and then firing')
_, load_tick, shot_tick, gun = min(pairs)
clips['production'] = [
    segment('catch', 'production', production['first'], production['first'] + 3 * 60),
    segment('cast', 'production', casts[0]['tick'] - 120, casts[0]['tick'] + 60),
    segment('load-left' if gun <= 2 else 'load-right', 'production', max(load_tick - 60, shot_tick - 4 * 60), shot_tick + 60),
]

GIF = ('fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];'
       '[b][p]paletteuse=dither=bayer:bayer_scale=3')
for name, segments in clips.items():
    inputs = []
    for camera, first, count in segments:
        inputs += ['-framerate', str(fps), '-start_number', str(first), '-t', str(count / fps),
                   '-i', str(frames_dir / f'{camera}-frame-%04d.jpg')]
    joined = ''.join(f'[{i}:v]' for i in range(len(segments))) + f'concat=n={len(segments)}:v=1:a=0[v]'
    mp4, gif = out_dir / f'clip-{name}.mp4', out_dir / f'clip-{name}.gif'
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', *inputs, '-filter_complex', joined,
                    '-map', '[v]', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart',
                    str(mp4)], check=True)
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(mp4), '-filter_complex', GIF,
                    '-loop', '0', str(gif)], check=True)
    seconds = sum(count for _, _, count in segments) / fps
    print(f'{name}: {seconds:.1f}s, mp4 {mp4.stat().st_size / 1e6:.1f} MB, gif {gif.stat().st_size / 1e6:.1f} MB')
PY
echo "Clips written to $OUT_DIR"
