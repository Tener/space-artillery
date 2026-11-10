# Sourced by package.sh and install.sh: mod paths and the version from info.json.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="awesome-artillery"
SRC="$ROOT/mods/$MOD"
VERSION="$(sed -n 's/.*"version": *"\([0-9.]*\)".*/\1/p' "$SRC/info.json")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$(basename "$0" .sh): no version in info.json" >&2; exit 2; }
