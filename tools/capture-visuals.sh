#!/usr/bin/env bash
# Capture the showcase demos and encode validated frame sequences as MP4 and GIF.
# Usage: tools/capture-visuals.sh [--encode-only]
# Raw frames and the event manifest remain in .factorio-test/play/script-output/showcase.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.factorio-test/play/script-output/showcase"
DOCS_DIR="$ROOT/docs"

case ${1:-} in
  "") capture=1 ;;
  --encode-only) capture=0 ;;
  *) echo "usage: $0 [--encode-only]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "usage: $0 [--encode-only]" >&2; exit 2; }
command -v ffmpeg > /dev/null
command -v ffprobe > /dev/null
command -v python3 > /dev/null
mkdir -p "$DOCS_DIR" "$OUTPUT_DIR"

if (( capture )); then
  # Remove only this scenario's outputs; unrelated script-output files are retained.
  find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*-frame-*.png' -delete
  if [[ -f "$OUTPUT_DIR/manifest.json" ]]; then rm "$OUTPUT_DIR/manifest.json"; fi
  "$ROOT/tools/factorio-test.sh" --client "$ROOT/mods" "awesome-artillery/showcase" 600
fi

# A missing frame or an unresolved engagement fails before any published clip changes.
python3 - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text())
previews = {}
for shot in manifest['shots']:
    expected = {f"{shot['name']}-frame-{i:04d}.png" for i in range(shot['frames'])}
    actual = {p.name for p in root.glob(f"{shot['name']}-frame-*.png")}
    if actual != expected:
        raise SystemExit(f"{shot['name']}: incomplete sequence; missing={len(expected - actual)}, extra={len(actual - expected)}")
    print(f"{shot['name']}: {len(actual)} frames, {len(actual) / manifest['fps']:g}s")
    duration = shot['frames'] / manifest['fps']
    views = shot['views']
    if len(views) > 1:
        starts = [(view['first'] - shot['first']) / 60 for view in views]
        intervals = [(start, min(start + 4, duration)) for start in starts]
        labels = ''.join(f'[v{i}]' for i in range(len(intervals)))
        filters = [f'[0:v]split={len(intervals)}{labels}']
        filters += [f'[v{i}]trim=start={start}:end={end},setpts=PTS-STARTPTS[c{i}]'
                    for i, (start, end) in enumerate(intervals)]
        filters += [''.join(f'[c{i}]' for i in range(len(intervals)))
                    + f'concat=n={len(intervals)}:v=1:a=0[preview]']
    else:
        intervals = [(0, min(8, duration))]
        filters = [f'[0:v]trim=duration={intervals[0][1]},setpts=PTS-STARTPTS[preview]']
    filters += ['[preview]fps=10,scale=800:-1:flags=lanczos,split[a][b]',
                '[a]palettegen=max_colors=128:stats_mode=diff[p]',
                '[b][p]paletteuse=dither=bayer:bayer_scale=3']
    (root / f"gif-filter-{shot['name']}.txt").write_text(';'.join(filters))
    preview_duration = sum(end - start for start, end in intervals)
    previews[shot['name']] = {'frames': round(preview_duration * 10), 'duration': preview_duration}
if manifest['stats']['kills']['combat'] < 12:
    raise SystemExit('combat: missing resolved interceptions')
huge_kills = sum(e['kind'] == 'kill' and e.get('name') == 'huge-promethium-asteroid'
                 and e['phase'] == 'promethium' for e in manifest['stats']['events'])
if huge_kills < 3:
    raise SystemExit('promethium: three huge asteroids must be intercepted')
if not all(count > 0 for count in manifest['stats']['production'].values()):
    raise SystemExit('production: incomplete material flow')
if not all(state['speed'] > 0 for state in manifest['stats']['flight'].values()):
    raise SystemExit('flight: ship is stationary')
(root / 'previews.json').write_text(json.dumps(previews))
PY

for name in production combat promethium hero; do
  echo "Encoding $name"
  ffmpeg -y -hide_banner -loglevel error -framerate 20 -start_number 0 \
    -i "$OUTPUT_DIR/${name}-frame-%04d.png" \
    -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart \
    "$OUTPUT_DIR/showcase-${name}.mp4"
  gif_filter=$(cat "$OUTPUT_DIR/gif-filter-${name}.txt")
  ffmpeg -y -hide_banner -loglevel error \
    -i "$OUTPUT_DIR/showcase-${name}.mp4" \
    -filter_complex "$gif_filter" \
    -loop 0 "$OUTPUT_DIR/showcase-${name}.gif"
done

python3 - "$OUTPUT_DIR" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text())
previews = json.loads((root / 'previews.json').read_text())
for shot in manifest['shots']:
    for extension in ['mp4', 'gif']:
        path = root / f"showcase-{shot['name']}.{extension}"
        info = json.loads(subprocess.check_output([
            'ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height,nb_read_frames:format=duration',
            '-of', 'json', str(path),
        ]))
        stream = info['streams'][0]
        expected_size = (manifest['width'], manifest['height']) if extension == 'mp4' else (800, 450)
        expected_frames = shot['frames'] if extension == 'mp4' else previews[shot['name']]['frames']
        expected_duration = shot['frames'] / manifest['fps'] if extension == 'mp4' else previews[shot['name']]['duration']
        assert (stream['width'], stream['height']) == expected_size, path
        assert int(stream['nb_read_frames']) == expected_frames, path
        assert abs(float(info['format']['duration']) - expected_duration) < 0.1, path
        print(f"Verified {path.name}")
PY

for name in production combat promethium hero; do
  cp "$OUTPUT_DIR/showcase-${name}.mp4" "$DOCS_DIR/"
  cp "$OUTPUT_DIR/showcase-${name}.gif" "$DOCS_DIR/"
done
echo "Showcase demos written to $DOCS_DIR"
