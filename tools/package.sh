#!/bin/bash
# Builds the release zip: dist/awesome-artillery_<version>.zip, holding one folder
# awesome-artillery_<version>/ as the mod portal expects. Test scenarios are left out.
# Usage: tools/package.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="awesome-artillery"
SRC="$ROOT/mods/$MOD"
VERSION="$(sed -n 's/.*"version": *"\([0-9.]*\)".*/\1/p' "$SRC/info.json")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "package: no version in info.json" >&2; exit 2; }

NAME="${MOD}_${VERSION}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME" "$ROOT/dist"
rsync -a --exclude scenarios --exclude '.*' "$SRC/" "$STAGE/$NAME/"
rm -f "$ROOT/dist/$NAME.zip"
(cd "$STAGE" && zip -qr "$ROOT/dist/$NAME.zip" "$NAME")
echo "package: dist/$NAME.zip"
unzip -l "$ROOT/dist/$NAME.zip"
