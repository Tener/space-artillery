#!/usr/bin/env python3
"""Prepare a release commit, validate its changelog, and create a version tag."""

import argparse
import json
import re
import subprocess
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SEPARATOR = "-" * 99 + "\n"


def version_number(version):
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError(f"Invalid version {version!r}")
    numbers = tuple(map(int, version.split(".")))
    if max(numbers) > 65535 or numbers == (0, 0, 0):
        raise ValueError(f"Invalid version {version}")
    return numbers


def parse_changelog(text):
    if not text.startswith(SEPARATOR):
        raise ValueError("Changelog must start with exactly 99 dashes")
    sections = {}
    versions = set()
    for section in text.split(SEPARATOR)[1:]:
        lines = section.splitlines()
        if not lines or not re.fullmatch(r"Version: [0-9]+\.[0-9]+\.[0-9]+", lines[0]):
            raise ValueError("Each separator must be followed by a numeric Version line")
        version = lines[0].removeprefix("Version: ")
        numbers = version_number(version)
        if numbers in versions:
            raise ValueError(f"Duplicate version {version}")
        versions.add(numbers)
        category = None
        entry = False
        dated = False
        entries = {}
        for line in lines[1:]:
            if "\t" in line or line != line.rstrip():
                raise ValueError(f"{version}: tabs and trailing whitespace are invalid")
            if not line:
                continue
            if line.startswith("Date: "):
                value = line.removeprefix("Date: ")
                if dated or date.fromisoformat(value).isoformat() != value:
                    raise ValueError(f"{version}: use one Date line in YYYY-MM-DD format")
                dated = True
            elif re.fullmatch(r"  \S.*:", line):
                category, entry = line[2:-1], False
                entries.setdefault(category, set())
            elif line.startswith("    - ") and category:
                entry = True
            elif line.startswith("      ") and entry:
                pass
            else:
                raise ValueError(f"{version}: invalid changelog line {line!r}")
            if line.startswith(("    - ", "      ")) and category:
                content = line[6:]
                if content in entries[category]:
                    raise ValueError(f"{version}: duplicate entry line in {category}")
                entries[category].add(content)
        sections[version] = lines
    return sections


def prepare_changelog(text, version, released):
    version_number(version)
    sections = parse_changelog(text)
    current = next(iter(sections))
    if version in sections and version != current:
        raise ValueError(f"{version} is a historical entry. Update info.json to the next version")
    if version != current:
        if version_number(version) <= version_number(current):
            raise ValueError("The new version must be newer than the current changelog entry")
        return SEPARATOR + f"Version: {version}\nDate: {released.isoformat()}\n  Changes:\n" + text
    lines = sections[current]
    dates = [i for i, line in enumerate(lines) if line.startswith("Date: ")]
    if dates:
        lines[dates[0]] = f"Date: {released.isoformat()}"
    else:
        lines.insert(1, f"Date: {released.isoformat()}")
    parts = text.split(SEPARATOR)
    parts[1] = "\n".join(lines) + "\n"
    return SEPARATOR.join(parts)


def release_notes(lines):
    notes = []
    for line in lines[1:]:
        if line.startswith("Date: "):
            notes.append(f"Released {line.removeprefix('Date: ')}")
        elif re.fullmatch(r"  \S.*:", line):
            notes.extend(["", f"## {line[2:-1]}", ""])
        elif line.startswith("    - "):
            notes.append(line[4:])
        elif line.startswith("      "):
            notes.append(line[4:])
    return "\n".join(notes).strip() + "\n"


def git(root, *arguments):
    return subprocess.run(
        ["git", *arguments], cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()


def load_release(root, tag=None):
    source = root / "mods/space-artillery"
    info = json.loads((source / "info.json").read_text(encoding="utf-8"))
    version = info["version"]
    version_number(version)
    sections = parse_changelog((source / "changelog.txt").read_text(encoding="utf-8"))
    if next(iter(sections)) != version:
        raise ValueError(f"The first changelog version must match info.json ({version})")
    if tag and tag != f"v{version}":
        raise ValueError(f"Tag {tag} does not match info.json and changelog version {version}")
    return info, sections


def check_tag(root, today, remote="origin"):
    info, sections = load_release(root)
    version = info["version"]
    tag = f"v{version}"
    if git(root, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Commit tracked working-tree and index changes before tagging")
    if git(root, "tag", "--list", tag):
        raise ValueError(f"Tag {tag} already exists locally")
    lines = sections[version]
    released = next((line[6:] for line in lines if line.startswith("Date: ")), None)
    if released != today.isoformat():
        raise ValueError(f"Changelog date must be today ({today.isoformat()}) for a new tag, found {released!r}")
    if not any(line.startswith("    - ") and line[6:].strip() for line in lines):
        raise ValueError("Add changelog entries before tagging")
    remotes = git(root, "remote").splitlines()
    if remotes:
        if remote not in remotes:
            raise ValueError(f"Remote {remote!r} is not configured")
        if git(root, "ls-remote", "--tags", remote, f"refs/tags/{tag}"):
            raise ValueError(f"Tag {tag} already exists on {remote}")
    return tag, info["title"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("prepare", help="Update info.json and prepare a dated changelog section")
    prepare.add_argument("version", help="Version for the release commit")
    for command in ("check", "notes"):
        command_parser = commands.add_parser(command)
        command_parser.add_argument("--tag", help="Check the release tag against info.json")
    tag_parser = commands.add_parser("tag", help="Validate the release commit and create an annotated tag")
    tag_parser.add_argument("--dry-run", action="store_true", help="Run tagging checks without creating a tag")
    tag_parser.add_argument("--remote", default="origin", help="Remote checked for an existing tag")
    args = parser.parse_args()
    source = ROOT / "mods/space-artillery/changelog.txt"
    try:
        if args.command == "prepare":
            info = json.loads((source.parent / "info.json").read_text(encoding="utf-8"))
            version_number(args.version)
            if git(ROOT, "tag", "--list", f"v{args.version}"):
                raise ValueError(f"Tag v{args.version} already exists locally. Prepare a new version")
            released = date.today()
            prepared = prepare_changelog(source.read_text(encoding="utf-8"), args.version, released)
            parse_changelog(prepared)
            source.write_text(prepared, encoding="utf-8")
            info["version"] = args.version
            (source.parent / "info.json").write_text(
                json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8",
            )
            print(f"Prepared {args.version} dated {released.isoformat()}. Edit the entries and commit info.json and changelog.txt together.")
            return
        if args.command == "tag":
            tag, title = check_tag(ROOT, date.today(), args.remote)
            if args.dry_run:
                print(f"Checks passed for {tag}.")
            else:
                git(ROOT, "tag", "-a", tag, "-m", f"{title} {tag[1:]}")
                print(f"Created local annotated tag {tag}.")
            return
        info, sections = load_release(ROOT, args.tag)
        version = info["version"]
        if args.command == "notes":
            output = ROOT / "dist/release-notes.md"
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(release_notes(sections[version]), encoding="utf-8")
            print(f"Release notes: {output.relative_to(ROOT)}")
        else:
            print(f"Changelog format, dates and version {version} verified.")
    except subprocess.CalledProcessError as error:
        parser.error(error.stderr.strip() or str(error))
    except (ValueError, OSError, KeyError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
