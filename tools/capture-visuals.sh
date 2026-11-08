#!/usr/bin/env bash
# Runs the showcase scenario in client rendering mode for 12 seconds,
# captures high-resolution screenshots and animation frames automatically,
# and generates an optimized showcase GIF / MP4 with ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.factorio-test/play/script-output"
DOCS_DIR="$ROOT/docs"

mkdir -p "$DOCS_DIR"
rm -f "$OUTPUT_DIR"/showcase-*.png "$OUTPUT_DIR"/thumb-*.png

echo "==> Running showcase scenario (waiting for capture to complete, up to 60s)..."
"$ROOT/tools/factorio-test.sh" --client "$ROOT/mods" awesome-artillery/showcase 60

echo "==> Collecting visuals..."
if [[ -f "$OUTPUT_DIR/showcase-16x9.png" ]]; then
  cp "$OUTPUT_DIR/showcase-16x9.png" "$DOCS_DIR/"
  echo "  - $DOCS_DIR/showcase-16x9.png"
fi
if [[ -f "$OUTPUT_DIR/showcase-square.png" ]]; then
  cp "$OUTPUT_DIR/showcase-square.png" "$DOCS_DIR/"
  echo "  - $DOCS_DIR/showcase-square.png"
fi
if [[ -f "$OUTPUT_DIR/showcase-thumb-512.png" ]]; then
  cp "$OUTPUT_DIR/showcase-thumb-512.png" "$DOCS_DIR/"
  echo "  - $DOCS_DIR/showcase-thumb-512.png"
fi

# If frame sequence exists and ffmpeg is installed, assemble GIF and MP4
if compgen -G "$OUTPUT_DIR/showcase-frame-*.png" > /dev/null && command -v ffmpeg > /dev/null; then
  echo "==> Generating showcase GIF and MP4 via ffmpeg..."
  ffmpeg -y -hide_banner -loglevel error -framerate 20 \
    -i "$OUTPUT_DIR/showcase-frame-%04d.png" \
    -filter_complex "[0:v] fps=20,scale=800:-1:flags=lanczos,split [a][b];[a] palettegen=max_colors=128:stats_mode=diff [p];[b][p] paletteuse=dither=bayer:bayer_scale=3" \
    "$DOCS_DIR/showcase.gif"
  echo "  - $DOCS_DIR/showcase.gif ($(du -h "$DOCS_DIR/showcase.gif" | cut -f1))"

  ffmpeg -y -hide_banner -loglevel error -framerate 20 \
    -i "$OUTPUT_DIR/showcase-frame-%04d.png" \
    -c:v libx264 -pix_fmt yuv420p -crf 20 \
    "$DOCS_DIR/showcase.mp4"
  echo "  - $DOCS_DIR/showcase.mp4 ($(du -h "$DOCS_DIR/showcase.mp4" | cut -f1))"

  rm -f "$OUTPUT_DIR"/showcase-frame-*.png
fi

echo "==> Visuals capture complete."
