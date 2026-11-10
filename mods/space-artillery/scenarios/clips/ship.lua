-- A minimal ship that casts its own artillery shells, built around the hub.
--
-- Inserters only reach the hub itself (not cargo bays), so its 32 edge tiles are the ship's
-- backbone: each machine takes its ingredients from the hub through one filtered inserter and
-- puts its product back through another, which a logistic condition switches off once the
-- hub holds enough. No belts.
--
--   bow    three collectors, each feeding the crusher behind it
--   west   iron melter, steel foundry, cannon
--   east   targeting computer, shell foundry, cannon
--   south  thruster fuel, water and oxidizer plants, then solar panels and the thrusters
--
-- Steel is made from collected chunks. Explosives and radars are cargo: the caller stocks
-- them in the hub, as a rocket would.
local router = require("__space-artillery__/scenarios/showcase/router")
local M = {}

local FOUNDATION = "space-platform-foundation"
local FHS = "space-art-flash-hardened-steel"
local SHELL = "space-art-steel-artillery-shell"
M.RESERVE = 24 -- shells the hub holds before the foundry's output inserter stops

function M.build(profile)
  local force = game.forces.player
  for _, name in ipairs{"vulcanus", "gleba", "fulgora", "aquilo"} do force.unlock_space_location(name) end
  for _, recipe in pairs(force.recipes) do recipe.enabled = true end
  for level = 1, profile.rotation do force.technologies["space-art-artillery-rotation-" .. level].researched = true end
  force.technologies["space-art-artillery-shell-velocity-1"].level = profile.velocity + 1
  force.set_ammo_damage_modifier("artillery-shell", profile.damage)
  force.set_gun_speed_modifier("artillery-shell", profile.fire_rate)
  force.set_ammo_damage_modifier("bullet", profile.bullet_damage)
  force.set_gun_speed_modifier("bullet", profile.bullet_fire_rate)

  local platform = force.create_space_platform{
    name = "Artillery Sloop", planet = profile.origin, starter_pack = "space-platform-starter-pack",
  }
  local hub = platform.apply_starter_pack()
  hub.destructible = false
  local surface = platform.surface
  surface.request_to_generate_chunks({0, 0}, 8)
  surface.force_generate_chunk_requests()

  local tiles = {}
  local function rect(x1, y1, x2, y2)
    for x = x1, x2 do
      for y = y1, y2 do tiles[#tiles + 1] = {name = FOUNDATION, position = {x, y}} end
    end
  end
  rect(-12, -8, 11, 8)   -- core
  -- Bow. A collector's front row must hang over open space, so the hull stops one row short
  -- of each; the middle collector sits one row forward.
  rect(-5, -10, 4, -9)
  rect(-2, -11, 0, -11)
  rect(-15, 9, 14, 26)   -- solar deck
  rect(-11, 27, 10, 31)  -- thrusters, and a column either side for their pipes
  surface.set_tiles(tiles)
  -- Spare calcite is thrown into this gap between the collectors.
  surface.set_tiles{{name = "empty-space", position = {1, -9}}}

  local g = router.new(surface, force, {-16, -13, 15, 32})
  local nodes = g.nodes
  g.claim(hub)

  local function machine(id, name, center, recipe, direction)
    nodes[id] = g.make(name, center, direction, {recipe = recipe})
    return nodes[id]
  end
  -- An inserter on a tile, picking up from the given side.
  --   filters: item names it may move
  --   limit: {item, comparator, count}: works only while the hub's stock of item passes
  local function inserter(tile, from, options)
    local entity = g.make("bulk-inserter", router.point(tile), defines.direction[from])
    options = options or {}
    if options.filters then
      entity.use_filters = true
      for i, name in ipairs(options.filters) do entity.set_filter(i, name) end
    end
    if options.limit then
      local behavior = entity.get_or_create_control_behavior()
      behavior.connect_to_logistic_network = true
      behavior.logistic_condition = {first_signal = {type = "item", name = options.limit[1]},
        comparator = options.limit[2], constant = options.limit[3]}
    end
    return entity
  end

  -- Bow: collector -> crusher -> hub. Crushed chunks that come back whole return through the hub.
  local function collector(id, center, chunk)
    local entity = machine(id .. "_collector", "asteroid-collector", center)
    entity.set_filter(1, chunk)
  end
  collector("carbon", {-3.5, -9.5}, "carbonic-asteroid-chunk")
  collector("metal", {-0.5, -10.5}, "metallic-asteroid-chunk")
  collector("oxide", {3.5, -9.5}, "oxide-asteroid-chunk")
  machine("carbon", "crusher", {-2.5, -6}, "carbonic-asteroid-crushing", defines.direction.east)
  machine("metal", "crusher", {0, -6.5}, "metallic-asteroid-crushing")
  machine("oxide", "crusher", {2.5, -6}, "advanced-oxide-asteroid-crushing", defines.direction.east)
  inserter({-3, -8}, "north")
  inserter({-1, -9}, "north")
  inserter({3, -8}, "north")
  inserter({-4, -5}, "north", {limit = {"carbon", "<", 200}})
  inserter({-3, -5}, "south", {filters = {"carbonic-asteroid-chunk"}})
  inserter({-1, -5}, "north", {limit = {"iron-ore", "<", 200}})
  inserter({0, -5}, "south", {filters = {"metallic-asteroid-chunk"}})
  -- Oxide: ice is the product that matters; calcite beyond what the hub needs goes overboard.
  inserter({1, -5}, "south", {filters = {"oxide-asteroid-chunk"}})
  inserter({2, -5}, "north", {filters = {"calcite"}, limit = {"calcite", "<", 100}})
  inserter({3, -5}, "north", {filters = {"ice", "oxide-asteroid-chunk"}, limit = {"ice", "<", 200}})
  inserter({1, -8}, "south", {filters = {"calcite"}, limit = {"calcite", ">", 99}})

  -- West of the hub: iron melting above the steel foundry. Both face south, so the melter's
  -- outlets and the steel foundry's inlets share the row between them.
  local turrets = {}
  local cannon = profile.rotation > 0 and ("space-art-artillery-turret-r" .. profile.rotation) or "artillery-turret"
  machine("melt", "foundry", {-7.5, -5.5}, "iron-ore-melting", defines.direction.south)
  inserter({-5, -4}, "east", {filters = {"iron-ore", "calcite"}})
  g.pipe(-9, -3, "molten-iron")
  g.pipe(-7, -3, "molten-iron")
  machine("steel", "foundry", {-7.5, 0.5}, FHS, defines.direction.south)
  inserter({-5, -1}, "east", {filters = {"carbon", "calcite", "ice"}})
  inserter({-5, 0}, "west", {limit = {FHS, "<", 40}})
  turrets[1] = machine("gun1", cannon, {-6.5, 4.5})
  inserter({-5, 3}, "east", {filters = {SHELL}})

  -- East of the hub: the shell foundry and the other cannon.
  machine("shells", "foundry", {7.5, 0.5}, SHELL)
  inserter({4, -1}, "west", {filters = {FHS, "explosives", "radar"}})
  inserter({4, 0}, "east", {limit = {SHELL, "<", M.RESERVE}})
  turrets[2] = machine("gun2", cannon, {6.5, 4.5})
  inserter({4, 3}, "west", {filters = {SHELL}})
  local computer = g.make("space-art-targeting-computer", {8.5, -6.5})

  -- South of the hub: thruster fuel, water and oxidizer. The water plant faces the hub, so
  -- its outlets meet its neighbours' inlets in the inserter row.
  -- Ice is the scarce input and steel needs it too, so propellant is only made while the
  -- hub's shell reserve is full.
  machine("fuel", "chemical-plant", {-3.5, 6.5}, "thruster-fuel")
  inserter({-4, 4}, "north", {filters = {"carbon"}, limit = {SHELL, ">", M.RESERVE - 1}})
  machine("water", "chemical-plant", {0.5, 6.5}, "ice-melting", defines.direction.south)
  inserter({0, 4}, "north", {filters = {"ice"}})
  machine("oxidizer", "chemical-plant", {3.5, 6.5}, "thruster-oxidizer")
  inserter({3, 4}, "north", {filters = {"iron-ore"}, limit = {SHELL, ">", M.RESERVE - 1}})
  for _, x in ipairs{-3, -2, -1, 1, 2} do g.pipe(x, 4, "water") end

  local thrusters = {}
  -- Spaced apart: a thruster's fuel and oxidizer ports swap sides, so neighbours cannot touch.
  for i, x in ipairs{-8, 0, 8} do
    thrusters[i] = machine("thruster" .. i, "thruster", {x, 29})
  end

  -- Gun turrets down both sides of the core and on the deck's leading corners.
  local guns = {}
  for _, p in ipairs{{-11, -4}, {-11, -1}, {-11, 2}, {-11, 5}, {11, -7}, {11, -4}, {11, -1}, {11, 2}, {11, 5},
    {-14, 10}, {13, 10}} do
    guns[#guns + 1] = g.make("gun-turret", p)
  end

  for _, p in ipairs{{-11, -7}, {6, -5}, {-9, 7}, {9, 7}, {-8, 18}, {7, 18}} do g.make("substation", p) end

  g.reserve_fluid_ports()
  for i = 1, #thrusters do
    g.fluid_link("fuel", "thruster" .. i, "thruster-fuel")
    g.fluid_link("oxidizer", "thruster" .. i, "thruster-oxidizer")
  end

  -- Solar panels fill what the pipes left of the deck, then any gap in the core.
  local panels = 0
  local function fill(y1, y2)
    for y = y1, y2 do
      for x = -15, 12 do
        local spot = {name = "solar-panel", position = {x + 1.5, y + 1.5}, force = force}
        if surface.can_place_entity(spot) then
          g.make("solar-panel", spot.position)
          panels = panels + 1
        end
      end
    end
  end
  fill(9, 24)
  fill(-8, 6)
  g.connect_poles()

  platform.schedule = {current = 1, records = {{station = profile.destination}, {station = profile.origin}}}
  platform.paused = true
  return {platform = platform, hub = hub, nodes = nodes, turrets = turrets, computer = computer,
    thrusters = thrusters, guns = guns, panels = panels}
end

return M
