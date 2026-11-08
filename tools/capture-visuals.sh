#!/usr/bin/env bash
# Runs each focused showcase scenario in client rendering mode,
# captures high-resolution screenshots and animation frames automatically,
# and generates optimized GIFs and MP4s with ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.factorio-test/play/script-output"
DOCS_DIR="$ROOT/docs"

mkdir -p "$DOCS_DIR"

capture_scenario() {
  local name="$1"
  local scenario="$2"
  local still_prefix="$3"
  local frame_prefix="$4"
  local has_frames="$5"

  echo "=========================================================="
  echo "==> Capturing: $name ($scenario)"
  echo "=========================================================="
  rm -f "$OUTPUT_DIR"/*-frame-*.png "$OUTPUT_DIR"/*-16x9.png "$OUTPUT_DIR"/*-square.png "$OUTPUT_DIR"/computer-gui.png

  "$ROOT/tools/factorio-test.sh" --client "$ROOT/mods" "$scenario" 60

  # Copy stills
  for f in "$OUTPUT_DIR"/${still_prefix}-16x9.png "$OUTPUT_DIR"/${still_prefix}-square.png "$OUTPUT_DIR"/computer-gui.png; do
    if [[ -f "$f" ]]; then
      local base
      base="$(basename "$f")"
      cp "$f" "$DOCS_DIR/showcase-$base"
      echo "  - Stored: $DOCS_DIR/showcase-$base"
    fi
  done

  # Compile animation if frames exist
  if [[ "$has_frames" == "true" ]] && compgen -G "$OUTPUT_DIR/${frame_prefix}-frame-*.png" > /dev/null && command -v ffmpeg > /dev/null; then
    local gif="$DOCS_DIR/showcase-${name}.gif"
    local mp4="$DOCS_DIR/showcase-${name}.mp4"

    echo "  - Encoding $gif..."
    ffmpeg -y -hide_banner -loglevel error -framerate 20 \
      -i "$OUTPUT_DIR/${frame_prefix}-frame-%04d.png" \
      -filter_complex "[0:v] fps=20,scale=800:-1:flags=lanczos,split [a][b];[a] palettegen=max_colors=128:stats_mode=diff [p];[b][p] paletteuse=dither=bayer:bayer_scale=3" \
      "$gif"
    echo "    Size: $(du -h "$gif" | cut -f1)"

    echo "  - Encoding $mp4..."
    ffmpeg -y -hide_banner -loglevel error -framerate 20 \
      -i "$OUTPUT_DIR/${frame_prefix}-frame-%04d.png" \
      -c:v libx264 -pix_fmt yuv420p -crf 20 \
      "$mp4"
    echo "    Size: $(du -h "$mp4" | cut -f1)"

    rm -f "$OUTPUT_DIR"/${frame_prefix}-frame-*.png
  fi
}

capture_scenario "hero" "awesome-artillery/showcase-hero" "hero" "hero" "true"
capture_scenario "combat" "awesome-artillery/showcase-combat" "combat" "combat" "true"
capture_scenario "computer" "awesome-artillery/showcase-computer" "computer" "" "false"
capture_scenario "production" "awesome-artillery/showcase-production" "production" "production" "true"
capture_scenario "promethium" "awesome-artillery/showcase-promethium" "promethium" "promethium" "true"

echo "=========================================================="
echo "==> All showcases captured successfully."
echo "=========================================================="
ls -lh "$DOCS_DIR"/showcase-*
