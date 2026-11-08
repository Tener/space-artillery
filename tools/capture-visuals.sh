#!/usr/bin/env bash
# Runs the unified showcase scenario once in client rendering mode with alt-mode enabled,
# captures high-resolution screenshots and animation frames across all 5 showcase phases,
# and generates optimized GIFs and MP4s with ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.factorio-test/play/script-output"
DOCS_DIR="$ROOT/docs"

mkdir -p "$DOCS_DIR"

echo "=========================================================="
echo "==> Running unified showcase scenario in Factorio..."
echo "=========================================================="
rm -f "$OUTPUT_DIR"/*.png

"$ROOT/tools/factorio-test.sh" --client "$ROOT/mods" "awesome-artillery/showcase" 60

echo "=========================================================="
echo "==> Processing captured stills..."
echo "=========================================================="

for shot in production-16x9 combat-16x9 promethium-16x9 hero-16x9 hero-square computer-gui; do
  src="$OUTPUT_DIR/${shot}.png"
  dst="$DOCS_DIR/showcase-${shot}.png"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    echo "  - Stored: $dst"
  else
    echo "  ! Missing: $src"
  fi
done

encode_animation() {
  local name="$1"
  local frame_pattern="$OUTPUT_DIR/${name}-frame-%04d.png"
  local gif="$DOCS_DIR/showcase-${name}.gif"
  local mp4="$DOCS_DIR/showcase-${name}.mp4"

  if compgen -G "$OUTPUT_DIR/${name}-frame-*.png" > /dev/null && command -v ffmpeg > /dev/null; then
    echo "==> Encoding $name animation..."
    ffmpeg -y -hide_banner -loglevel error -framerate 20 \
      -i "$frame_pattern" \
      -filter_complex "[0:v] fps=20,scale=800:-1:flags=lanczos,split [a][b];[a] palettegen=max_colors=128:stats_mode=diff [p];[b][p] paletteuse=dither=bayer:bayer_scale=3" \
      "$gif"
    echo "  - GIF: $gif ($(du -h "$gif" | cut -f1))"

    ffmpeg -y -hide_banner -loglevel error -framerate 20 \
      -i "$frame_pattern" \
      -c:v libx264 -pix_fmt yuv420p -crf 20 \
      "$mp4"
    echo "  - MP4: $mp4 ($(du -h "$mp4" | cut -f1))"

    rm -f "$OUTPUT_DIR"/${name}-frame-*.png
  fi
}

echo "=========================================================="
echo "==> Compiling animation GIFs and MP4s..."
echo "=========================================================="
encode_animation "production"
encode_animation "combat"
encode_animation "promethium"
encode_animation "hero"

echo "=========================================================="
echo "==> Showcase capture complete."
echo "=========================================================="
ls -lh "$DOCS_DIR"/showcase-*
