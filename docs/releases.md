# Releases

Run commands from the repository root with Python 3.9 or later and Git. Commit
implementation changes first. The example below releases version `0.1.3`.

1. Prepare the version and dated changelog section.

   ```sh
   python3 tools/release.py prepare 0.1.3
   ```

2. Add curated, player-facing entries to [changelog.txt](../mods/space-artillery/changelog.txt).
   Repeating `prepare` for the same unreleased version refreshes its date and
   preserves the entries.

3. Run local checks. See [test setup](testing.md) for Factorio requirements.

   ```sh
   make test
   python3 -m unittest discover -s tools -p test_release.py
   ```

4. Commit the version bump and changelog together.

   ```sh
   git add mods/space-artillery/info.json mods/space-artillery/changelog.txt
   git commit -m "Release 0.1.3"
   ```

5. Validate, create the annotated tag, and push it.

   ```sh
   python3 tools/release.py tag --dry-run
   python3 tools/release.py tag
   git push origin v0.1.3
   ```

   Tagging requires today's changelog date, committed tracked changes, valid
   changelog formatting, and an unused tag locally and on the configured remote.

6. Wait for the [build workflow](https://github.com/Tener/space-artillery/actions/workflows/build.yml).
   Download the mod ZIP and plain `mod-portal.md` from the
   [GitHub release](https://github.com/Tener/space-artillery/releases). Upload
   the ZIP to the Factorio mod portal and paste the generated Markdown into its
   description. The ZIP supplies the portal changelog, and the current version's
   changelog section supplies the GitHub release notes.
