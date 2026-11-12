import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

import release


TODAY = date(2026, 11, 12)


def changelog(version="0.1.2", released=TODAY):
    return (
        release.SEPARATOR
        + f"Version: {version}\nDate: {released.isoformat()}\n"
        + "  Bugfixes:\n    - Fixed targeting.\n      Preserved the shell budget.\n"
    )


class ChangelogTests(unittest.TestCase):
    def test_prepare_preserves_entries_and_history(self):
        old = changelog("0.1.1", TODAY - timedelta(days=1))
        text = changelog() + old
        prepared = release.prepare_changelog(text, "0.1.2", TODAY + timedelta(days=1))
        sections = release.parse_changelog(prepared)
        self.assertEqual(list(sections), ["0.1.2", "0.1.1"])
        self.assertIn("Date: 2026-11-13", sections["0.1.2"])
        self.assertTrue(prepared.endswith(old))
        self.assertIn("    - Fixed targeting.", sections["0.1.2"])

    def test_prepare_new_version(self):
        old = changelog()
        prepared = release.prepare_changelog(old, "0.1.3", TODAY)
        self.assertEqual(list(release.parse_changelog(prepared)), ["0.1.3", "0.1.2"])
        self.assertTrue(prepared.endswith(old))
        with self.assertRaises(ValueError):
            release.prepare_changelog(old, "0.1.1", TODAY)

    def test_invalid_format_and_dates(self):
        text = changelog()
        invalid = [
            text.replace("-" * 99, "-" * 98),
            text.replace("2026-11-12", "2026-02-30"),
            text.replace("2026-11-12", "20261112"),
            text.replace("  Bugfixes:", "\tBugfixes:"),
            text.replace("targeting.", "targeting. "),
            text.replace("  Bugfixes:", "   Bugfixes:"),
            text.replace("  Bugfixes:", "Date: 2026-11-12\n  Bugfixes:"),
            text + text,
            text + text.replace("0.1.2", "0.01.2"),
            text.replace("0.1.2", "0.0.0"),
            text.replace("0.1.2", "0.1.65536"),
        ]
        for candidate in invalid:
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    release.parse_changelog(candidate)

    def test_duplicate_entry(self):
        text = changelog().replace("      Preserved the shell budget.", "    - Fixed targeting.")
        with self.assertRaises(ValueError):
            release.parse_changelog(text)

    def test_notes_keep_only_selected_release_and_continuations(self):
        sections = release.parse_changelog(changelog() + changelog("0.1.1"))
        self.assertEqual(
            release.release_notes(sections["0.1.2"]),
            "Released 2026-11-12\n\n## Bugfixes\n\n- Fixed targeting.\n  Preserved the shell budget.\n",
        )


class TagTests(unittest.TestCase):
    def setUp(self):
        scratch = release.ROOT / "tmp"
        scratch.mkdir(exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        release.git(self.root, "init")
        release.git(self.root, "config", "user.name", "Release tests")
        release.git(self.root, "config", "user.email", "release-tests@example.invalid")
        self.source = self.root / "mods/space-artillery"
        self.source.mkdir(parents=True)
        self.write_release()
        release.git(self.root, "add", "mods")
        release.git(self.root, "commit", "-m", "Release 0.1.2")

    def write_release(self, version="0.1.2", text=None):
        (self.source / "info.json").write_text(json.dumps({"version": version, "title": "Space Artillery"}))
        (self.source / "changelog.txt").write_text(text or changelog())

    def run_cli(self, *arguments):
        tools = self.root / "tools"
        tools.mkdir(exist_ok=True)
        script = tools / "release.py"
        shutil.copyfile(release.__file__, script)
        return subprocess.run(
            [sys.executable, str(script), *arguments],
            check=True, capture_output=True, text=True,
        ).stdout

    def test_prepare_updates_manifest_and_changelog_together(self):
        old = (self.source / "changelog.txt").read_text()
        self.run_cli("prepare", "0.1.3")
        info = json.loads((self.source / "info.json").read_text())
        text = (self.source / "changelog.txt").read_text()
        self.assertEqual(info["version"], "0.1.3")
        self.assertEqual(next(iter(release.parse_changelog(text))), "0.1.3")
        self.assertIn(f"Date: {date.today().isoformat()}", text)
        self.assertTrue(text.endswith(old))

    def test_cli_preserves_utf8(self):
        text = changelog().replace("Fixed targeting.", "Poprawiono celność.")
        (self.source / "changelog.txt").write_text(text, encoding="utf-8")
        self.run_cli("prepare", "0.1.3")
        self.assertTrue((self.source / "changelog.txt").read_text(encoding="utf-8").endswith(text))

    def test_cli_dry_run_and_annotated_tag(self):
        self.write_release(text=changelog(released=date.today()))
        release.git(self.root, "add", "mods")
        release.git(self.root, "commit", "--allow-empty", "-m", "Prepare release")
        self.run_cli("tag", "--dry-run")
        self.assertEqual(release.git(self.root, "tag", "--list"), "")
        self.run_cli("tag")
        self.assertEqual(release.git(self.root, "cat-file", "-t", "refs/tags/v0.1.2"), "tag")
        self.assertEqual(
            release.git(self.root, "rev-parse", "v0.1.2^{}"),
            release.git(self.root, "rev-parse", "HEAD"),
        )

    def test_fresh_release_and_untracked_files(self):
        (self.root / "local-scratch.txt").write_text("untracked")
        self.assertEqual(release.check_tag(self.root, TODAY), ("v0.1.2", "Space Artillery"))

    def test_dirty_worktree_and_index(self):
        (self.source / "changelog.txt").write_text(changelog().replace("targeting.", "aiming."))
        with self.assertRaisesRegex(ValueError, "Commit tracked"):
            release.check_tag(self.root, TODAY)
        release.git(self.root, "add", "mods")
        with self.assertRaisesRegex(ValueError, "Commit tracked"):
            release.check_tag(self.root, TODAY)

    def test_existing_local_and_remote_tags(self):
        release.git(self.root, "tag", "v0.1.2")
        with self.assertRaisesRegex(ValueError, "already exists locally"):
            release.check_tag(self.root, TODAY)
        remote = self.root / "remote.git"
        remote.mkdir()
        release.git(remote, "init", "--bare")
        release.git(self.root, "remote", "add", "origin", str(remote))
        release.git(self.root, "push", "origin", "v0.1.2")
        release.git(self.root, "tag", "-d", "v0.1.2")
        with self.assertRaisesRegex(ValueError, "already exists on origin"):
            release.check_tag(self.root, TODAY)

    def test_tag_date_is_today_but_ci_accepts_historical_dates(self):
        release.load_release(self.root, "v0.1.2")
        with self.assertRaisesRegex(ValueError, "must be today"):
            release.check_tag(self.root, TODAY + timedelta(days=1))

    def test_missing_date_and_empty_entries(self):
        for text, message in [
            (changelog().replace("Date: 2026-11-12\n", ""), "must be today"),
            (release.SEPARATOR + "Version: 0.1.2\nDate: 2026-11-12\n  Changes:\n", "Add changelog entries"),
        ]:
            self.write_release(text=text)
            release.git(self.root, "add", "mods")
            release.git(self.root, "commit", "-m", "Update changelog")
            with self.assertRaisesRegex(ValueError, message):
                release.check_tag(self.root, TODAY)

    def test_manifest_and_tag_mismatches(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            release.load_release(self.root, "v0.1.3")
        self.write_release(version="0.1.3")
        with self.assertRaisesRegex(ValueError, "must match info.json"):
            release.load_release(self.root)


if __name__ == "__main__":
    unittest.main()
