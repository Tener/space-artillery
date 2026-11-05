# Awesome Artillery

More uses for artillery. This first release teaches **space platform artillery to shoot
asteroids**. More is planned: new shell types, and flares to call artillery on
demolishers.

## Asteroid defense

Put artillery turrets and a **targeting computer** on your space platform. The artillery
then engages asteroids at long range, leading its shots so they land where the asteroid
will be.

- **Never hits your own ship.** Shots that would land near the hull are held back.
- **No overkill.** Turrets share out targets and fire just enough shells to kill each
  asteroid.
- **Research matters.** Artillery damage research makes big and eventually huge
  asteroids worth shooting; fire rate, range and shell speed research all apply.
- **Vanilla turret, vanilla shells.** Same ammo logistics as on the ground.

## Targeting computer

Unlocked by the "Artillery targeting computer" research (needs Fulgora and Vulcanus
science). Craft it from rare processing units, rare radars and a few space-age parts.

The computer decides which asteroids its platform's artillery shoots:
- asteroid **sizes** and **types** (metallic, carbonic, oxide, ...);
- a **zone**: direction, arc, and near and far distance. The zone is drawn while the
  computer's window is open;
- **circuit control**: each setting can come from a signal of your choice, plus a
  switch-off signal.

Settings are kept in blueprints and can be copy-pasted.

## Tips

- Artillery has a 32-tile minimum range and avoids the hull, so asteroids that get
  close still need guns, rockets or lasers. Medium asteroids shrug off lasers.
- Vanilla decides which turret fires, so place turrets where they cover the bow.

## Settings

- **Startup:** artillery turret rotation speed (5×), shell speed (3×) and fire rate
  (2×). These apply to **all artillery**, ground included.
- **Map:** update interval, smallest asteroid to target, most shells per asteroid, hull
  safety margin, and whether artillery needs a targeting computer.

## Compatibility

Requires Space Age. Modded asteroids and turrets are handled: other turrets ignore the
artillery's invisible targets.
