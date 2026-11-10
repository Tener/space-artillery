local constants = require("constants")
local simulations = require("simulations")

local function as_list(x) return x[1] and x or {x} end
for _, ammo in pairs(data.raw.ammo) do
  if ammo.ammo_category == "artillery-shell" then
    for _, ammo_type in pairs(as_list(ammo.ammo_type)) do
      for _, action in pairs(as_list(ammo_type.action)) do
        for _, delivery in pairs(as_list(action.action_delivery)) do
          if delivery.type == "artillery" then
            delivery.trigger_fired_artillery = true
          end
        end
      end
    end
  end
end

-- One invisible decoy per asteroid type. Vanilla artillery auto-targets it; it mirrors the
-- asteroid's health and resistances so vanilla's predicted-damage check prevents overkill.
data:extend{{type = "trigger-target-type", name = "space-art-decoy"}}
local empty = {filename = "__core__/graphics/empty.png", size = 1, frame_count = 1}
local base = data.raw["unit-spawner"]["biter-spawner"]
for name, asteroid in pairs(data.raw.asteroid) do
  if asteroid.max_health then
    local d = table.deepcopy(base)
    d.name = "space-art-decoy-" .. name
    d.localised_name = {"entity-name.space-art-decoy"}
    d.hidden = true
    d.flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "not-flammable", "no-copy-paste",
      "not-upgradable", "not-selectable-in-game"}
    d.selection_box = nil
    d.collision_mask = {layers = {}}
    d.graphics_set = {animations = {empty}}
    d.max_health = asteroid.max_health
    d.resistances = table.deepcopy(asteroid.resistances)
    d.healing_per_tick = 0
    d.trigger_target_mask = {"space-art-decoy"}
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
    d.hidden_in_factoriopedia = true
    data:extend{d}
  end
end

-- Targeting computer: decides which asteroids get decoys, and where. Uses programmable-speaker
-- so it takes electric power, connects to red/green circuit wires, opens a GUI, and doesn't
-- display radar scanning/coverage distance in its tooltip or Factoriopedia.
do
  local gfx = "__space-artillery__/graphics/"
  -- The packs every technology here costs, plus any extra ones named.
  local function science_packs(...)
    local list = {
      {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
      {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
    }
    for _, name in pairs{...} do list[#list + 1] = {name, 1} end
    return list
  end
  local r = data.raw.radar.radar
  local c = table.deepcopy(data.raw["programmable-speaker"]["programmable-speaker"])
  c.name = "space-art-targeting-computer"
  c.minable = {mining_time = 0.2, result = "space-art-targeting-computer"}
  c.max_health = r.max_health
  c.corpse = r.corpse
  c.dying_explosion = r.dying_explosion
  c.collision_box = table.deepcopy(r.collision_box)
  c.selection_box = table.deepcopy(r.selection_box)
  c.drawing_box_vertical_extension = r.drawing_box_vertical_extension
  c.collision_mask = table.deepcopy(r.collision_mask)
  c.resistances = table.deepcopy(r.resistances)
  c.circuit_connector = table.deepcopy(r.circuit_connector)
  c.circuit_wire_max_distance = r.circuit_wire_max_distance
  c.energy_source = {type = "electric", usage_priority = "secondary-input", drain = "5MW"}
  c.energy_usage_per_tick = "5MW"
  c.instruments = {}
  c.maximum_polyphony = 0
  c.audible_distance_modifier = 0
  c.surface_conditions = {{property = "gravity", max = 0}}
  c.icon = gfx .. "icons/targeting-computer.png"
  c.icon_size = 64
  c.icons = nil
  c.fast_replaceable_group = nil
  c.next_upgrade = nil
  c.water_reflection = nil
  c.sprite = {
    layers = {
      {
        filename = gfx .. "entity/targeting-computer/targeting-computer.png",
        priority = "high",
        width = 208,
        height = 208,
        scale = 0.5,
      },
      {
        filename = gfx .. "entity/targeting-computer/targeting-computer-shadow.png",
        priority = "high",
        width = 264,
        height = 208,
        shift = {0.45, 0.1},
        draw_as_shadow = true,
        scale = 0.5,
      },
    },
  }
  c.factoriopedia_description = {"factoriopedia-description.space-art-targeting-computer"}
  local item = table.deepcopy(data.raw.item.radar)
  item.name = "space-art-targeting-computer"
  item.place_result = "space-art-targeting-computer"
  item.icon = c.icon
  item.icon_size = 64
  item.icons = nil
  item.order = "d[radar]-z[targeting-computer]"
  item.factoriopedia_description = {"factoriopedia-description.space-art-targeting-computer"}
  data:extend{c, item, {
    type = "recipe", name = "space-art-targeting-computer", enabled = false, energy_required = 30,
    ingredients = {
      -- rare or better, whatever the recipe's quality
      {type = "item", name = "processing-unit", amount = 50, quality_min = "rare"},
      {type = "item", name = "radar", amount = 5, quality_min = "rare"},
      {type = "item", name = "superconductor", amount = 20},
      {type = "item", name = "tungsten-plate", amount = 20},
      {type = "item", name = "low-density-structure", amount = 10},
    },
    results = {{type = "item", name = "space-art-targeting-computer", amount = 1}},
  }, {
    type = "technology", name = "space-art-targeting-computer",
    icon = gfx .. "technology/targeting-computer.png",
    icon_size = 256,
    prerequisites = {"artillery", "electromagnetic-science-pack", "metallurgic-science-pack"},
    effects = {{type = "unlock-recipe", recipe = "space-art-targeting-computer"}},
    unit = {count = 1000, time = 60, ingredients = science_packs()},
  }}

  -- Locale text quoting a shell's damage next to the base shell's: __1__/__2__ physical and
  -- explosion of the shell, __3__/__4__ of the base artillery shell.
  local function damage_text(section, shell_name)
    local d, base = constants.shells[shell_name], constants.shells["artillery-shell"]
    return {section .. "." .. shell_name, tostring(d.physical), tostring(d.explosion),
      tostring(base.physical), tostring(base.explosion)}
  end
  local rotation_percent, velocity_percent = tostring(constants.rotation_percent), tostring(constants.velocity_percent)

  -- Space-manufacturable artillery shell: flash-hardened steel (steel + carbon + calcite + ice)
  -- replaces Vulcanus tungsten. Weaker physical damage, so it scales more slowly against big
  -- asteroids and never breaks huge asteroids' 3000 flat physical resistance.
  local steel = data.raw.item["steel-plate"]
  local fhs = table.deepcopy(steel)
  fhs.name = "space-art-flash-hardened-steel"
  fhs.order = (steel.order or "c[steel-plate]") .. "-b[flash-hardened]"
  fhs.stack_size = 50
  fhs.icon = gfx .. "icons/flash-hardened-steel.png"
  fhs.icon_size = 64
  fhs.icons = nil
  fhs.random_tint_color = nil
  fhs.factoriopedia_simulation = nil
  fhs.factoriopedia_description = {"factoriopedia-description.space-art-flash-hardened-steel"}

  local function set_damage(t, phys, expl)
    if type(t) ~= "table" then return end
    if t.type == "damage" and t.damage then
      if t.damage.type == "physical" then t.damage.amount = phys
      elseif t.damage.type == "explosion" then t.damage.amount = expl end
    end
    for _, v in pairs(t) do set_damage(v, phys, expl) end
  end
  local function set_proj(t, proj_name)
    if type(t) ~= "table" then return end
    if t.type == "artillery" and t.projectile then t.projectile = proj_name end
    for _, v in pairs(t) do set_proj(v, proj_name) end
  end
  -- A copy of the base artillery shell and its projectile, with the damage constants.lua
  -- lists for it. kind names the shell and its graphics ("steel", "promethium").
  local base_shell = data.raw.ammo["artillery-shell"]
  local function make_shell(kind, order, map_color, picture_scale)
    local name = "space-art-" .. kind .. "-artillery-shell"
    local proj = table.deepcopy(data.raw["artillery-projectile"]["artillery-projectile"])
    proj.name = "space-art-" .. kind .. "-artillery-projectile"
    proj.hidden_in_factoriopedia = true
    proj.map_color = map_color
    proj.picture = {
      filename = gfx .. "entity/projectile/" .. kind .. "-shell.png",
      width = 64,
      height = 64,
      scale = picture_scale,
    }
    set_damage(proj.action, constants.shells[name].physical, constants.shells[name].explosion)

    local shell = table.deepcopy(base_shell)
    shell.name = name
    shell.order = (base_shell.order or "d[explosive-cannon-shell]-d[artillery]") .. "-" .. order .. "[" .. kind .. "]"
    shell.icon = gfx .. "icons/" .. kind .. "-artillery-shell.png"
    shell.icon_size = 64
    shell.icons = nil
    shell.factoriopedia_simulation = nil
    shell.factoriopedia_description = damage_text("factoriopedia-description", name)
    set_proj(shell.ammo_type, proj.name)
    return shell, proj
  end
  local shell, proj = make_shell("steel", "b", {0.4, 0.85, 1}, 0.5)

  -- Heavy armor-piercing promethium artillery shell: its physical damage punches through huge
  -- asteroids' 3000 flat physical resistance even at 0% damage research.
  local prom_shell, prom_proj = make_shell("promethium", "c", {0.9, 0.3, 1}, 0.55)
  if data.raw.explosion and data.raw.explosion["massive-explosion"]
    and prom_proj.action and prom_proj.action.action_delivery and prom_proj.action.action_delivery.target_effects then
    table.insert(prom_proj.action.action_delivery.target_effects, {
      type = "create-entity",
      entity_name = "massive-explosion",
    })
  end

  -- A technology completed by control.lua (field data), gating a shell technology.
  local function trigger_tech(short, prerequisite, param)
    local name = "space-art-" .. short
    return {
      type = "technology", name = name,
      icon = gfx .. "technology/" .. short .. ".png",
      icon_size = 256,
      factoriopedia_description = {"factoriopedia-description." .. name, param},
      prerequisites = {prerequisite},
      effects = {
        {type = "nothing", effect_description = {"technology-effect." .. name}},
      },
      research_trigger = {
        type = "scripted",
        trigger_description = {"technology-trigger." .. name, param},
      },
    }
  end

  -- The checkpoint uses the normal research bar. Its data has no recipe,
  -- so only the kill counter can advance it during play.
  local field_data = "space-art-interception-data"
  data:extend{{
    type = "tool", name = field_data,
    icon = gfx .. "technology/asteroid-ballistics.png", icon_size = 256,
    stack_size = 1, durability = 1, hidden = true, hidden_in_factoriopedia = true,
  }}
  -- Every research ingredient must be accepted by at least one lab.
  table.insert(data.raw.lab.lab.inputs, field_data)
  local asteroid_ballistics = {
    type = "technology", name = "space-art-asteroid-ballistics",
    icon = gfx .. "technology/asteroid-ballistics.png", icon_size = 256,
    localised_description = {"technology-description.space-art-asteroid-ballistics", tostring(constants.ballistics_kills)},
    factoriopedia_description = {"factoriopedia-description.space-art-asteroid-ballistics", tostring(constants.ballistics_kills)},
    prerequisites = {"space-art-targeting-computer"},
    effects = {{type = "nothing", effect_description = {"technology-effect.space-art-asteroid-ballistics"}}},
    unit = {count = constants.ballistics_kills, time = 1, ingredients = {{field_data, 1}}},
    ignore_tech_cost_multiplier = true,
  }

  local function shell_tech(kind, prerequisites, recipes, count, ...)
    local name = "space-art-" .. kind .. "-artillery-shell"
    local effects = {}
    for _, recipe in pairs(recipes) do effects[#effects + 1] = {type = "unlock-recipe", recipe = recipe} end
    return {
      type = "technology", name = name,
      icon = gfx .. "technology/" .. kind .. "-artillery-shell.png",
      icon_size = 256,
      factoriopedia_description = damage_text("factoriopedia-description", name),
      prerequisites = prerequisites,
      effects = effects,
      unit = {count = count, time = 60, ingredients = science_packs(...)},
    }
  end

  data:extend{fhs, proj, shell, prom_proj, prom_shell, {
    type = "recipe", name = "space-art-flash-hardened-steel", categories = {"metallurgy"}, enabled = false, energy_required = 19.2,
    allow_productivity = true, auto_recycle = false,
    ingredients = {
      {type = "fluid", name = "molten-iron", amount = 60, fluidbox_multiplier = 10},
      {type = "item", name = "carbon", amount = 2},
      {type = "item", name = "calcite", amount = 1},
      {type = "item", name = "ice", amount = 2},
    },
    results = {{type = "item", name = "space-art-flash-hardened-steel", amount = 1}},
  }, {
    type = "recipe", name = "space-art-steel-artillery-shell", categories = {"metallurgy"}, enabled = false, energy_required = 15,
    ingredients = {
      {type = "item", name = "space-art-flash-hardened-steel", amount = 2},
      {type = "item", name = "explosives", amount = 8},
      {type = "item", name = "radar", amount = 1},
    },
    results = {{type = "item", name = "space-art-steel-artillery-shell", amount = 1}},
  }, {
    type = "recipe", name = "space-art-promethium-artillery-shell", categories = {"metallurgy"}, enabled = false, energy_required = 20,
    ingredients = {
      {type = "item", name = "space-art-flash-hardened-steel", amount = 2},
      {type = "item", name = "promethium-asteroid-chunk", amount = 1},
      {type = "item", name = "explosives", amount = 8},
      {type = "item", name = "radar", amount = 1},
    },
    results = {{type = "item", name = "space-art-promethium-artillery-shell", amount = 1}},
  },
    asteroid_ballistics,
    shell_tech("steel", {"space-art-asteroid-ballistics", "advanced-asteroid-processing"},
      {"space-art-flash-hardened-steel", "space-art-steel-artillery-shell"}, 2000),
    trigger_tech("promethium-ballistics", "space-art-steel-artillery-shell"),
    shell_tech("promethium", {"space-art-promethium-ballistics"},
      {"space-art-promethium-artillery-shell"}, 4000, "agricultural-science-pack", "cryogenic-science-pack"),
  }

  -- Artillery turret turning speed research (starting at 2k). Factorio has no built-in
  -- technology modifier for turret_rotation_speed, so each level uses a hidden
  -- artillery-turret prototype fast-replaced on research/build (zero on_tick cost).
  local base_turret = data.raw["artillery-turret"]["artillery-turret"]
  base_turret.fast_replaceable_group = base_turret.fast_replaceable_group or "artillery-turret"
  for level = 1, constants.rotation_levels do
    local tr = table.deepcopy(base_turret)
    tr.name = "space-art-artillery-turret-r" .. level
    tr.localised_name = {"entity-name.artillery-turret"}
    tr.localised_description = {"entity-description.artillery-turret"}
    tr.hidden = true
    tr.hidden_in_factoriopedia = true
    tr.factoriopedia_simulation = nil
    tr.placeable_by = {item = "artillery-turret", count = 1}
    tr.minable = base_turret.minable and {mining_time = base_turret.minable.mining_time, result = "artillery-turret"} or nil
    tr.turret_rotation_speed = base_turret.turret_rotation_speed * (1 + constants.rotation_percent / 100 * level)
    local ing = science_packs()
    if level >= 4 then ing[#ing + 1] = {"cryogenic-science-pack", 1} end
    if level >= 7 then ing[#ing + 1] = {"promethium-science-pack", 1} end
    data:extend{tr, {
      type = "technology",
      name = "space-art-artillery-rotation-" .. level,
      icons = {
        {icon = gfx .. "technology/artillery-rotation.png", icon_size = 256},
        {icon = "__core__/graphics/icons/technology/effect-constant/effect-constant-movement-speed.png", icon_size = 64, shift = {32, 32}},
      },
      factoriopedia_description = {"factoriopedia-description.space-art-artillery-rotation", rotation_percent},
      prerequisites = {level == 1 and "space-art-targeting-computer" or ("space-art-artillery-rotation-" .. (level - 1))},
      effects = {{type = "nothing", effect_description = {"technology-effect.space-art-artillery-rotation", rotation_percent}}},
      unit = {count = 2000 * (2 ^ (level - 1)), time = 60, ingredients = ing},
      upgrade = true,
    }}
  end

  -- Artillery shell velocity research (infinite, starting at 2k).
  data:extend{{
    type = "technology",
    name = "space-art-artillery-shell-velocity-1",
    icons = {
      {icon = gfx .. "technology/artillery-shell-velocity.png", icon_size = 256},
      {icon = "__core__/graphics/icons/technology/effect-constant/effect-constant-movement-speed.png", icon_size = 64, shift = {32, 32}},
    },
    factoriopedia_description = {"factoriopedia-description.space-art-artillery-shell-velocity", velocity_percent},
    prerequisites = {"space-art-targeting-computer"},
    effects = {{type = "nothing", effect_description = {"technology-effect.space-art-artillery-shell-velocity", velocity_percent}}},
    unit = {
      count_formula = "2^(L-1)*2000",
      time = 60,
      ingredients = science_packs(),
    },
    max_level = "infinite",
    upgrade = true,
  }}

  local tips = data.raw["tips-and-tricks-item"] or {}
  local parent = tips["asteroid-defense"] or tips["space-platform"]
  local cat = parent and parent.category or (data.raw["tips-and-tricks-item-category"]["space-platform"] and "space-platform") or nil
  local base_indent = parent and (parent.indent or 0) or 1
  local base_order = parent and (parent.order or "z") or "z[space-artillery]"

  c.factoriopedia_simulation = simulations.space
  item.factoriopedia_simulation = simulations.space
  fhs.factoriopedia_simulation = simulations.fhs
  shell.factoriopedia_simulation = simulations.steel
  prom_shell.factoriopedia_simulation = simulations.prom

  data:extend{
    {
      type = "tips-and-tricks-item",
      name = "space-art-space-artillery",
      category = cat,
      indent = base_indent,
      order = base_order .. "-z[space-art-a]",
      tag = "[entity=space-art-targeting-computer]",
      dependencies = parent and {parent.name} or nil,
      trigger = {type = "research", technology = "space-art-targeting-computer"},
      simulation = simulations.space,
    },
    {
      type = "tips-and-tricks-item",
      name = "space-art-steel-artillery-shell",
      category = cat,
      indent = base_indent + 1,
      order = base_order .. "-z[space-art-b]",
      tag = "[item=space-art-steel-artillery-shell]",
      localised_description = {"tips-and-tricks-item-description.space-art-steel-artillery-shell"},
      dependencies = {"space-art-space-artillery"},
      trigger = {type = "research", technology = "space-art-steel-artillery-shell"},
      simulation = simulations.steel,
    },
    {
      type = "tips-and-tricks-item",
      name = "space-art-promethium-artillery-shell",
      category = cat,
      indent = base_indent + 1,
      order = base_order .. "-z[space-art-c]",
      tag = "[item=space-art-promethium-artillery-shell]",
      localised_description = {"tips-and-tricks-item-description.space-art-promethium-artillery-shell"},
      dependencies = {"space-art-steel-artillery-shell"},
      trigger = {type = "research", technology = "space-art-promethium-artillery-shell"},
      simulation = simulations.prom,
    },
  }
  data:extend{{type = "mod-data", name = "space-art-sims", data = {
    space = simulations.space.init,
    fhs = simulations.fhs.init,
    steel = simulations.steel.init,
    prom = simulations.prom.init,
  }}}
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
  data:extend{{type = "mod-data", name = "space-art-asteroids", data = catalogue}}
end

-- Every other turret ignores decoys (verified: without this, rocket turrets shoot them).
for _, type in pairs{"ammo-turret", "electric-turret", "fluid-turret", "turret"} do
  for _, t in pairs(data.raw[type] or {}) do
    t.ignore_target_mask = t.ignore_target_mask or {}
    table.insert(t.ignore_target_mask, "space-art-decoy")
  end
end
