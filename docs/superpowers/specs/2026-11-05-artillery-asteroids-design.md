# Awesome Artillery — Design

Date: 2026-11-05, updated 2026-11-06 · Target: Factorio 2.1.24+ with Space Age ·
Status: built (0.1.0, asteroid defense); more artillery features to come

## Intent

Make the vanilla artillery turret useful for space-platform defense. In vanilla you can
already *place* an artillery turret on a platform, but it never fires at asteroids. Even
if it did, its slow shells would land where the asteroid *was*.

The niche is **long-range area defense against medium and big asteroids**, and
against huge ones once enough damage research is done. That frees up
rocket and railgun capacity and gives artillery shells a late-game use. It should feel
like vanilla artillery: same turret, same shells, same ammo logistics, just aimed for you.

Where you put artillery on the ship matters, because vanilla decides which turret fires.
That is deliberate: placing turrets well is part of designing the ship.

## Goals

1. Artillery turrets on space platforms automatically engage asteroids in range.
2. Shots **lead the target**, aiming where the asteroid will be when the shell lands.
3. Shells **never land where the splash would hit the platform**.
4. Several turrets **don't overkill** one asteroid while others get through.
5. Vanilla controls still apply: the circuit enable/disable and the turret's
   auto-targeting toggle switch the behaviour off per turret.
6. Cheap enough to run on many platforms at once.

## Non-goals

- New turrets or visible graphics for asteroid defense. The one new building is the
  targeting computer (a tinted radar). Later features are planned under the Awesome
  Artillery name: new shell types (e.g. a kinetic "penetrator" for huge asteroids) and
  flares to target demolishers.
- Allowing artillery wagons on platforms. They are gravity-gated in vanilla and stay so.
- Rebalancing asteroids.

## Anti-goals (failure even if it "works")

- Artillery blowing up its own platform.
- Noticeable UPS cost on a save with many platforms.
- Breaking saves when the mod is removed. The game deletes the decoys on removal, and
  the artillery speed changes simply revert to vanilla, leaving ordinary idle
  turrets.

## Facts this design rests on

From the 2.1.24 data files:

| Thing | Value |
|---|---|
| Artillery range / min range | 224 / 32 tiles |
| Cooldown | 200 ticks |
| Shell | `starting_speed = 1` tile/tick |
| Impact | radius 4: 1000 physical + 1000 explosion, hits all forces |
| Turret rotation | 0.001 orientation/tick (a half-turn ≈ 500 ticks) |
| Asteroid HP small/medium/big/huge | 100 / 400 / 2000 / 5000 (promethium ×2) |
| Explosion resist % | 50 / 30 / 10 / **99** |
| Physical flat decrease | 0 / 0 / 2000 / 3000 |

### Verified live

Each row below was observed in headless 2.1.24 runs (`--test-scenario`) on
2026-11-05, using a throwaway spike mod.

| Question | Observed |
|---|---|
| Does vanilla auto-targeting shoot asteroids? | **No.** A medium asteroid stayed in range for 900 ticks and the turret never turned. Asteroids belong to the `enemy` force. |
| Can a prototype flag make it? | **No.** With `is_military_target = true` on every asteroid prototype and entity (both read back true), the turret still never fired. |
| Does splash damage asteroids? | **Yes.** Big: 900 per shell. Two mediums 2–3 tiles away died to the same shell. Huge: 10 per shell. |
| Flight time | ≈ **distance in ticks** (95 tiles → 96 ticks, 117 → 118, 41 → 38). |
| Does aiming at the current position hit a 0.1 tiles/tick asteroid? | **No.** It missed by about 20 tiles. |
| Splash near the hull | A shell 2 tiles off the edge **killed 3 solar panels**. Foundation tiles survived. |
| Min range | A target 18 tiles away was never fired at. |
| `artillery-flare` | Works on platforms: one flare gives one shell, but **vanilla picks the turret**. |
| `shooting_target` on artillery | Errors: "Entity is not turret". |
| Hidden spawner decoy, auto-targeting on | Artillery fires at it. The shells don't damage it, because it has no collision. |
| Decoy vs other turrets | A rocket turret shot it. With `aa-decoy` added to every other turret's `ignore_target_mask`, the gun and rocket turrets used 0 ammo on it and artillery was unaffected. |
| Health-matched decoy, 3 turrets, 1 big asteroid | **Exactly 3 shells** (one per turret). The asteroid died and its decoy was removed. |
| Health-matched decoys, 3 turrets, 2 crossing mediums, flight-time lead | **2 shells, 2 kills.** The third turret stayed idle. |
| Drift around a stationary platform | ≈ 0.02 tiles/tick toward +y. An asteroid spawned 100 tiles *behind* (+y) the platform was removed by the game on tick 0. |

### Other turret types vs decoys (verified)

Laser, tesla, railgun, gun and rocket turrets were powered and loaded with a decoy 14
tiles in front of each. With the `ignore_target_mask` fix they targeted nothing for
600 ticks, and the decoys stayed at full health. When real medium asteroids then
spawned, every turret engaged them and they all died.

### Travelling platform (verified)

Setup: Nauvis → Vulcanus with 3 artillery turrets, the full decoy controller, natural
asteroid spawns and 5400 ticks per run. Laser turrets covered small asteroids. The
artillery, thrusters and hub were made indestructible so the run survives to the end.
For forced speeds, the platform was looped back along the route so it never arrived.

| Platform speed | Asteroid speed relative to the platform (tiles/tick) | Shells | Artillery kills (medium + small) | Kills per shell | Mediums that reached the hull |
|---|---|---|---|---|---|
| ~2.0–2.7 (thrusters, natural) | 0.07–0.08 | 41 | 43 + 5 | 1.2 | 13 |
| 5 (forced) | 0.11 | 60 | 64 + 3 | 1.1 | 33 |
| 10 (forced) | 0.14 | 75 | 98 + 0 | 1.3 | 127 |
| 20 (forced) | 0.17 | 78 | 141 + 3 | 1.8 | 228 |

Conclusions:

- **The flight-time-only lead holds at every speed tested.** Kills per shell stay above
  1, and rise with speed because denser asteroid fields give more blast-radius kills.
- **Asteroid speed relative to the platform grows slowly with platform speed**
  (0.07 → 0.17 tiles/tick for a 10× speed increase).
- **Fire rate is the limit, not the aim.** At speed 10 and up, 3 turrets fire about
  as fast as they can (81 shells is the maximum in 5400 ticks) and many mediums still
  get through. How many turrets to fit, and artillery shooting-speed research, are
  ship-design and balance questions, not mod bugs.
- **Hazards for the controller**, each of which crashed the spike: artillery turrets
  get destroyed mid-trip, every turret on a platform can be destroyed, and the
  platform itself can be destroyed when its hub dies. The controller must check that
  turrets and platforms are still valid, and skip a platform with no turrets left.

### Artillery research (verified)

Technologies, read at runtime through the Lua API (all three are infinite):

| Technology | Effect per level |
|---|---|
| `artillery-shell-damage-N` | `ammo-damage[artillery-shell]` +0.1 |
| `artillery-shell-speed-N` | `gun-speed[artillery-shell]` +1 (+100% fire rate) |
| `artillery-shell-range-N` | `artillery-range` +0.3 |

Tested by setting the force modifiers directly.

**Damage vs overkill.** With 3 turrets and 3 big asteroids:

| Damage bonus | Shells per big asteroid |
|---|---|
| 0 | exactly 3 |
| +150% | exactly 1 |

Vanilla's predicted-damage check includes the damage bonus, so health-matched decoys
still prevent overkill after research.

**Damage vs huge asteroids.** 3 turrets, 3 huge asteroids, 1500 ticks:

| Damage bonus (levels) | Damage per shell | Result |
|---|---|---|
| 0 | ~10 | 21 shells wasted, 210 HP removed in total |
| +300% (30) | ~940 | all 3 killed, about 6 shells each |
| +500% (50) | ~2760 | all 3 killed at 2 shells each, plus their 8 big and 3 medium fragments, in 18 shells |

The 3000 flat physical reduction only gives way once shell physical damage exceeds
3000, which needs a bonus above +200%. **With enough research, huge asteroids are
viable artillery targets.**

**Fire rate.** Platform speed 10, 5400 ticks:

| Fire-rate bonus | Shells | Artillery kills (medium + small) | Mediums that reached the hull |
|---|---|---|---|
| 0 | 75 | 98 + 0 | 127 |
| +100% | 112 | 153 + 5 | 114 |
| +300% | 156 | 213 + 31 | 109 |

Kills scale with shells fired, so the lead stays accurate. The number reaching the hull
levels off at about 110. At +300% the turrets are no longer limited by fire rate (the
maximum would be 324 shells). The likely causes are asteroids that appear inside the
32-tile minimum range or the hull safety zone, and the turret's slow turning, which
fire-rate research doesn't affect. Artillery is long-range defense; ships still need
close-in turrets.

### Faster turret rotation and shells (verified)

Prototype changes: `artillery-turret.turret_rotation_speed` 0.001 → 0.005 (5×), and
the `artillery-shell` ammo's artillery delivery `starting_speed` 1 → 3 (3×).

- A half-turn shot fired at tick 132 instead of 532.
- Flight time was 34 ticks for ~100 tiles, so flight time is now distance ÷ shell
  speed.

Platform speed 10, +300% fire rate, 5400 ticks:

| | Shells | Artillery kills (medium + small) | Mediums that reached the hull |
|---|---|---|---|
| Vanilla rotation and shell speed | 156 | 213 + 31 | 109 |
| 5× rotation, 3× shell speed | 290 | 408 + 42 | 90 |

Less time turning nearly doubles the shots fired, and accuracy holds with the shorter
lead. Most of the remaining leaks are probably asteroids inside the 32-tile minimum
range or the hull safety zone (not separately tested). Lowering `min_range` on the
artillery gun is a possible further setting.

These changes apply to all artillery, ground included; the user is fine with that.

**Range** was not tested. The controller's "can any turret reach this point" check
must use `force.artillery_range_modifier` and not a hard-coded 224.

### Playtest findings (user, in the game client)

- "Very fun." The decoy design works in real play.
- **Decoy health bars were visible**, and moved as the decoy was teleported to new lead
  points. The cause: the engine draws a health bar for any damaged entity, and decoys
  copy the asteroid's current health. **Fixed** with the `not-selectable-in-game`
  entity flag and no `selection_box`. Verified by screenshot: a half-health decoy
  shows no bar, and a half-health solar panel next to it does.
- **The fire rate felt too low** for dense fields. Added a startup setting, the
  artillery fire-rate multiplier (default 2×), which divides the cooldown of every
  artillery-shell gun. Headless at natural speed over 90 s: 84 shells and 97 medium
  kills, with 8 decoys waiting at the end (it was 66 shells, 75 kills and 25 waiting
  at 1×).
- **Ships need a close-in layer.** Medium asteroids that get inside artillery's
  minimum range or the hull safety zone can't be shot by artillery, and lasers barely
  hurt them (90% laser resistance). The playtest ship lost its bow until gun turrets
  were added. This is for the player's ship design, and worth a tip in the mod
  description.

### Performance (profiled headless, `perf` cases)

**Target:** platform speed up to 10 (~600 km/s), which is the stress case. Higher speeds
need heavily modded ships. Spikes are to be avoided at any speed.

How the cost came down (speed 10, ~190 asteroids, the update then ran every 10 ticks):

| | Per update | Per asteroid |
|---|---|---|
| First version | 5.37 ms | 29 µs |
| + positions, settings and hull outline read once per update | 2.58 ms | 12 µs |
| + closed-form aim from the turrets' centre | 1.88 ms | 8.6 µs |

- The biggest single cost was the iterative per-turret lead (3.4 µs per asteroid).
- Measured: vanilla picks the **nearest** turret only 41% of the time, so per-turret
  leading bought nothing. Misses from the firing turret not being at the centre are left
  to shell-speed research (user's call).
- Measured: asteroid velocity is constant while platform speed is constant. On a
  platform speed change, all asteroids shift by the same amount.
- Single API calls cost 0.2–0.7 µs (`teleport` 0.5–1.4 µs). `LuaModData.data` copies the
  whole table on every access, so it is cached. `count_tiles_filtered` costs ~2 µs; the
  cached hull outline avoids 94% of those calls.
- Allocation is a minor factor (~0.1 µs per extra small table, GC included).

**Update interval.** Without correction, the aim held up to an interval of 60 ticks at
natural speed and 30 at speed 10. Aiming for the middle of the interval (advancing the
asteroid by `v · interval / 2`) roughly doubles the tolerable interval. The default is
now **30 ticks**.

**Spreading the work over the interval.** With everything done in one tick, the update
spiked at interval 30: ~2.9 ms at speed 10, 13 ms at speed 50, 50 ms at speed 200. Now
each asteroid is updated on its own tick of the interval. Same total work, measured on
the same case:

| Speed | Before (one tick in 30) | Now (every tick) | Asteroids per tick, max |
|---|---|---|---|
| 10 | 2.9 ms | 0.13 ms avg | 14 |
| 50 | ~13 ms | 0.48 ms avg | 29 |

The remaining spike is each platform's scan tick (finding and registering asteroids):
~0.5 ms at speed 10, ~0.9 ms at speed 50. Profiling is now minimal: one timer per tick
plus counts, because `LuaProfiler` values can't be compared in Lua, so the worst tick
is reported as a count of asteroids. Factorio's own tools (F4 time usage,
`--benchmark-verbose`) were judged not granular enough.

Open performance work (on hold, TODO in `control.lua`):
- Split the scan tick, e.g. one slice of the reach per tick.
- Skip asteroids that can never get a decoy before doing any work: a name prefilter
  (size, computer types, shell limit) and scanning only the computers' zones. This
  matters when computers restrict targeting.
- Update asteroids without a decoy less often.

### Not yet verified (needs a real game)

- Decoys don't show on the map (`not-on-map` flag) and raise no alerts.
- Blueprint **setup** (the computer's settings saved into a blueprint, including a
  library blueprint) and copy-paste of settings. Building from a tagged ghost is tested.
- Save and load mid-flight, and multiplayer (no desyncs expected: all state is in
  `storage`, and the only module-level state is the profiler and a prototype cache).

## How it works

### Firing: health-matched decoys

Each eligible asteroid gets one hidden **decoy** on the `enemy` force, which vanilla
artillery auto-targets. The script keeps each decoy at the asteroid's **lead point**
with **the same health as the asteroid**, and destroys it when the asteroid is gone.

Everything else is left to vanilla, and all of it was verified live:

- **Which turret fires.** Accepted on purpose, as part of designing the ship.
- **Overkill avoidance.** The decoy has the asteroid's max health and resistances, so
  vanilla's predicted-damage check stops after the right number of shells.
- **Spreading targets** across turrets.
- **Turret controls, ammo, quality and research bonuses**, with no extra code.

The shell damages whatever is within 4 tiles of where it lands; the decoy itself never
takes damage. So only the asteroid's real health matters, and it is copied to the decoy
whenever it changes.

Rejected alternatives:

- **Flares** give one shell each, but vanilla still picks the turret, and the mod would
  have to reimplement overkill avoidance.
- **`shooting_target`** doesn't work on artillery.
- **Prototype flags on asteroids** don't make vanilla target them.
- **An `ammo-turret` "space artillery"** also worked in a spike (vanilla shell, built-in
  target leading, honours target masks), but would be a new turret. Kept in reserve.

### Prototypes (`data-final-fixes.lua`)

- A `trigger-target-type` named `aa-decoy`.
- For each `asteroid` prototype with `max_health`, a decoy `aa-decoy-<asteroid name>`:
  a `unit-spawner` copied from `biter-spawner`, with the asteroid's `max_health` and
  `resistances`, `trigger_target_mask = {"aa-decoy"}`, no collision, no spawning, loot,
  corpse or sounds, blank graphics, and the flags `not-on-map` and
  `not-selectable-in-game` with no `selection_box` (this hides the health bar, verified).
- Every non-artillery turret (`ammo-turret`, `electric-turret`, `fluid-turret`,
  `turret`) gets `aa-decoy` in its `ignore_target_mask`, modded turrets included.
- The targeting computer (entity, item, recipe, technology; see below).
- A `mod-data` catalogue `aa-asteroids`: asteroid name → chunk type and size rank,
  found by walking each asteroid's `dying_trigger_effect` chain (works for modded
  asteroids).
- The artillery speed changes (startup settings).

Asteroid prototypes are not changed.

### Control loop (`control.lua`)

Each tracked asteroid has a **slot**, its registration number modulo the update
interval, and is updated only on the tick of its slot. Each platform **scans** once per
interval, on a tick offset by its surface index:

1. Skip the platform if it is gone or has no valid artillery turrets. Turrets are
   tracked with build events plus a rescan in `on_init`/`on_configuration_changed`, and
   checked for `valid` before every use.
2. Build the platform's context: turret centre and spread, reach band, settings, hull
   outline, targeting computer rules. It is kept in `storage` and shared by that
   platform's slot updates until the next scan.
3. Find asteroids within reach, register each with `register_on_object_destroyed`, and
   start tracking new ones. The scan does nothing else.

On a slot tick, each asteroid in the slot is either dropped (the last scan didn't see
it, its platform has no context, or it is gone) or updated: velocity from the last
sample, eligibility, lead point, reach, hull safety, computer rules. Then the decoy is
created, teleported (only when the aim moved ≥ 0.5 tiles) or destroyed. A destroyed
asteroid's decoy is removed through `on_object_destroyed`.

### Target eligibility

- Asteroid size ≥ the minimum-size setting (default small; computers narrow it further).
- **Expected shells to kill ≤ setting** (default 8): current health ÷ one shell's
  damage against that asteroid, from the vanilla shell damage (physical 1000 +
  explosion 1000), the force's `artillery-shell` damage modifier and the asteroid's
  resistances (flat decrease first, then percentage). Recomputed per force when research
  finishes or is reversed.
  - With no research, huge asteroids take ~10 per shell, so they get no decoy.
  - At about +300% damage they need ~6 shells, so they qualify.
- Which eligible asteroid gets shot first is up to vanilla.

### Lead calculation

The turret tracks the decoy while it turns, and the shell lands where the decoy was at
the moment of firing. So the lead only needs the shell's flight time. In closed form,
from the turrets' centre: solve |r + v·t| = s·t for the flight time t, where r is the
asteroid's offset from the centre, v its velocity and s the shell speed (read at
runtime from the `artillery-shell` ammo). Before solving, the asteroid is advanced by
`v · interval / 2`, because the shot can come at any point until the next update.

The aim point must be reachable: its distance from the centre must lie within
[min range − spread, range + spread], with range including
`force.artillery_range_modifier`.

### Platform safety

Reject an aim point if any `space-platform-foundation` tile lies within impact radius 4
+ margin (setting, default 4). A per-chunk outline of the hull, rebuilt on tile events
and every 10 s, answers most points; points near the outline get an exact
`count_tiles_filtered`.

### Targeting computer (`scripts/computer.lua`)

A radar copy (100 kW, no scanning, `connects_to_other_radars = false` so it has its own
circuit network, space only). It decides which asteroids get decoys on its platform:

- **Sizes** (checkboxes), **types** (8 asteroid-chunk slots; empty = all) and a
  **sector zone**: direction, arc, near and far distance. Far goes up to 500 tiles and
  grows with artillery range research.
- **Circuit inputs**, roboport-style: each has an enable checkbox and a selectable
  signal. Direction, arc, near and far (defaults D, A, N, F), a minimum size ("this size
  and up", S) and a switch-off signal (default ⛔).
- The zone is drawn on the surface while the computer's window is open.
- With several computers, an asteroid is allowed if any working computer allows it.
  With **require computer** on (default), a platform without a working computer fires
  at nothing.
- Settings survive blueprints (tag `aa_cfg`, library blueprints included), ghosts and
  copy-paste.

**Unlock:** technology "Artillery targeting computer", requiring Artillery and the
Fulgora and Vulcanus science packs; 1000 units of automation, logistic, military,
chemical, utility, space, metallurgic and electromagnetic science, 60 s each.
**Recipe** (30 s, any assembler): 50 processing units and 5 radars, both rare or better
(`quality_min`), plus 20 superconductors, 20 tungsten plates and 10 low density
structures.

### Settings

Startup (prototypes; all artillery, ground included):

| Setting | Default |
|---|---|
| Artillery turret rotation speed multiplier | 5 |
| Artillery shell speed multiplier | 3 |
| Artillery fire rate multiplier | 2 |

Runtime-global:

| Setting | Default |
|---|---|
| Update interval (ticks) | 30 |
| Smallest asteroid to target | small |
| Most shells to spend on one asteroid | 8 |
| Hull safety margin (tiles) | 4 |
| Artillery needs a targeting computer | on |

### Mod layout

```
mods/mod-list.json             mods enabled for the test runner
mods/awesome-artillery/
  info.json, changelog.txt, thumbnail.png (placeholder from a screenshot)
  settings.lua
  data-final-fixes.lua         decoys, turret ignore masks, computer, catalogue, speeds
  control.lua                  decoy controller, events, remote interface
  scripts/computer.lua         targeting computer: rules, GUI, zones, blueprints
  locale/en/locale.cfg
  scenarios/playtest/          playtest ship + headless test cases (not shipped)
  scenarios/thumbnail/         screenshots for the thumbnail (not shipped)
  scenarios/bars/              health bar screenshot check (not shipped)
tools/factorio-test.sh         headless runner, client and play launcher
tools/package.sh               builds dist/awesome-artillery_<version>.zip
.github/workflows/build.yml    zip on pushes to main, GitHub release on v* tags
```

The remote interface `awesome-artillery` (decoy counts, computer config, profiling,
setting changes) ships with the mod: scenarios and other mods can use it.

## Testing (deliberately light)

**Runner:** `tools/factorio-test.sh MODS_DIR MOD/SCENARIO [TEST_ARG] [TICKS]` runs one
headless `--test-scenario` with an isolated write dir, so the user's saves, mods and
settings are untouched. `--client` and `--play` start the game client on a scenario
(screenshots only work there).

**Playtest scenario cases** (`--test-arg "<case> [ticks]"`, default 3600 ticks):

| Case | Checks |
|---|---|
| `check` | general invariants while the ship flies |
| `tc-none`, `tc-unpowered` | no decoys or shells without a working computer |
| `tc-zone` | decoys only for medium asteroids in the north 90° sector |
| `tc-signals`, `tc-pick`, `tc-ignore` | minimum size from a wire, from a chosen signal, and an unticked input is ignored |
| `tc-chunk` | type slots (metallic only) |
| `tc-wires` | two computers on separate wires |
| `tc-blueprint` | a computer built from a tagged ghost gets the settings |
| `tech` | the recipe is locked at start; prerequisites and ingredient quality |
| `perf`, `perf-idle`, `-sN` (speed), `-iN` (interval) | profiling |
| `perf-vel`, `perf-who` | velocity after speed changes; which turret fires |

Cases that wait for a kind of asteroid need 60 s: in 30 s some runs see no medium or
metallic asteroid at all. Each case fails itself at its deadline, so the built-in
"timeout counts as a pass" never hides a failure.

No CI tests: GitHub Actions only builds the zip.

## Calls made without the user

- Reuse the vanilla turret and shell.
- Default multipliers 5× rotation and 3× shell speed (tested values, not tuned), 2× fire
  rate (after the playtest).
- Asteroids that need more than 8 shells get no decoy (setting).
- Safety checks foundation tiles only, since platform buildings stand on foundation.
- The exact research cost (1000 units), Artillery as a prerequisite, the recipe amounts
  and the extra ingredients (superconductor, tungsten plate, low density structure).
- The remote interface ships with the mod.
- The thumbnail is a placeholder from an in-game screenshot.

## Decided with the user

- Decoy-based firing, with the decoy's health tied to the asteroid's and the decoy
  destroyed with it (the user's idea).
- Vanilla picks which turret fires; turret placement is part of the ship design.
- Light testing only, using the built-in 2.1.24 test flags; live checks, not
  assumptions.
- Faster rotation, shells and fire rate change ground artillery too.
- Huge asteroids become targets once research makes them worth shooting.
- The targeting computer and its features (sizes, types, zone, roboport-style circuit
  inputs, switch-off signal, zone drawing).
- Target platform speed ≤ 10; avoid spikes; keep it simple with TODOs for later.
- Name: Awesome Artillery, with more artillery features to come (new shells, flares
  for demolishers).
- Computer unlock needs Fulgora and Vulcanus research; costly recipe with rare
  processing units and rare radars; any assembler (the research already gates it).
- GitHub Actions: zip on main, release on tags; no automatic uploads, no CI tests,
  hardened workflow.
