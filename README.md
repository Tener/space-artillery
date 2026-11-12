# Space Artillery

**Automated artillery defense against asteroids.** Requires Factorio 2.1 + Space Age.

Space platform artillery leads incoming asteroids and coordinates fire between
cannons to avoid overkill. A powered targeting computer selects asteroid sizes,
chunk types and firing sectors, with circuit network overrides. Shots that would
detonate near platform foundation are held back.

The mod adds steel and promethium artillery shells cast in space, plus research
for turret rotation speed and shell velocity. Computer settings persist in
blueprints and can be configured on ghosts before construction.

## Showcases

**Shell follow** shows the launch, flight in slow motion, and interception.

![The camera follows a shell from the cannon to an asteroid interception](docs/previews/shell-follow.webp)

| Sector control | Compact production |
| --- | --- |
| ![The firing sector narrows and turns as artillery intercepts asteroids](docs/previews/sector-control.webp) | ![Collectors, foundry casting, and cannon loading in alt-mode](docs/previews/compact-production.webp) |

| Battery combat | Promethium impact |
| --- | --- |
| ![An artillery battery intercepts incoming asteroids during flight](docs/previews/battery-combat.webp) | ![A promethium shell breaks up a huge asteroid](docs/previews/promethium-impact.webp) |

| Asteroid-to-ammunition factory | Ship overview |
| --- | --- |
| ![Collected chunks move through crushing, component manufacture, and shell casting](docs/previews/asteroid-factory.webp) | ![Thrusters, factory, and artillery in action before a full view of the ship in flight](docs/previews/ship-overview.webp) |

The compact ship casts its own shells with steel made from collected chunks.
It carries radars and explosives as cargo. The larger factory makes its
components and propellant onboard. [Capture notes](docs/capture-notes.md)

See the [mod description](docs/mod-portal.md) for research progression, ammunition
stats, computer controls and compatibility.

## Build and install

```sh
make package
```

This builds `dist/space-artillery_<version>.zip`. Copy it into Factorio's mods
directory and enable **Space Artillery** in the game. `make install` builds and
copies it automatically; set `FACTORIO_MODS` to use a custom mods directory.
Packaging requires Bash, Make, rsync and zip.

## Releases

Use Python 3.9 or later and Git to prepare a release. For example, after the
implementation changes are committed:

```sh
python3 tools/release.py prepare 0.1.3
```

This updates `info.json` and creates the changelog section with today's date.
Repeating it for the same unreleased version refreshes the date and preserves
the entries. Write the player-facing entries, then commit those two files together:

```sh
git add mods/space-artillery/info.json mods/space-artillery/changelog.txt
git commit -m "Release 0.1.3"
python3 tools/release.py tag --dry-run
python3 tools/release.py tag
git push origin v0.1.3
```

Tagging checks the declared version, Factorio changelog formatting, nonempty
entries, and a YYYY-MM-DD date equal to today on the machine running the command.
It also checks for tracked working-tree or index changes and existing tags
locally and on `origin` when a remote is configured.

GitHub Actions validates the changelog and uses the matching version section for
GitHub release notes. Rebuilding an existing tag accepts its historical date.
Run `python3 tools/release.py check` to check the changelog locally, or
`python3 -m unittest discover -s tools -p test_release.py` to test the release
tool using temporary local repositories under `tmp/`.

## Development

Mod sources are in [mods/space-artillery](mods/space-artillery). Tests require
Factorio 2.1.24 or later, Space Age and Python 3. The runner defaults to the macOS
Steam installation; set `FACTORIO` to the executable's absolute path elsewhere.

| Command | Purpose |
| --- | --- |
| `make test` | Run all 20 local functional cases, including save/reload. |
| `make test-smoke` | Run the short technology, prototype and GUI checks. |
| `make test-demos` | Check production and combat in both capture scenarios without rendering. |
| `make play` | Open the interactive playtest ship. |
| `./tools/capture-clips.sh` | Render and encode the compact-ship recordings into `tmp/clips/` for review. |

See [testing instructions](docs/testing.md) for coverage and individual cases.
[Capture instructions](docs/capture-notes.md) cover rendering and encoding;
captures open a game window and require FFmpeg and Python 3.
