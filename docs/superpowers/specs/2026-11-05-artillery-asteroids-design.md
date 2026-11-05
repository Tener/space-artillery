# Artillery Asteroids — Design

Date: 2026-11-05 · Target: Factorio 2.1.24+ with Space Age · Status: draft for approval

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

- New turrets, shells, recipes, technologies or visible graphics. A possible v2 is a
  kinetic "penetrator" shell for huge asteroids.
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

### Performance (profiled headless, platform speed 10, ~190 asteroids / ~175 decoys)

Measured with `LuaProfiler` in the playtest build (`perf` cases):

| | Per update (every 10 ticks) | Per asteroid |
|---|---|---|
| First version | 5.37 ms | 29 µs |
| + positions, settings and hull outline read once per update | 2.58 ms | 12 µs |
| + closed-form aim from the turrets' centre | 1.88 ms | 8.6 µs |

- The biggest single cost was the iterative per-turret lead (3.4 µs per asteroid). The
  replacement solves |r + v·t| = shell_speed·t once, from the turrets' centre.
- Measured: vanilla picks the **nearest** turret only 41% of the time, so per-turret
  leading bought nothing. Misses from the firing turret not being at the centre are left
  to shell-speed research (user's call).
- Measured: asteroid velocity is constant while platform speed is constant. On a
  platform speed change, all asteroids shift by the same amount.
- Single API calls cost 0.2–0.7 µs (`position` 0.36 µs, `teleport` 0.5–1.4 µs),
  `LuaModData.data` copies the whole table on every access (cache it), and
  `count_tiles_filtered` costs ~2 µs. A cached hull outline now avoids 94% of those calls.
- Allocation: ~116 KB per update. An extra small table costs ~0.1 µs including GC, so
  allocation is a minor factor.
- Accuracy after the simplification: 2.0 kills per shell at natural speed (unchanged),
  2.4 at speed 10.

Open performance work (on hold):
- Spread updates across ticks: same total, no 2 ms spike every 10th tick.
- Per-asteroid update interval from aim drift (speed × interval vs ~1 tile), with
  asteroids that have no decoy updated less often.
- Skip asteroids that can never get a decoy before doing any work: a name prefilter
  (size, computer types, shell limit), and scanning only the computers' zones instead of
  the full circle. This matters when computers restrict targeting: in the zone test,
  almost all processed asteroids got no decoy.

### Not yet verified

- **Decoy invisibility**: blank sprites, no map icon, no alerts, no kill statistics.
  The spike used the visible biter-spawner sprite.

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
takes damage. So only the asteroid's real health matters, and it is copied to the
decoy on every update.

Rejected alternatives:

- **Flares** give one shell each, but vanilla still picks the turret, and the mod would
  have to reimplement overkill avoidance.
- **`shooting_target`** doesn't work on artillery.
- **Prototype flags on asteroids** don't make vanilla target them.

### Prototypes (`data-final-fixes.lua`)

- A new `trigger-target-type` named `aa-decoy`.
- For each `asteroid` prototype with `max_health`, a decoy `aa-decoy-<asteroid name>`.
  It is a `unit-spawner` copied from `biter-spawner`, with:
  - `max_health` and `resistances` copied from the asteroid;
  - `trigger_target_mask = {"aa-decoy"}`;
  - `hidden = true` and `collision_mask = {layers = {}}`;
  - no spawning (`max_count_of_owned_units = 0`, `max_friends_around_to_spawn = 0`,
    huge `spawning_cooldown`);
  - no loot, corpse, minable, autoplace or dying explosion;
  - invisible and silent: blank graphics, the `not-selectable-in-game` flag and no
    `selection_box` (this is what hides the health bar, verified), not on the map, no
    alerts.
- **Every non-artillery turret** of types `ammo-turret`, `electric-turret`,
  `fluid-turret` and `turret` gets `aa-decoy` appended to `ignore_target_mask`. This
  runs in `data-final-fixes` so turrets from other mods are covered too.

Asteroid prototypes are not changed.

### Control loop

For each platform surface, every **N ticks** (setting, default 10), staggered across
platforms:

1. Skip the platform if it is no longer valid or has no valid artillery turrets.
   Track turrets with build and destroy events (asteroid hits destroy them mid-trip),
   plus a full rescan in `on_init` and `on_configuration_changed`. Keep the registry
   in `storage`, and check `valid` before every use.
2. Find asteroids within the turrets' range plus a margin.
3. Start tracking each new eligible asteroid and record its position. It gets no decoy
   until a second sample gives it a velocity, since asteroids don't expose one.
4. For each tracked asteroid:
   - If it is no longer valid, destroy its decoy and stop tracking it.
   - Otherwise update its velocity, using the actual tick delta since the last sample.
     Compute the lead point and run the safety check.
   - If the point is safe and some turret can reach it (32–224 tiles), create the
     decoy or `teleport` it there, and set `decoy.health = asteroid.health`.
   - If the point is unsafe or out of reach, destroy the decoy. It is recreated on
     the next update once the point is fine again.

### Target eligibility

- Asteroid size ≥ setting (default **medium**).
- **Expected shells to kill ≤ setting** (default 8). This is the asteroid's current
  health divided by the expected damage of one shell against that asteroid type. One
  shell's damage comes from the shell's damage effects, the force's
  `artillery-shell` damage modifier, and the asteroid's resistances. This rule replaces
  "never huge":
  - With no research, huge asteroids take ~10 per shell (hundreds of shells), so they
    get no decoy.
  - At about +300% damage they need ~6 shells, so they qualify.
  - Big asteroids need 3 shells with no research, so they always qualify.
- Recompute the per-type damage when research finishes (`on_research_finished`, and
  `on_research_reversed`), not every update.
- Which eligible asteroid gets shot first is up to vanilla. The mod's only lever is
  which asteroids get decoys.

Damage math: Factorio applies the flat decrease first, then the percentage. When the
flat decrease is at least the damage, the result is near zero; count it as 0. Read the
shell's damage effects (physical 1000 and explosion 1000 in vanilla) from the
`artillery-projectile` prototype at data stage, and pass them to runtime, for example
through a `mod-data` prototype, so modded shells are handled too.

### Lead calculation

The turret tracks the decoy while it turns, and the shell lands where the decoy is *at
the moment of firing*. So the lead only needs the shell's flight time:

```
aim = asteroid_pos + velocity * t,   t = distance(nearest artillery turret, aim) / shell_speed
iterate ~4 times starting from t = 0
```

`shell_speed` is read at runtime from the `artillery-shell` ammo prototype's artillery
delivery `starting_speed`. It is 1 in vanilla and changed by the startup setting below.
Flight time ≈ distance ÷ shell speed, as measured at speeds 1 and 3. Using the nearest turret rather than the
one that fires adds an error of about (difference in turret distances) × velocity. That
stays inside the 4-tile blast for normal ship sizes. It was verified with natural
asteroids moving up to 0.17 tiles/tick relative to the platform (platform speed 20).

This math lives in a **pure module** (`scripts/intercept.lua`, no game API) so it can be
tested in isolation.

### Platform safety

This check is required. The spike showed that a shell 2 tiles off the hull destroys
buildings. Reject an aim point if any `space-platform-foundation` tile lies within
**impact radius 4 + margin** (setting, default 4, so 8 tiles in total). Platform
buildings can only stand on foundation, so checking tiles covers them too.

### Settings (startup)

These change prototypes, for all artillery (ground included):

| Setting | Default |
|---|---|
| Artillery turret rotation speed multiplier | 5 |
| Artillery shell speed multiplier | 3 |
| Artillery fire rate multiplier | 2 |

### Settings (runtime-global)

| Setting | Default |
|---|---|
| Update interval (ticks) | 10 |
| Minimum asteroid size to target | medium |
| Maximum expected shells per asteroid | 8 |
| Safety margin (tiles) | 4 |

### Mod layout

```
info.json                name "artillery-asteroids", factorio_version "2.1",
                         dependencies: base, space-age
data-final-fixes.lua     decoy prototypes, trigger-target-type, turret ignore masks
settings.lua
control.lua              event wiring
scripts/intercept.lua    pure lead math
scripts/tracking.lua     artillery turret registry per surface
scripts/decoys.lua       asteroid tracking, decoy create/move/destroy, safety check
locale/en/locale.cfg
changelog.txt
scenarios/aa-test/       test scenario (see Testing)
tools/factorio-test.sh   headless test runner (not shipped in the mod zip)
```

## Testing (deliberately light)

**Runner:** `tools/factorio-test.sh MODS_DIR MOD/SCENARIO [TEST_ARG] [TICKS]` already
exists. It runs one headless `--test-scenario` with an isolated config, so the user's
saves, mods and settings are untouched. It checks its arguments and prints only the
scenario's own output and errors. The full log goes to `.factorio-test/last.log`.

**One scenario** (`scenarios/aa-test`) with a few cases, chosen by `--test-arg`:

1. `intercept`: pure-math checks of the lead solver (stationary target, crossing
   target, unreachable target → nil).
2. `kill`: a platform with three artillery turrets and a medium asteroid on a known
   crossing path. Passes if one shell kills it and no platform entity takes damage.
3. `overkill`: one big asteroid. Passes if exactly 3 shells are fired.
4. `safety`: an asteroid whose lead point is within 8 tiles of the hull. Passes if no
   shell is fired.
5. `ignore`: laser, tesla, railgun, gun and rocket turrets next to decoys. Passes if
   none of them targets a decoy, and each still kills a real asteroid.

Each case calls `script.finish_test(false)` itself when its deadline passes. That way
the built-in "timeout counts as a pass" never applies.

There is no CI and no external framework.

## Build order

1. Spike: done (see "Verified live").
2. ~~Remaining live checks~~: done (see "Other turret types" and "Travelling platform").
3. Prototypes, including decoy invisibility.
4. `intercept.lua` and the `intercept` test case.
5. Turret tracking, the decoy control loop and the safety check.
6. The `kill`, `overkill`, `safety` and `ignore` test cases.
7. Settings, locale, changelog, then a manual play-test on a real platform trip.

## Left to the builder

- Exact `storage` layout, the stagger scheme, and the key used to track asteroids.
- How to make the decoy fully invisible and silent (graphics, map, alerts, stats).
- How the test scenario builds its platform. The spike used
  `force.create_space_platform` + `apply_starter_pack` plus hand-placed foundation
  tiles, which worked.

## Calls made without the user

- Reuse the vanilla turret and shell; no new items.
- Default multipliers of 5× rotation and 3× shell speed: these are the tested values,
  not tuned.
- Asteroids that need more than 8 shells get no decoy (setting). That keeps huge
  asteroids off the list until damage research makes them worth shooting (the user
  suggested making huge asteroids viable with research).
- Default minimum target size is medium. Small asteroids are cheap to kill with lasers,
  and a 100 kg shell is wasted on them.
- Safety checks foundation tiles only, since platform buildings always stand on
  foundation.
- Lead uses the nearest turret's distance, because vanilla's turret choice is unknown
  ahead of time.

## Decided with the user

- Decoy-based firing, with the decoy's health tied to the asteroid's and the decoy
  destroyed with it (the user's idea).
- Vanilla picks which turret fires; turret placement is part of the ship-design
  challenge (the user's call).
- Light testing only, using the built-in 2.1.24 test flags.
- Faster rotation and shells may change ground artillery too (the user's call).
- Huge asteroids become targets once research makes them worth shooting (the
  user's suggestion).
