# Local tests

Run `make test` with Factorio 2.1.24 or later, Space Age and Python 3 installed. The runner uses
the macOS Steam installation by default; set `FACTORIO` to the executable's absolute
path for another installation. No graphics or screenshots are produced.

The suite runs 20 cases in fresh game processes and returns nonzero if any fail.
Full logs are retained per case under `tmp/test-logs/`. Game configuration, saves
and runtime output are isolated under `.factorio-test/`.

- `tech`: recipes, research prerequisites and kill triggers, rotation upgrades and
  preserved ammunition, simulation initialization, bearings and a working GUI checkbox.
- `tc-none`, `tc-unpowered`: no targeting without a working computer.
- `tc-zone`, `tc-chunk`: size, sector and asteroid type filters, with positive matches.
- `tc-signals`, `tc-pick`, `tc-ignore`, `tc-wires`: circuit overrides, custom signals,
  disabled overrides and the union of multiple computers' rules.
- `tc-blueprint`, `tc-gui`: ghost configuration survives revival; the window and
  required controls exist and update settings.
- `tc-fast`: controlled unreachable targets receive no decoys.
- `steel-shell`: steel kills big asteroids and rejects huge targets beyond its damage budget.
- `core-math`: analytic intercept cases, unreachable targets, range boundaries,
  scan delay, shell speed, translated origins, resistances and damage modifiers.
- `core-hull`: unsafe aim points are suppressed, foundation changes invalidate the
  cache, and empty gaps inside a hull bounding box remain targetable.
- `core-damage`: actual ammo changes and damage research alter huge-target eligibility.
- `core-combat`: stationary and crossing targets are killed by real artillery;
  three cannons respect one- and two-shell target budgets; velocity research changes
  the projectile's measured speed.
- `core-lifecycle`: target and computer destruction, replacement, and platform deletion.
- `core-save`, `core-reload`: save a tracked target and configured computer, reopen
  the save in a new process, verify settings and decoy cleanup, then intercept again.
  Saving uses a temporary headless server bound to localhost on an ephemeral port;
  it is neither listed publicly nor broadcast on LAN.

`make test-smoke` runs only `tech`. `make test-demos` additionally checks both capture
scenarios' production and combat assertions without rendering. CI is unchanged.

To run one case:

```sh
./tools/factorio-test.sh mods space-artillery/core hull 2100
./tools/factorio-test.sh mods space-artillery/playtest 'tc-zone 3600' 4000
```
