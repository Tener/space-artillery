# Space Artillery

**Automated artillery defense against asteroids.** Requires Factorio 2.1 + Space Age.

Space platform artillery leads incoming asteroids and coordinates fire between
cannons to avoid overkill. A powered targeting computer selects asteroid sizes,
chunk types and firing sectors, with circuit network overrides. Shots that would
detonate near platform foundation are held back.

The mod adds steel and promethium artillery shells cast in space, plus research
for turret rotation speed and shell velocity. Computer settings persist in
blueprints and can be configured on ghosts before construction.

[![Follow an artillery shell from the cannon to an asteroid interception](docs/clip-follow.gif)](docs/clip-follow.mp4)

## Showcases

| Recording | What it shows | Watch |
| --- | --- | --- |
| Shell follow | One cannon firing, the shell's flight slowed to a third of real time, and the interception. | [MP4](docs/clip-follow.mp4) · [GIF](docs/clip-follow.gif) |
| Sector control | The firing sector narrows and turns left while artillery intercepts asteroids inside it. | [MP4](docs/clip-tactical.mp4) · [GIF](docs/clip-tactical.gif) |
| Production | Asteroid collection, shell casting, and loading and firing, with alt-mode enabled. | [MP4](docs/clip-production.mp4) · [GIF](docs/clip-production.gif) |
| Promethium | Promethium artillery shells breaking huge asteroids. | [MP4](docs/showcase-promethium.mp4) · [GIF](docs/showcase-promethium.gif) |

The compact ship in the first three clips makes its steel from collected asteroid
chunks and casts its own shells; radars and explosives are carried as cargo.
[Capture notes](docs/capture-notes.md) describe the setups and staged inputs.

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
