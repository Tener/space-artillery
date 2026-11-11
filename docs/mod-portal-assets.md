# Portal description assets

The source description in [mod-portal.md](mod-portal.md) uses reference-style
Markdown with relative paths to the assets in this repository.

GitHub Actions produces a separate `space-artillery-mod-portal-description`
artifact containing `mod-portal.md`. Tag builds also attach `mod-portal.md`
directly to the GitHub release for a plain-file download. Image URLs use the
release tag on tag builds and the checked-out commit on branch builds. Copy the
generated Markdown into the mod portal description.

Generate the same file locally by supplying a tag or commit:

```sh
python3 tools/prepare-portal-description.py v0.1.1
```

The output is `dist/mod-portal.md`. Commit replacement captures alongside the
description so each build references its own assets.

| Markdown reference | File |
| --- | --- |
| `shell-follow` | [Shell follow](previews/shell-follow.webp) |
| `sector-control` | [Sector control](previews/sector-control.webp) |
| `compact-production` | [Compact production](previews/compact-production.webp) |
| `asteroid-factory` | [Asteroid factory](previews/asteroid-factory.webp) |
| `battery-combat` | [Battery combat](previews/battery-combat.webp) |
| `promethium-impact` | [Promethium impact](previews/promethium-impact.webp) |
| `ship-overview` | [Ship overview](previews/ship-overview.webp) |
| `computer-interface` | [Computer interface](showcase-computer-gui.png) |

The seven animated WebP previews total about 4 MB. The original GIFs and full
recordings are also stored in `docs/`. [Capture notes](capture-notes.md) describe
the setups and encoding.
