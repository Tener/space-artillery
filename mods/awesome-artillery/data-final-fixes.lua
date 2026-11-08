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
data:extend{{type = "trigger-target-type", name = "awe-art-decoy"}}
local empty = {filename = "__core__/graphics/empty.png", size = 1, frame_count = 1}
local base = data.raw["unit-spawner"]["biter-spawner"]
for name, asteroid in pairs(data.raw.asteroid) do
  if asteroid.max_health then
    local d = table.deepcopy(base)
    d.name = "awe-art-decoy-" .. name
    d.localised_name = {"entity-name.awe-art-decoy"}
    d.hidden = true
    d.flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "not-flammable", "no-copy-paste",
      "not-upgradable", "not-selectable-in-game"}
    d.selection_box = nil
    d.collision_mask = {layers = {}}
    d.graphics_set = {animations = {empty}}
    d.max_health = asteroid.max_health
    d.resistances = table.deepcopy(asteroid.resistances)
    d.healing_per_tick = 0
    d.trigger_target_mask = {"awe-art-decoy"}
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
  local gfx = "__awesome-artillery__/graphics/"
  local r = data.raw.radar.radar
  local c = table.deepcopy(data.raw["programmable-speaker"]["programmable-speaker"])
  c.name = "awe-art-targeting-computer"
  c.minable = {mining_time = 0.2, result = "awe-art-targeting-computer"}
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
  c.factoriopedia_description = {"factoriopedia-description.awe-art-targeting-computer"}
  local item = table.deepcopy(data.raw.item.radar)
  item.name = "awe-art-targeting-computer"
  item.place_result = "awe-art-targeting-computer"
  item.icon = c.icon
  item.icon_size = 64
  item.icons = nil
  item.order = "d[radar]-z[targeting-computer]"
  item.factoriopedia_description = {"factoriopedia-description.awe-art-targeting-computer"}
  data:extend{c, item, {
    type = "recipe", name = "awe-art-targeting-computer", enabled = false, energy_required = 30,
    ingredients = {
      -- rare or better, whatever the recipe's quality
      {type = "item", name = "processing-unit", amount = 50, quality_min = "rare"},
      {type = "item", name = "radar", amount = 5, quality_min = "rare"},
      {type = "item", name = "superconductor", amount = 20},
      {type = "item", name = "tungsten-plate", amount = 20},
      {type = "item", name = "low-density-structure", amount = 10},
    },
    results = {{type = "item", name = "awe-art-targeting-computer", amount = 1}},
  }, {
    type = "technology", name = "awe-art-targeting-computer",
    icon = gfx .. "technology/targeting-computer.png",
    icon_size = 256,
    prerequisites = {"artillery", "electromagnetic-science-pack", "metallurgic-science-pack"},
    effects = {{type = "unlock-recipe", recipe = "awe-art-targeting-computer"}},
    unit = {count = 1000, time = 60, ingredients = {
      {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
      {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
    }},
  }}

  -- Space-manufacturable artillery shell: flash-hardened steel (steel + carbon + calcite + ice)
  -- replaces Vulcanus tungsten. Weaker physical damage (200 vs 1000), so it scales more slowly
  -- against big asteroids and never breaks huge asteroids' 3000 flat physical resistance.
  local steel = data.raw.item["steel-plate"]
  local fhs = table.deepcopy(steel)
  fhs.name = "awe-art-flash-hardened-steel"
  fhs.order = (steel.order or "c[steel-plate]") .. "-b[flash-hardened]"
  fhs.stack_size = 50
  fhs.icon = gfx .. "icons/flash-hardened-steel.png"
  fhs.icon_size = 64
  fhs.icons = nil
  fhs.random_tint_color = nil
  fhs.factoriopedia_simulation = nil
  fhs.factoriopedia_description = {"factoriopedia-description.awe-art-flash-hardened-steel"}

  local proj = table.deepcopy(data.raw["artillery-projectile"]["artillery-projectile"])
  proj.name = "awe-art-steel-artillery-projectile"
  proj.hidden_in_factoriopedia = true
  proj.map_color = {0.4, 0.85, 1}
  proj.picture = {
    filename = gfx .. "entity/projectile/steel-shell.png",
    width = 64,
    height = 64,
    scale = 0.5,
  }
  local function set_damage(t, phys, expl)
    if type(t) ~= "table" then return end
    if t.type == "damage" and t.damage then
      if t.damage.type == "physical" then t.damage.amount = phys
      elseif t.damage.type == "explosion" then t.damage.amount = expl end
    end
    for _, v in pairs(t) do set_damage(v, phys, expl) end
  end
  set_damage(proj.action, 200, 800)

  local base_shell = data.raw.ammo["artillery-shell"]
  local shell = table.deepcopy(base_shell)
  shell.name = "awe-art-steel-artillery-shell"
  shell.order = (base_shell.order or "d[explosive-cannon-shell]-d[artillery]") .. "-b[steel]"
  shell.icon = gfx .. "icons/steel-artillery-shell.png"
  shell.icon_size = 64
  shell.icons = nil
  shell.factoriopedia_simulation = nil
  shell.factoriopedia_description = {"factoriopedia-description.awe-art-steel-artillery-shell"}
  local function set_proj(t, proj_name)
    if type(t) ~= "table" then return end
    if t.type == "artillery" and t.projectile then t.projectile = proj_name end
    for _, v in pairs(t) do set_proj(v, proj_name) end
  end
  set_proj(shell.ammo_type, "awe-art-steel-artillery-projectile")

  -- Heavy armor-piercing promethium artillery shell: 4000 physical + 1000 explosion damage,
  -- punching through huge asteroids' 3000 flat physical resistance even at 0% damage research.
  local prom_proj = table.deepcopy(data.raw["artillery-projectile"]["artillery-projectile"])
  prom_proj.name = "awe-art-promethium-artillery-projectile"
  prom_proj.hidden_in_factoriopedia = true
  prom_proj.map_color = {0.9, 0.3, 1}
  prom_proj.picture = {
    filename = gfx .. "entity/projectile/promethium-shell.png",
    width = 64,
    height = 64,
    scale = 0.55,
  }
  set_damage(prom_proj.action, 4000, 1000)
  if data.raw.explosion and data.raw.explosion["massive-explosion"]
    and prom_proj.action and prom_proj.action.action_delivery and prom_proj.action.action_delivery.target_effects then
    table.insert(prom_proj.action.action_delivery.target_effects, {
      type = "create-entity",
      entity_name = "massive-explosion",
    })
  end

  local prom_shell = table.deepcopy(base_shell)
  prom_shell.name = "awe-art-promethium-artillery-shell"
  prom_shell.order = (base_shell.order or "d[explosive-cannon-shell]-d[artillery]") .. "-c[promethium]"
  prom_shell.icon = gfx .. "icons/promethium-artillery-shell.png"
  prom_shell.icon_size = 64
  prom_shell.icons = nil
  prom_shell.factoriopedia_simulation = nil
  prom_shell.factoriopedia_description = {"factoriopedia-description.awe-art-promethium-artillery-shell"}
  set_proj(prom_shell.ammo_type, "awe-art-promethium-artillery-projectile")

  data:extend{fhs, proj, shell, prom_proj, prom_shell, {
    type = "recipe", name = "awe-art-flash-hardened-steel", categories = {"metallurgy"}, enabled = false, energy_required = 19.2,
    allow_productivity = true, auto_recycle = false,
    ingredients = {
      {type = "fluid", name = "molten-iron", amount = 60, fluidbox_multiplier = 10},
      {type = "item", name = "carbon", amount = 2},
      {type = "item", name = "calcite", amount = 1},
      {type = "item", name = "ice", amount = 2},
    },
    results = {{type = "item", name = "awe-art-flash-hardened-steel", amount = 1}},
  }, {
    type = "recipe", name = "awe-art-steel-artillery-shell", categories = {"metallurgy"}, enabled = false, energy_required = 15,
    ingredients = {
      {type = "item", name = "awe-art-flash-hardened-steel", amount = 2},
      {type = "item", name = "explosives", amount = 8},
      {type = "item", name = "radar", amount = 1},
    },
    results = {{type = "item", name = "awe-art-steel-artillery-shell", amount = 1}},
  }, {
    type = "recipe", name = "awe-art-promethium-artillery-shell", categories = {"metallurgy"}, enabled = false, energy_required = 20,
    ingredients = {
      {type = "item", name = "awe-art-flash-hardened-steel", amount = 2},
      {type = "item", name = "promethium-asteroid-chunk", amount = 1},
      {type = "item", name = "explosives", amount = 8},
      {type = "item", name = "radar", amount = 1},
    },
    results = {{type = "item", name = "awe-art-promethium-artillery-shell", amount = 1}},
  }, {
    type = "technology", name = "awe-art-asteroid-ballistics",
    icon = gfx .. "technology/asteroid-ballistics.png",
    icon_size = 256,
    factoriopedia_description = {"factoriopedia-description.awe-art-asteroid-ballistics"},
    prerequisites = {"awe-art-targeting-computer"},
    effects = {
      {type = "nothing", effect_description = {"technology-effect.awe-art-asteroid-ballistics"}},
    },
    research_trigger = {
      type = "scripted",
      trigger_description = {"technology-trigger.awe-art-asteroid-ballistics"},
    },
  }, {
    type = "technology", name = "awe-art-steel-artillery-shell",
    icon = gfx .. "technology/steel-artillery-shell.png",
    icon_size = 256,
    factoriopedia_description = {"factoriopedia-description.awe-art-steel-artillery-shell"},
    prerequisites = {"awe-art-asteroid-ballistics", "advanced-asteroid-processing"},
    effects = {
      {type = "unlock-recipe", recipe = "awe-art-flash-hardened-steel"},
      {type = "unlock-recipe", recipe = "awe-art-steel-artillery-shell"},
    },
    unit = {count = 2000, time = 60, ingredients = {
      {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
      {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
    }},
  }, {
    type = "technology", name = "awe-art-promethium-ballistics",
    icon = gfx .. "technology/promethium-ballistics.png",
    icon_size = 256,
    factoriopedia_description = {"factoriopedia-description.awe-art-promethium-ballistics"},
    prerequisites = {"awe-art-steel-artillery-shell"},
    effects = {
      {type = "nothing", effect_description = {"technology-effect.awe-art-promethium-ballistics"}},
    },
    research_trigger = {
      type = "scripted",
      trigger_description = {"technology-trigger.awe-art-promethium-ballistics"},
    },
  }, {
    type = "technology", name = "awe-art-promethium-artillery-shell",
    icon = gfx .. "technology/promethium-artillery-shell.png",
    icon_size = 256,
    factoriopedia_description = {"factoriopedia-description.awe-art-promethium-artillery-shell"},
    prerequisites = {"awe-art-promethium-ballistics"},
    effects = {
      {type = "unlock-recipe", recipe = "awe-art-promethium-artillery-shell"},
    },
    unit = {count = 4000, time = 60, ingredients = {
      {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
      {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
      {"agricultural-science-pack", 1}, {"cryogenic-science-pack", 1},
    }},
  }}

  -- Artillery turret turning speed research (10 levels, +30% per level, starting at 2k). Factorio
  -- has no built-in technology modifier for turret_rotation_speed, so each level uses a hidden
  -- artillery-turret prototype fast-replaced on research/build (zero on_tick cost).
  local base_turret = data.raw["artillery-turret"]["artillery-turret"]
  base_turret.fast_replaceable_group = base_turret.fast_replaceable_group or "artillery-turret"
  for level = 1, 10 do
    local tr = table.deepcopy(base_turret)
    tr.name = "awe-art-artillery-turret-r" .. level
    tr.localised_name = {"entity-name.artillery-turret"}
    tr.localised_description = {"entity-description.artillery-turret"}
    tr.hidden = true
    tr.hidden_in_factoriopedia = true
    tr.factoriopedia_simulation = nil
    tr.placeable_by = {item = "artillery-turret", count = 1}
    tr.minable = base_turret.minable and {mining_time = base_turret.minable.mining_time, result = "artillery-turret"} or nil
    tr.turret_rotation_speed = base_turret.turret_rotation_speed * (1 + 0.3 * level)
    local ing = {
      {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
      {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
    }
    if level >= 4 then ing[#ing + 1] = {"cryogenic-science-pack", 1} end
    if level >= 7 then ing[#ing + 1] = {"promethium-science-pack", 1} end
    data:extend{tr, {
      type = "technology",
      name = "awe-art-artillery-rotation-" .. level,
      icons = {
        {icon = gfx .. "technology/artillery-rotation.png", icon_size = 256},
        {icon = "__core__/graphics/icons/technology/effect-constant/effect-constant-movement-speed.png", icon_size = 64, shift = {32, 32}},
      },
      factoriopedia_description = {"factoriopedia-description.awe-art-artillery-rotation"},
      prerequisites = {level == 1 and "awe-art-targeting-computer" or ("awe-art-artillery-rotation-" .. (level - 1))},
      effects = {{type = "nothing", effect_description = {"technology-effect.awe-art-artillery-rotation", "30"}}},
      unit = {count = 2000 * (2 ^ (level - 1)), time = 60, ingredients = ing},
      upgrade = true,
    }}
  end

  -- Artillery shell velocity research (infinite, +20% projectile flight speed per level, starting at 2k).
  data:extend{{
    type = "technology",
    name = "awe-art-artillery-shell-velocity-1",
    icons = {
      {icon = gfx .. "technology/artillery-shell-velocity.png", icon_size = 256},
      {icon = "__core__/graphics/icons/technology/effect-constant/effect-constant-movement-speed.png", icon_size = 64, shift = {32, 32}},
    },
    factoriopedia_description = {"factoriopedia-description.awe-art-artillery-shell-velocity"},
    prerequisites = {"awe-art-targeting-computer"},
    effects = {{type = "nothing", effect_description = {"technology-effect.awe-art-artillery-shell-velocity", "20"}}},
    unit = {
      count_formula = "2^(L-1)*2000",
      time = 60,
      ingredients = {
        {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"military-science-pack", 1},
        {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
        {"metallurgic-science-pack", 1}, {"electromagnetic-science-pack", 1},
      },
    },
    max_level = "infinite",
    upgrade = true,
  }}

  local tips = data.raw["tips-and-tricks-item"] or {}
  local parent = tips["asteroid-defense"] or tips["space-platform"]
  local cat = parent and parent.category or (data.raw["tips-and-tricks-item-category"]["space-platform"] and "space-platform") or nil
  local base_indent = parent and (parent.indent or 0) or 1
  local base_order = parent and (parent.order or "z") or "z[awesome-artillery]"

  local sim_space_artillery = {
    mods = {"awesome-artillery"},
    hide_factoriopedia_gradient = true,
    mute_wind_sounds = false,
    init = [[
      require("__core__/lualib/story")
      local player = game.simulation.create_test_player{name = "Spaceman"}
      local force = player.force
      force.set_ammo_damage_modifier("artillery-shell", 1.5)
      force.set_gun_speed_modifier("artillery-shell", 1.0)
      if force.technologies["awe-art-artillery-shell-velocity-1"] then force.technologies["awe-art-artillery-shell-velocity-1"].level = 5 end
      local platform = force.create_space_platform{name = "platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
      local hub = platform.apply_starter_pack()
      hub.destructible = false
      local s = platform.surface
      for x = -3, 3 do for y = -3, 2 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
      s.force_generate_chunk_requests()

      local tiles = {}
      for y = -18, 8 do
        local hw = y < -10 and math.floor((y + 20) * 1.4) or 14
        for x = -hw, hw do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
      end
      s.set_tiles(tiles)

      player.teleport({0, -10}, s)
      game.simulation.camera_player = player
      game.simulation.camera_position = {0, -34}
      game.simulation.camera_zoom = 0.42
      game.simulation.hide_cursor = true

      local function make(name, pos, dir)
        local e = s.create_entity{name = name, position = pos, force = force, raise_built = true, direction = dir or defines.direction.north}
        if not (e and e.valid) then
          e = s.find_entities_filtered{position = pos, radius = 1.5, force = force}[1]
        end
        if e and e.valid then e.destructible = false end
        return e
      end

      for _, x in pairs{-10.5, -7.5, 7.5, 10.5} do make("solar-panel", {x, -1.5}) end
      for _, x in pairs{-6, 6} do make("substation", {x, -6}) end
      local eei = make("electric-energy-interface", {0, 6})
      if eei then eei.power_production = 1e7; eei.electric_buffer_size = 1e7 end

      local t_steel = make("artillery-turret", {-6.5, -10.5})
      assert(t_steel, "t_steel nil")
      t_steel.insert{name = "awe-art-steel-artillery-shell", count = 15}
      local t_prom = make("artillery-turret", {6.5, -10.5})
      assert(t_prom, "t_prom nil")
      t_prom.insert{name = "awe-art-promethium-artillery-shell", count = 15}

      for _, pos in pairs{{-3, -15}, {3, -15}} do
        local g = make("gun-turret", pos)
        if g then g.insert{name = "piercing-rounds-magazine", count = 50} end
      end

      local comp = make("awe-art-targeting-computer", {0.5, -10.5})
      local cc = make("constant-combinator", {3.5, -10.5})
      if cc and comp then
        cc.get_wire_connector(defines.wire_connector_id.circuit_red, true)
          .connect_to(comp.get_wire_connector(defines.wire_connector_id.circuit_red, true))
      end

      local configured = false
      local wave = {
        {"medium-metallic-asteroid", -14, -56, 0.01, 0.045},
        {"medium-carbonic-asteroid", 12, -58, -0.01, 0.045},
        {"big-oxide-asteroid", 0, -60, 0.0, 0.035},
        {"huge-promethium-asteroid", 8, -62, -0.005, 0.03},
        {"medium-metallic-asteroid", 18, -55, -0.02, 0.045},
        {"big-metallic-asteroid", -8, -60, 0.01, 0.035},
      }
      local idx = 0
      local fallback_decoys = {}
      local function spawn_next()
        local has_mod = remote.interfaces["awesome-artillery"] ~= nil
        if has_mod and not configured then
          configured = true
          remote.call("awesome-artillery", "set_interval", 10)
          remote.call("awesome-artillery", "set_debug", true)
          if comp and comp.valid then
            remote.call("awesome-artillery", "set_computer_cfg", comp.unit_number, {
              sizes = {small = true, medium = true, big = true, huge = true},
              dir = 0, arc = 120, near = 30, far = 65,
            })
          end
        end
        if t_steel and t_steel.valid then t_steel.insert{name = "awe-art-steel-artillery-shell", count = 5} end
        if t_prom and t_prom.valid then t_prom.insert{name = "awe-art-promethium-artillery-shell", count = 5} end
        for _, a in pairs(s.find_entities_filtered{type = "asteroid"}) do
          if a.position.y > -20 or a.position.y < -75 or math.abs(a.position.x) > 45 then a.destroy() end
        end
        for k, pair in pairs(fallback_decoys) do
          if not (pair[1] and pair[1].valid) then
            if pair[2] and pair[2].valid then pair[2].destroy() end
            fallback_decoys[k] = nil
          end
        end
        idx = (idx % #wave) + 1
        local w = wave[idx]
        local a = s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
        if a and not has_mod then
          local d = s.create_entity{name = "awe-art-decoy-" .. w[1], position = {w[2] + w[4] * 16, w[3] + w[5] * 16}, force = "enemy"}
          fallback_decoys[#fallback_decoys + 1] = {a, d}
        end
      end
      local story_table = {{
        {name = "init", condition = story_elapsed_check(0.2), action = function() spawn_next() end},
        {name = "loop", condition = story_elapsed_check(1.8), action = function() spawn_next(); story_jump_to(storage.story, "loop") end},
      }}
      tip_story_init(story_table)
    ]],
  }

  local sim_fhs = {
    mods = {"awesome-artillery"},
    hide_factoriopedia_gradient = true,
    mute_wind_sounds = false,
    init = [[
      require("__core__/lualib/story")
      local player = game.simulation.create_test_player{name = "Spaceman"}
      local force = player.force
      for _, r in pairs{"awe-art-flash-hardened-steel", "awe-art-steel-artillery-shell", "awe-art-promethium-artillery-shell"} do
        if force.recipes[r] then force.recipes[r].enabled = true end
      end
      local platform = force.create_space_platform{name = "platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
      local hub = platform.apply_starter_pack()
      hub.destructible = false
      local s = platform.surface
      local tiles = {}
      for x = -12, 12 do
        for y = -14, 8 do
          tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}}
        end
      end
      s.set_tiles(tiles)

      player.teleport({0, -8}, s)
      game.simulation.camera_player = player
      game.simulation.camera_position = {0, -8.5}
      game.simulation.camera_zoom = 0.85
      game.simulation.hide_cursor = true

      local function make(name, pos, dir, recipe)
        local e = s.create_entity{name = name, position = pos, force = force, raise_built = true,
          direction = dir or defines.direction.north, recipe = recipe}
        if e then e.destructible = false end
        return e
      end

      make("substation", {-8, -8})
      make("substation", {8, -8})
      local eei = make("electric-energy-interface", {0, 6})
      if eei then eei.power_production = 1e7; eei.electric_buffer_size = 1e7 end

      local a_fhs = make("foundry", {-3.5, -8.5}, defines.direction.north, "awe-art-flash-hardened-steel")
      make("fast-inserter", {-0.5, -8.5}, defines.direction.west)
      local a_steel = make("foundry", {2.5, -8.5}, defines.direction.north, "awe-art-steel-artillery-shell")

      local function stock()
        if a_fhs and a_fhs.valid then
          a_fhs.insert_fluid{name = "molten-iron", amount = 500}
          a_fhs.insert{name = "carbon", count = 10}
          a_fhs.insert{name = "calcite", count = 10}
          a_fhs.insert{name = "ice", count = 10}
        end
        if a_steel and a_steel.valid then
          a_steel.insert{name = "awe-art-flash-hardened-steel", count = 6}
          a_steel.insert{name = "explosives", count = 20}
          a_steel.insert{name = "radar", count = 5}
        end
      end
      stock()
      local story_table = {{
        {name = "loop", condition = story_elapsed_check(2.0), action = function() stock(); story_jump_to(storage.story, "loop") end},
      }}
      tip_story_init(story_table)
    ]],
  }

  local sim_steel_shell = {
    mods = {"awesome-artillery"},
    hide_factoriopedia_gradient = true,
    mute_wind_sounds = false,
    init = [[
      require("__core__/lualib/story")
      local player = game.simulation.create_test_player{name = "Spaceman"}
      local force = player.force
      force.set_gun_speed_modifier("artillery-shell", 1.0)
      if force.technologies["awe-art-artillery-shell-velocity-1"] then force.technologies["awe-art-artillery-shell-velocity-1"].level = 5 end
      for _, r in pairs{"advanced-metallic-asteroid-crushing", "advanced-carbonic-asteroid-crushing",
        "advanced-oxide-asteroid-crushing", "ice-melting", "coal-synthesis", "explosives",
        "awe-art-flash-hardened-steel", "awe-art-steel-artillery-shell"} do
        if force.recipes[r] then force.recipes[r].enabled = true end
      end

      local platform = force.create_space_platform{name = "platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
      local hub = platform.apply_starter_pack()
      hub.destructible = false
      local s = platform.surface
      for x = -3, 3 do for y = -3, 2 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
      s.force_generate_chunk_requests()

      local tiles = {}
      for y = -18, 10 do
        local hw = y < -12 and math.floor((y + 20) * 1.6) or 14
        for x = -hw, hw do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
      end
      s.set_tiles(tiles)

      player.teleport({0, -10}, s)
      game.simulation.camera_player = player
      game.simulation.camera_position = {0, -26}
      game.simulation.camera_zoom = 0.45
      game.simulation.hide_cursor = true

      local function make(name, pos, dir, recipe)
        local e = s.create_entity{name = name, position = pos, force = force, raise_built = true,
          direction = dir or defines.direction.north, recipe = recipe}
        if not (e and e.valid) then
          e = s.find_entities_filtered{position = pos, radius = 1.5, force = force}[1]
        end
        if e and e.valid then e.destructible = false end
        return e
      end

      for _, pos in pairs{{-6, -6}, {9, -6}, {-6, 5}, {9, 5}} do make("substation", pos) end
      for _, x in pairs{-10.5, 10.5} do make("solar-panel", {x, -1.5}); make("solar-panel", {x, 1.5}) end
      local eei = make("electric-energy-interface", {0, 8})
      if eei then eei.power_production = 1e7; eei.electric_buffer_size = 1e7 end

      make("crusher", {-9, -7.5}, defines.direction.south, "advanced-metallic-asteroid-crushing")
      make("crusher", {-9, -2.5}, defines.direction.south, "advanced-carbonic-asteroid-crushing")
      make("crusher", {-9, 2.5}, defines.direction.south, "advanced-oxide-asteroid-crushing")
      make("chemical-plant", {-5.5, -2.5}, defines.direction.east, "coal-synthesis")
      make("chemical-plant", {-5.5, 2.5}, defines.direction.east, "explosives")

      local a_fhs = make("foundry", {-1.5, -7.5}, defines.direction.north, "awe-art-flash-hardened-steel")
      local a_sh = make("foundry", {4.5, -7.5}, defines.direction.north, "awe-art-steel-artillery-shell")
      assert(a_fhs and a_sh, "foundry nil in sim_steel_shell")
      make("fast-inserter", {1.5, -7.5}, defines.direction.west)
      make("fast-inserter", {4.5, -10.5}, defines.direction.south)

      local turret = make("artillery-turret", {4.5, -12.5})
      assert(turret, "turret nil in sim_steel_shell")
      turret.insert{name = "awe-art-steel-artillery-shell", count = 10}
      make("awe-art-targeting-computer", {-1.5, -12.5})
      for _, x in pairs{-6, 0, 8} do
        local g = make("gun-turret", {x, -16})
        if g then g.insert{name = "piercing-rounds-magazine", count = 50} end
      end

      local configured = false
      local function stock_craft()
        if remote.interfaces["awesome-artillery"] and not configured then
          configured = true
          remote.call("awesome-artillery", "set_interval", 10)
        end
        if a_fhs and a_fhs.valid then
          a_fhs.insert_fluid{name = "molten-iron", amount = 500}
          a_fhs.insert{name = "carbon", count = 10}
          a_fhs.insert{name = "calcite", count = 10}
          a_fhs.insert{name = "ice", count = 10}
        end
        if a_sh and a_sh.valid then
          a_sh.insert{name = "awe-art-flash-hardened-steel", count = 6}
          a_sh.insert{name = "explosives", count = 20}
          a_sh.insert{name = "radar", count = 5}
        end
        if turret and turret.valid then turret.insert{name = "awe-art-steel-artillery-shell", count = 5} end
      end
      stock_craft()

      local wave = {
        {"medium-metallic-asteroid", -8, -46, 0.01, 0.04},
        {"medium-oxide-asteroid", 10, -48, -0.01, 0.04},
        {"medium-carbonic-asteroid", 2, -47, 0.0, 0.04},
      }
      local idx = 0
      local fallback_decoys = {}
      local function step()
        stock_craft()
        for k, pair in pairs(fallback_decoys) do
          if not (pair[1] and pair[1].valid) then
            if pair[2] and pair[2].valid then pair[2].destroy() end
            fallback_decoys[k] = nil
          end
        end
        idx = (idx % #wave) + 1
        local w = wave[idx]
        local a = s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
        if a and not remote.interfaces["awesome-artillery"] then
          local d = s.create_entity{name = "awe-art-decoy-" .. w[1], position = {w[2] + w[4] * 16, w[3] + w[5] * 16}, force = "enemy"}
          fallback_decoys[#fallback_decoys + 1] = {a, d}
        end
      end
      local story_table = {{
        {name = "init", condition = story_elapsed_check(0.2), action = function() step() end},
        {name = "loop", condition = story_elapsed_check(2.0), action = function() step(); story_jump_to(storage.story, "loop") end},
      }}
      tip_story_init(story_table)
    ]],
  }

  local sim_promethium_shell = {
    mods = {"awesome-artillery"},
    hide_factoriopedia_gradient = true,
    mute_wind_sounds = false,
    init = [[
      require("__core__/lualib/story")
      local player = game.simulation.create_test_player{name = "Spaceman"}
      local force = player.force
      force.set_ammo_damage_modifier("artillery-shell", 1.5)
      force.set_gun_speed_modifier("artillery-shell", 1.2)
      if force.technologies["awe-art-artillery-shell-velocity-1"] then force.technologies["awe-art-artillery-shell-velocity-1"].level = 6 end
      for _, r in pairs{"awe-art-flash-hardened-steel", "awe-art-promethium-artillery-shell"} do
        if force.recipes[r] then force.recipes[r].enabled = true end
      end

      local platform = force.create_space_platform{name = "platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
      local hub = platform.apply_starter_pack()
      hub.destructible = false
      local s = platform.surface
      for x = -3, 3 do for y = -3, 2 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
      s.force_generate_chunk_requests()

      local tiles = {}
      for y = -18, 8 do
        local hw = y < -10 and math.floor((y + 20) * 1.5) or 14
        for x = -hw, hw do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
      end
      s.set_tiles(tiles)

      player.teleport({0, -10}, s)
      game.simulation.camera_player = player
      game.simulation.camera_position = {0, -32}
      game.simulation.camera_zoom = 0.42
      game.simulation.hide_cursor = true

      local function make(name, pos, dir, recipe)
        local e = s.create_entity{name = name, position = pos, force = force, raise_built = true,
          direction = dir or defines.direction.north, recipe = recipe}
        if not (e and e.valid) then
          e = s.find_entities_filtered{position = pos, radius = 1.5, force = force}[1]
        end
        if e and e.valid then e.destructible = false end
        return e
      end

      for _, pos in pairs{{-8, -7}, {8, -7}, {-8, 5}, {8, 5}} do make("substation", pos) end
      local eei = make("electric-energy-interface", {0, 6})
      if eei then eei.power_production = 1e8; eei.electric_buffer_size = 1e8 end

      local a_fhs = make("foundry", {-3.5, -7.5}, defines.direction.north, "awe-art-flash-hardened-steel")
      local a_prom = make("foundry", {2.5, -7.5}, defines.direction.north, "awe-art-promethium-artillery-shell")
      make("fast-inserter", {-0.5, -7.5}, defines.direction.west)

      local turrets = {
        make("artillery-turret", {-6.5, -12.5}),
        make("artillery-turret", {6.5, -12.5}),
      }
      for _, t in pairs(turrets) do
        if t and t.valid then t.insert{name = "awe-art-promethium-artillery-shell", count = 15} end
      end
      local comp = make("awe-art-targeting-computer", {0, -12.5})

      local configured = false
      local wave = {
        {"huge-promethium-asteroid", -8, -56, 0.005, 0.03},
        {"huge-metallic-asteroid", 10, -58, -0.005, 0.03},
        {"big-promethium-asteroid", 0, -54, 0.0, 0.04},
        {"huge-oxide-asteroid", -12, -56, 0.01, 0.03},
      }
      local idx = 0
      local fallback_decoys = {}
      local function step()
        local has_mod = remote.interfaces["awesome-artillery"] ~= nil
        if has_mod and not configured then
          configured = true
          remote.call("awesome-artillery", "set_interval", 10)
          if comp and comp.valid then
            remote.call("awesome-artillery", "set_computer_cfg", comp.unit_number, {
              sizes = {small = true, medium = true, big = true, huge = true},
              dir = 0, arc = 120, near = 30, far = 65,
            })
          end
        end
        if a_fhs and a_fhs.valid then
          a_fhs.insert_fluid{name = "molten-iron", amount = 500}
          a_fhs.insert{name = "carbon", count = 10}
          a_fhs.insert{name = "calcite", count = 10}
          a_fhs.insert{name = "ice", count = 10}
        end
        if a_prom and a_prom.valid then
          a_prom.insert{name = "awe-art-flash-hardened-steel", count = 6}
          a_prom.insert{name = "promethium-asteroid-chunk", count = 6}
          a_prom.insert{name = "explosives", count = 20}
          a_prom.insert{name = "radar", count = 5}
        end
        for _, t in pairs(turrets) do
          if t and t.valid then t.insert{name = "awe-art-promethium-artillery-shell", count = 5} end
        end
        for _, a in pairs(s.find_entities_filtered{type = "asteroid"}) do
          if a.position.y > -20 or a.position.y < -75 or math.abs(a.position.x) > 45 then a.destroy() end
        end
        for k, pair in pairs(fallback_decoys) do
          if not (pair[1] and pair[1].valid) then
            if pair[2] and pair[2].valid then pair[2].destroy() end
            fallback_decoys[k] = nil
          end
        end
        idx = (idx % #wave) + 1
        local w = wave[idx]
        local a = s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
        if a and not has_mod then
          local d = s.create_entity{name = "awe-art-decoy-" .. w[1], position = {w[2] + w[4] * 16, w[3] + w[5] * 16}, force = "enemy"}
          fallback_decoys[#fallback_decoys + 1] = {a, d}
        end
      end
      local story_table = {{
        {name = "init", condition = story_elapsed_check(0.2), action = function() step() end},
        {name = "loop", condition = story_elapsed_check(2.2), action = function() step(); story_jump_to(storage.story, "loop") end},
      }}
      tip_story_init(story_table)
    ]],
  }

  c.factoriopedia_simulation = sim_space_artillery
  item.factoriopedia_simulation = sim_space_artillery
  fhs.factoriopedia_simulation = sim_fhs
  shell.factoriopedia_simulation = sim_steel_shell
  prom_shell.factoriopedia_simulation = sim_promethium_shell

  data:extend{
    {
      type = "tips-and-tricks-item",
      name = "awe-art-space-artillery",
      category = cat,
      indent = base_indent,
      order = base_order .. "-z[awe-art-a]",
      tag = "[entity=awe-art-targeting-computer]",
      dependencies = parent and {parent.name} or nil,
      trigger = {type = "research", technology = "awe-art-targeting-computer"},
      simulation = sim_space_artillery,
    },
    {
      type = "tips-and-tricks-item",
      name = "awe-art-steel-artillery-shell",
      category = cat,
      indent = base_indent + 1,
      order = base_order .. "-z[awe-art-b]",
      tag = "[item=awe-art-steel-artillery-shell]",
      dependencies = {"awe-art-space-artillery"},
      trigger = {type = "research", technology = "awe-art-targeting-computer"},
      simulation = sim_steel_shell,
    },
    {
      type = "tips-and-tricks-item",
      name = "awe-art-promethium-artillery-shell",
      category = cat,
      indent = base_indent + 1,
      order = base_order .. "-z[awe-art-c]",
      tag = "[item=awe-art-promethium-artillery-shell]",
      dependencies = {"awe-art-steel-artillery-shell"},
      trigger = {type = "research", technology = "awe-art-promethium-ballistics"},
      simulation = sim_promethium_shell,
    },
  }
  data:extend{{type = "mod-data", name = "awe-art-sims", data = {
    space = sim_space_artillery.init,
    fhs = sim_fhs.init,
    steel = sim_steel_shell.init,
    prom = sim_promethium_shell.init,
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
  data:extend{{type = "mod-data", name = "awe-art-asteroids", data = catalogue}}
end

-- Every other turret ignores decoys (verified: without this, rocket turrets shoot them).
for _, type in pairs{"ammo-turret", "electric-turret", "fluid-turret", "turret"} do
  for _, t in pairs(data.raw[type] or {}) do
    t.ignore_target_mask = t.ignore_target_mask or {}
    table.insert(t.ignore_target_mask, "awe-art-decoy")
  end
end
