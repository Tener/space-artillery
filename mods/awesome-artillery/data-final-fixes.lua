local rotation = settings.startup["aa-rotation-multiplier"].value
local shell_speed = settings.startup["aa-shell-speed-multiplier"].value
local fire_rate = settings.startup["aa-fire-rate-multiplier"].value

-- Faster artillery: applies to all artillery, ground included.
for _, t in pairs(data.raw["artillery-turret"]) do
  t.turret_rotation_speed = t.turret_rotation_speed * rotation
end
for _, gun in pairs(data.raw.gun) do
  local ap = gun.attack_parameters
  if ap and ap.ammo_category == "artillery-shell" then ap.cooldown = ap.cooldown / fire_rate end
end

local function as_list(x) return x[1] and x or {x} end
for _, ammo in pairs(data.raw.ammo) do
  if ammo.ammo_category == "artillery-shell" then
    for _, ammo_type in pairs(as_list(ammo.ammo_type)) do
      for _, action in pairs(as_list(ammo_type.action)) do
        for _, delivery in pairs(as_list(action.action_delivery)) do
          if delivery.type == "artillery" then delivery.starting_speed = (delivery.starting_speed or 1) * shell_speed end
        end
      end
    end
  end
end

-- One invisible decoy per asteroid type. Vanilla artillery auto-targets it; it mirrors the
-- asteroid's health and resistances so vanilla's predicted-damage check prevents overkill.
data:extend{{type = "trigger-target-type", name = "aa-decoy"}}
local empty = {filename = "__core__/graphics/empty.png", size = 1, frame_count = 1}
local base = data.raw["unit-spawner"]["biter-spawner"]
for name, asteroid in pairs(data.raw.asteroid) do
  if asteroid.max_health then
    local d = table.deepcopy(base)
    d.name = "aa-decoy-" .. name
    d.localised_name = {"entity-name.aa-decoy"}
    d.hidden = true
    d.flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "not-flammable", "no-copy-paste",
      "not-upgradable", "not-selectable-in-game"}
    d.selection_box = nil
    d.collision_mask = {layers = {}}
    d.graphics_set = {animations = {empty}}
    d.max_health = asteroid.max_health
    d.resistances = table.deepcopy(asteroid.resistances)
    d.healing_per_tick = 0
    d.trigger_target_mask = {"aa-decoy"}
    d.max_count_of_owned_units = 0
    d.max_friends_around_to_spawn = 0
    d.spawning_cooldown = {1e9, 1e9}
    d.autoplace = nil
    d.minable = nil
    d.loot = nil
    d.corpse = nil
    d.dying_explosion = nil
    d.dying_sound = nil
    d.working_sound = nil
    d.damaged_trigger_effect = nil
    d.created_effect = nil
    d.spawn_decoration = nil
    d.absorptions_per_second = nil
    d.water_reflection = nil
    d.factoriopedia_simulation = nil
    data:extend{d}
  end
end

-- Targeting computer: decides which asteroids get decoys, and where. A radar that doesn't
-- scan and keeps its circuit wires to itself; its own GUI replaces the radar's.
do
  local tint = {0.55, 0.8, 1}
  local function tint_all(t)
    if type(t) ~= "table" then return end
    if t.filename or t.filenames then t.tint = tint end
    for _, v in pairs(t) do tint_all(v) end
  end
  local c = table.deepcopy(data.raw.radar.radar)
  c.name = "aa-targeting-computer"
  c.minable = {mining_time = 0.2, result = "aa-targeting-computer"}
  c.energy_usage = "100kW"
  c.energy_per_sector = "1J"
  c.energy_per_nearby_scan = "1J"
  c.max_distance_of_sector_revealed = 0
  c.max_distance_of_nearby_sector_revealed = 0
  c.connects_to_other_radars = false -- own circuit network, not the surface-wide radar one
  c.surface_conditions = {{property = "gravity", max = 0}}
  c.icons = {{icon = data.raw.item.radar.icon, tint = tint}}
  c.icon = nil
  c.fast_replaceable_group = nil
  c.next_upgrade = nil
  tint_all(c.pictures)
  local item = table.deepcopy(data.raw.item.radar)
  item.name = "aa-targeting-computer"
  item.place_result = "aa-targeting-computer"
  item.icons = c.icons
  item.icon = nil
  item.order = "d[radar]-z[targeting-computer]"
  data:extend{c, item, {
    type = "recipe", name = "aa-targeting-computer", enabled = false, energy_required = 30,
    ingredients = {
      -- rare or better, whatever the recipe's quality
      {type = "item", name = "processing-unit", amount = 50, quality_min = "rare"},
      {type = "item", name = "radar", amount = 1},
    },
    results = {{type = "item", name = "aa-targeting-computer", amount = 1}},
  }, {
    type = "technology", name = "aa-targeting-computer",
    icons = {{icon = data.raw.technology.artillery.icon, icon_size = data.raw.technology.artillery.icon_size, tint = tint}},
    prerequisites = {"artillery", "electromagnetic-science-pack", "metallurgic-science-pack"},
    effects = {{type = "unlock-recipe", recipe = "aa-targeting-computer"}},
    unit = {count = 1000, time = 60, ingredients = {
      {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
      {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
    }},
  }}
end

-- Asteroid catalogue for runtime, mod-friendly: an asteroid's type is the chunk it finally
-- breaks into, and its size is how many break-ups that takes (1 small ... 4 huge in vanilla).
do
  local function children(name)
    local out = {}
    local function walk(t)
      if type(t) ~= "table" then return end
      if t.type == "create-asteroid-chunk" and t.asteroid_name then out.chunk = out.chunk or t.asteroid_name end
      if t.type == "create-entity" and t.entity_name and data.raw.asteroid[t.entity_name] then
        out.child = out.child or t.entity_name
      end
      for _, v in pairs(t) do walk(v) end
    end
    walk(data.raw.asteroid[name].dying_trigger_effect)
    return out
  end
  local function resolve(name, depth)
    if depth > 10 then return end
    local c = children(name)
    if c.chunk then return c.chunk, 1 end
    if c.child then
      local chunk, d = resolve(c.child, depth + 1)
      if chunk then return chunk, d + 1 end
    end
  end
  local catalogue = {}
  for name, a in pairs(data.raw.asteroid) do
    if a.max_health then
      local chunk, size = resolve(name, 0)
      if not size then -- no break-up chain: guess the size from health
        local hp = a.max_health
        size = hp <= 150 and 1 or hp <= 1000 and 2 or hp <= 3500 and 3 or 4
      end
      catalogue[name] = {chunk = chunk, size = math.min(size, 4)}
    end
  end
  data:extend{{type = "mod-data", name = "aa-asteroids", data = catalogue}}
end

-- Every other turret ignores decoys (verified: without this, rocket turrets shoot them).
for _, type in pairs{"ammo-turret", "electric-turret", "fluid-turret", "turret"} do
  for _, t in pairs(data.raw[type] or {}) do
    t.ignore_target_mask = t.ignore_target_mask or {}
    table.insert(t.ignore_target_mask, "aa-decoy")
  end
end
