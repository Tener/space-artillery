# Awesome Artillery

Teaches **space platform artillery to shoot incoming asteroids**, guided by an orbital **targeting computer**, with **space-manufacturable steel and promethium artillery shells** and dedicated **rotation speed & shell velocity research**.

## Asteroid defense

Place artillery turrets and a **targeting computer** (`5 MW`) on your space platform. Artillery engages incoming asteroids at long range, leading shots so they detonate along the asteroid's flight path.

- **Hull splash safety:** Shots that would detonate near platform foundation are held back.
- **No overkill:** Turrets share targets and fire only enough shells to destroy each asteroid based on your loaded shell type and damage research.
- **Research progression:**
  - **Artillery turret rotation speed (1–10):** +30% turning speed per level (up to +300% = 4× at level 10).
  - **Artillery shell velocity (1–∞):** +20% projectile flight speed per level, reducing time-to-target against fast asteroids.
  - Vanilla artillery damage and shooting speed upgrades apply in full.

## Targeting computer

Unlocked by **Artillery targeting computer** (requires Fulgora and Vulcanus science; crafted from rare processing units, rare radars, superconductors, tungsten plates, and low-density structures).

Each computer configures which asteroids its platform's artillery engages:
- Asteroid **sizes** (`Small`, `Medium`, `Big`, `Huge`) and **chunk types** (`Metallic`, `Carbonic`, `Oxide`, `Promethium`, plus any modded asteroid chunks).
- A directional **sector zone**: direction, arc angle, and near/far range, highlighted on the platform while the window is open.
- **Circuit network control:** Every parameter can be driven dynamically by red/green wire signals, plus a configurable switch-off signal.
- **Blueprints & ghosts:** Settings persist in blueprints, copy-paste (`Shift+Right/Left Click`), and can be configured directly on unbuilt **ghost** targeting computers.

## Space-manufactured shells

- **Flash-hardened steel & Steel artillery shell (`200 physical + 800 explosion`):**
  - Destroying **500** medium, big, or huge metallic, carbonic, or oxide asteroids with artillery completes **Asteroid ballistics field data**, unlocking the **Steel artillery shell** research (`2,000` packs).
  - Cast in a **foundry** in space from asteroid resources (`molten-iron`, `carbon`, `calcite`, `ice`, `explosives`, and `radar`) without needing imported Vulcanus tungsten. Matches tungsten shells against small, medium, and big asteroids at base research, scales more slowly on big asteroids, and cannot pierce huge asteroids' 3,000 flat physical armor.
- **Promethium artillery shell (`4000 physical + 1000 explosion`):**
  - Destroying any medium, big, or huge promethium asteroid completes **Promethium ballistics field data**, unlocking the **Promethium artillery shell** research (`4,000` packs).
  - Cast in a **foundry** in space from **flash-hardened steel** and **promethium asteroid chunks**, its massive kinetic punch pierces huge asteroids' 3,000 flat physical resistance even at 0% damage research and one-shots big asteroids.

## Map settings

- Update interval (ticks), smallest asteroid size to target, maximum shells to spend on one asteroid, hull safety margin (tiles), and whether platform artillery requires a powered targeting computer.

## Compatibility

Requires Factorio 2.1 + Space Age. Modded asteroids and turrets are supported automatically: non-artillery turrets ignore the artillery's lead decoys.
