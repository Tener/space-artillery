# Showcase demos

Run `make visuals` on macOS with Factorio 2.1.24+, FFmpeg and Python 3 installed.
`tools/capture-visuals.sh --encode-only` reuses captured frames. MP4s contain the full
sequences at 1280x720 and 20 fps. GIF previews are 800x450 at 10 fps: four seconds
from each production chapter, and the first eight seconds of the other clips.

| Demo | Visual sequence | Required evidence |
| --- | --- | --- |
| Production, 36 s | Collection and crushing; component manufacture; shell casting and loading. Three fixed views follow the material flow. | Every production stage has crafted from collected chunks; shells are made and loaded during filming. |
| Combat, 20 s | A flying artillery platform intercepts a sustained incoming asteroid stream. | At least twelve artillery kills occur within the clip. |
| Promethium, 20 s | Manufactured promethium shells break huge promethium asteroids amid continuing traffic. | Three huge targets are intercepted during filming; labels show health and destruction. |
| Overview, 15 s | The whole ship, solar wings and working thrusters remain visible while collection, casting and defense continue. | Positive flight speed, ongoing production and ammunition delivery. |

Four filtered collectors feed separate metallic, carbonic, oxide and promethium
belts. Advanced crushing supplies iron ore, copper ore, carbon, sulfur, ice and
calcite. Returned chunks recirculate through their crushers. Copper cable,
electronic circuits, gears, radar, coal and explosives are manufactured onboard.
Iron melting supplies flash-hardened steel; separate foundries cast steel and
promethium shells. Every ingredient has its own filtered inserters and turbo
belt. Underground crossings preserve ingredient separation.

Ice melting, carbon and iron ore supply the thruster fuel and oxidizer plants.
Legendary solar wings supply power; lasers provide close defense. The shell and
propulsion chains receive no scripted items or fluids. Physical resource fields and combat waves are staged for
repeatable filming; collectors must catch the chunks. Showcase entities are
indestructible.

Combat uses +300% artillery damage, 4x firing speed, rotation research VI and
shell velocity research IV. Captions state the modifiers. The promethium profile
targets big and huge asteroids; legendary lasers handle smaller traffic, with
+300% laser damage and 4x firing speed. Finished shells enter a shared magazine
in the hub. Each ammunition type has separate, circuit-limited feed belts; green-wire conditions limit each cannon to
five loaded shells so all four receive ammunition. Loaders switch between clips.
The ship travels on the Vulcanus–Nauvis connection throughout filming.

The scenario warms up at accelerated speed, manufacturing ammunition for the
hub magazine before departure. Combat draws on that reserve while production
continues during filming. Run its full production and combat checks without
rendering:

```sh
./tools/factorio-test.sh mods awesome-artillery/showcase verify 55000
```

Frames and `manifest.json` remain under
`.factorio-test/play/script-output/showcase/`. The manifest records shot
boundaries, frame counts, firing ticks and asteroid kills. Encoding fails on
missing frames or unresolved engagements. Dimensions, frame counts and durations
are checked before replacing clips in `docs/`. Review collection, transfers,
firing, destruction and the beginning and end of each clip before committing.
