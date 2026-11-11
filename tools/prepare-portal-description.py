#!/usr/bin/env python3
"""Render the portal description with links pinned to a Git tag or commit."""

import argparse
import os
import re
from pathlib import Path
from urllib.parse import quote, urlsplit


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("ref", help="Git tag or commit used for the published links")
args = parser.parse_args()

root = Path(__file__).resolve().parent.parent
source = root / "docs" / "mod-portal.md"
repository = os.environ.get("GITHUB_REPOSITORY", "Tener/space-artillery")
ref = quote(args.ref, safe="")


def publish_reference(match):
    target = match.group(2)
    if urlsplit(target).scheme or target.startswith(("/", "#")):
        return match.group(0)

    asset = (source.parent / target).resolve()
    if not asset.is_file():
        parser.error(f"Referenced file does not exist: {target}")
    path = quote(asset.relative_to(root).as_posix(), safe="/")
    if asset.suffix.lower() in {".webp", ".gif", ".png", ".jpg", ".jpeg", ".svg"}:
        url = f"https://raw.githubusercontent.com/{repository}/{ref}/{path}"
    else:
        url = f"https://github.com/{repository}/blob/{ref}/{path}"
    return match.group(1) + url


description = re.sub(
    r"^(\[[^\]\n]+\]:[ \t]+)(\S+)[ \t]*$",
    publish_reference,
    source.read_text(),
    flags=re.MULTILINE,
)
output = root / "dist" / "mod-portal.md"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(description)
print(f"Portal description: {output.relative_to(root)} (ref {args.ref})")
