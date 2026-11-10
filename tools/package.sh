#!/bin/bash
# Builds the release zip: dist/awesome-artillery_<version>.zip, holding one folder
# awesome-artillery_<version>/ as the mod portal expects. Test scenarios are left out.
# Usage: tools/package.sh
set -euo pipefail

source "$(dirname "$0")/common.sh"

NAME="${MOD}_${VERSION}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME" "$ROOT/dist"
rsync -a --exclude scenarios --exclude '.*' "$SRC/" "$STAGE/$NAME/"
rm -f "$ROOT/dist/$NAME.zip"
(cd "$STAGE" && zip -qr "$ROOT/dist/$NAME.zip" "$NAME")
echo "package: dist/$NAME.zip"
unzip -l "$ROOT/dist/$NAME.zip"
