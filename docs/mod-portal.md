# Space Artillery

<!-- Before publishing, replace the image URL placeholders using docs/mod-portal-assets.md. -->

**Automated artillery defense against asteroids.** Requires **Factorio 2.1 + Space Age**.

Place artillery on a space platform and use a powered targeting computer to select
its targets. Cannons lead moving asteroids, coordinate fire using expected damage,
and hold shots whose predicted blasts would reach platform foundation.

Cast steel and promethium artillery shells onboard, then research faster turret
rotation and shell flight.

![A shell launches from its cannon, flies toward an asteroid and intercepts it][shell-follow]

The shell-follow recording slows flight to one third of real time.

## Getting started

1. Research **Artillery targeting computer** after artillery, electromagnetic
   science and metallurgic science.
2. Craft a computer using rare processing units and radars, superconductors,
   tungsten plates and low-density structures.
3. Place it on a platform with artillery turrets, supply **5 MW**, and choose the
   asteroid sizes, types and firing sector.

## Targeting computer

- Filter by asteroid size and chunk type, including modded asteroid chunks.
- Set direction, arc width, and near and far range. The firing sector is
  highlighted while the computer window is open.
- Enable **Show targets** to see the platform's artillery aim points as red
  circles, connected to their asteroids by orange lines. These markers are
  visible to you while the window is open.
- Drive filters and sector settings through red or green circuit signals, or
  switch the computer off with a selected signal.
- Configure ghosts before construction, copy settings between computers, and
  carry settings in blueprints.

Any working computer on the platform can permit a target.

![The firing sector narrows and turns while artillery intercepts incoming asteroids][sector-control]

[View the computer interface][computer-interface].

## Make ammunition in space

Cast **flash-hardened steel** in a foundry from molten iron, carbon, calcite and
ice. Use it with explosives and radars to make **steel artillery shells**.
**Promethium artillery shells** also require a promethium asteroid chunk.

| Shell | Physical damage | Explosion damage |
| --- | ---: | ---: |
| Vanilla artillery shell | 1,000 | 1,000 |
| Steel artillery shell | 200 | 800 |
| Promethium artillery shell | 4,000 | 1,000 |

Damage values are before research and asteroid resistance. Promethium shells
pierce huge asteroids' 3,000 flat physical resistance at base damage research.

- Destroy **500 medium or larger standard asteroids with artillery** to complete
  **Asteroid ballistics field data**. Kills in planet orbit count. Progress appears
  in the research interface, and completion unlocks **Steel artillery shell**
  research, costing **2,000 of each required science pack**.
- Destroy a **medium or larger promethium asteroid** to complete
  **Promethium ballistics field data** and unlock **Promethium artillery shell**
  research, costing **4,000 of each required science pack**.

![Collectors, crushers, foundry casting and cannon loading on a compact ship][compact-production]

The compact ship makes its steel from collected chunks and carries radars and
explosives as cargo.

![Collected asteroid chunks pass through crushing, component manufacture and shell casting][asteroid-factory]

The larger factory makes its shell components and propellant onboard, with
separate belts for production inputs.

## Research upgrades

- **Artillery turret rotation speed** adds **30% per level** across ten levels,
  reaching four times the original turning speed.
- **Artillery shell velocity** adds **20% flight speed per level**, with infinite
  research.
- Vanilla artillery damage and shooting speed research apply.

![A flying artillery battery engages incoming asteroids][battery-combat]

![A promethium shell breaks up a huge asteroid][promethium-impact]

The larger combat showcases use +300% artillery damage, four times the base firing
speed, rotation research VI and shell velocity research IV. Resource fields and
combat waves are staged, and the showcase ships are indestructible. Production
uses collected chunks.

![Thrusters, production and artillery before a full view of the ship in flight][ship-overview]

## Settings and current limitations

Map settings control the targeting update interval, smallest asteroid size,
maximum shells per target, hull safety margin, and whether artillery requires a
working targeting computer.

Widely separated cannons can miss moving asteroids because they share a lead
calculation based on the battery's average position. Shell velocity research
reduces this error.

[Questions and bug reports][discussion]

[shell-follow]: REPLACE_SHELL_FOLLOW_URL
[sector-control]: REPLACE_SECTOR_CONTROL_URL
[compact-production]: REPLACE_COMPACT_PRODUCTION_URL
[asteroid-factory]: REPLACE_ASTEROID_FACTORY_URL
[battery-combat]: REPLACE_BATTERY_COMBAT_URL
[promethium-impact]: REPLACE_PROMETHIUM_IMPACT_URL
[ship-overview]: REPLACE_SHIP_OVERVIEW_URL
[computer-interface]: REPLACE_COMPUTER_INTERFACE_URL
[discussion]: https://mods.factorio.com/mod/space-artillery/discussion
