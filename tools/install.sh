#!/usr/bin/env bash
# Builds the release zip via tools/package.sh and installs it into Factorio's mods
# directory, removing any existing awesome-artillery_*.zip versions first.
# Usage: tools/install.sh [FACTORIO_MODS_DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="awesome-artillery"
SRC="$ROOT/mods/$MOD"
VERSION="$(sed -n 's/.*"version": *"\([0-9.]*\)".*/\1/p' "$SRC/info.json")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "install: no version in info.json" >&2; exit 2; }

if [[ $# -ge 1 ]]; then
  DEST="$1"
elif [[ -n "${FACTORIO_MODS:-}" ]]; then
  DEST="$FACTORIO_MODS"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  DEST="$HOME/Library/Application Support/factorio/mods"
else
  DEST="$HOME/.factorio/mods"
fi

"$ROOT/tools/package.sh"

mkdir -p "$DEST"
rm -f "$DEST/${MOD}_"*.zip
cp "$ROOT/dist/${MOD}_${VERSION}.zip" "$DEST/"
echo "install: $DEST/${MOD}_${VERSION}.zip"
ls -la "$DEST/${MOD}_"*.zip
