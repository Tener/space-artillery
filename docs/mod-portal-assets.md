# Portal description assets

The GitHub repository is private. Its raw image URLs return 404 to anonymous
visitors. The description in [mod-portal.md](mod-portal.md) uses reference-style
Markdown with placeholders for public image URLs.

Upload the files below to the mod portal or another public image host, then
replace each placeholder in the description's reference block with the returned
image URL. Verify that each URL loads without signing in before publishing.

| Markdown reference | File | URL placeholder |
| --- | --- | --- |
| `shell-follow` | [Shell follow](previews/shell-follow.webp) | `REPLACE_SHELL_FOLLOW_URL` |
| `sector-control` | [Sector control](previews/sector-control.webp) | `REPLACE_SECTOR_CONTROL_URL` |
| `compact-production` | [Compact production](previews/compact-production.webp) | `REPLACE_COMPACT_PRODUCTION_URL` |
| `asteroid-factory` | [Asteroid factory](previews/asteroid-factory.webp) | `REPLACE_ASTEROID_FACTORY_URL` |
| `battery-combat` | [Battery combat](previews/battery-combat.webp) | `REPLACE_BATTERY_COMBAT_URL` |
| `promethium-impact` | [Promethium impact](previews/promethium-impact.webp) | `REPLACE_PROMETHIUM_IMPACT_URL` |
| `ship-overview` | [Ship overview](previews/ship-overview.webp) | `REPLACE_SHIP_OVERVIEW_URL` |
| `computer-interface` | [Computer interface](showcase-computer-gui.png) | `REPLACE_COMPUTER_INTERFACE_URL` |

The seven animated WebP previews total about 4 MB. Image-host acceptance and
animation preservation still need checking during upload. The original GIFs are
also stored in `docs/`, with their mappings recorded in
[capture notes](capture-notes.md).

The portal's [image upload API](https://wiki.factorio.com/Mod_images_API) returns
the public image URL after a successful upload.
