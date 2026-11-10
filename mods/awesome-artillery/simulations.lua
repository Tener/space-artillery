-- Factoriopedia and Tips & Tricks simulations. Each one's init script is COMMON (the helpers
-- every scene uses) followed by its own scene.

local COMMON = [[
  require("__core__/lualib/story")
  local player = game.simulation.create_test_player{name = "Spaceman"}
  local force = player.force
  local s
  local FHS = "awe-art-flash-hardened-steel"
  local STEEL, PROM = "awe-art-steel-artillery-shell", "awe-art-promethium-artillery-shell"
  local SHELL_INPUTS = {[FHS] = 6, explosives = 20, radar = 5}

  local function research(damage, speed, velocity)
    force.set_ammo_damage_modifier("artillery-shell", damage)
    force.set_gun_speed_modifier("artillery-shell", speed)
    local tech = force.technologies["awe-art-artillery-shell-velocity-1"]
    if tech then tech.level = velocity end
  end

  local function enable_recipes(names)
    for _, r in pairs(names) do
      if force.recipes[r] then force.recipes[r].enabled = true end
    end
  end

  -- Foundation rows y1..y2, each half_width(y) tiles to either side of x = 0.
  -- far: also generate the chunks asteroids approach through.
  local function build_platform(y1, y2, half_width, far)
    local platform = force.create_space_platform{name = "platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
    local hub = platform.apply_starter_pack()
    hub.destructible = false
    s = platform.surface
    if far then
      for x = -3, 3 do for y = -3, 2 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
      s.force_generate_chunk_requests()
    end
    local tiles = {}
    for y = y1, y2 do
      local hw = half_width(y)
      for x = -hw, hw do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
    end
    s.set_tiles(tiles)
  end

  local function camera(player_position, position, zoom, alt_info)
    player.teleport(player_position, s)
    game.simulation.camera_player = player
    game.simulation.camera_position = position
    game.simulation.camera_zoom = zoom
    if alt_info then game.simulation.camera_alt_info = true end
    game.simulation.hide_cursor = true
  end

  local function make(name, pos, dir, recipe)
    local e = s.create_entity{name = name, position = pos, force = force, raise_built = true,
      direction = dir or defines.direction.north, recipe = recipe}
    if not (e and e.valid) then
      e = s.find_entities_filtered{position = pos, radius = 1.5, force = force}[1]
    end
    if e and e.valid then e.destructible = false end
    return e
  end

  local function power(watts)
    local eei = make("electric-energy-interface", {0, 6})
    if eei then eei.power_production = watts; eei.electric_buffer_size = watts end
  end

  local function wire(a, b)
    if not (a and b) then return end
    local red = defines.wire_connector_id.circuit_red
    a.get_wire_connector(red, true).connect_to(b.get_wire_connector(red, true), false)
  end

  local function stock(e, items)
    if not (e and e.valid) then return end
    for name, count in pairs(items) do e.insert{name = name, count = count} end
  end

  local function stock_fhs(foundry, pipe)
    if foundry and foundry.valid then foundry.insert_fluid{name = "molten-iron", amount = 500} end
    stock(foundry, {carbon = 10, calcite = 10, ice = 10})
    if pipe and pipe.valid then pipe.insert_fluid{name = "molten-iron", amount = 100} end
  end

  -- The mod's own script starts after this one, so the computer is set up on the first step.
  local configured = false
  local function configure(comp)
    if configured or not remote.interfaces["awesome-artillery"] then return end
    configured = true
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    if comp and comp.valid then
      remote.call("awesome-artillery", "set_computer_cfg", comp.unit_number, {
        sizes = {small = false, medium = true, big = true, huge = true},
        dir = 0, arc = 120, near = 30, far = 56,
      })
    end
  end

  -- Removes asteroids that left the scene and spawns the wave's next one: {name, x, y, vx, vy}.
  local wave_index = 0
  local function spawn_next(wave)
    for _, a in pairs(s.find_entities_filtered{type = "asteroid"}) do
      if a.position.y > -15 or a.position.y < -75 or math.abs(a.position.x) > 35 then a.destroy() end
    end
    wave_index = (wave_index % #wave) + 1
    local w = wave[wave_index]
    s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
  end

  -- Runs step every period seconds, the first time after first seconds if given.
  local function run(step, period, first)
    local nodes = {}
    if first then nodes[1] = {name = "init", condition = story_elapsed_check(first), action = function() step() end} end
    nodes[#nodes + 1] = {name = "loop", condition = story_elapsed_check(period),
      action = function() step(); story_jump_to(storage.story, "loop") end}
    tip_story_init({nodes})
  end
]]

local function simulation(scene)
  return {
    mods = {"awesome-artillery"},
    hide_factoriopedia_gradient = true,
    mute_wind_sounds = false,
    init = COMMON .. scene,
  }
end

local M = {}

M.space = simulation[[
  research(1.5, 1.0, 5)
  build_platform(-18, 8, function(y) return y < -10 and math.floor((y + 20) * 1.4) or 14 end, true)
  camera({0, -10}, {0, -28}, 0.54)
  power(1e7)

  local t_steel = make("artillery-turret", {-6.5, -10.5})
  assert(t_steel, "t_steel nil")
  stock(t_steel, {[STEEL] = 15})
  local chest_steel = make("requester-chest", {-6.5, -7.5})
  stock(chest_steel, {[STEEL] = 30})
  make("fast-inserter", {-6.5, -8.5}, defines.direction.south)

  local t_prom = make("artillery-turret", {6.5, -10.5})
  assert(t_prom, "t_prom nil")
  stock(t_prom, {[PROM] = 15})
  local chest_prom = make("requester-chest", {6.5, -7.5})
  stock(chest_prom, {[PROM] = 30})
  make("fast-inserter", {6.5, -8.5}, defines.direction.south)

  for _, pos in pairs{{-3, -15}, {3, -15}} do
    stock(make("gun-turret", pos), {["piercing-rounds-magazine"] = 50})
  end

  local comp = make("awe-art-targeting-computer", {0.5, -10.5})
  wire(make("constant-combinator", {3.5, -10.5}), comp)
  wire(comp, t_steel)
  wire(comp, t_prom)

  local wave = {
    {"medium-metallic-asteroid", -10, -56, 0.01, 0.035},
    {"small-metallic-asteroid", 2, -52, 0.0, 0.04},
    {"medium-carbonic-asteroid", 8, -58, -0.01, 0.035},
    {"big-oxide-asteroid", 0, -60, 0.0, 0.03},
    {"huge-promethium-asteroid", 6, -62, -0.005, 0.025},
    {"small-oxide-asteroid", -3, -54, 0.002, 0.04},
    {"medium-metallic-asteroid", 12, -56, -0.02, 0.035},
    {"big-metallic-asteroid", -6, -60, 0.01, 0.03},
  }
  run(function()
    configure(comp)
    stock(t_steel, {[STEEL] = 5})
    stock(t_prom, {[PROM] = 5})
    stock(chest_steel, {[STEEL] = 5})
    stock(chest_prom, {[PROM] = 5})
    spawn_next(wave)
  end, 1.8, 0.2)
]]

M.fhs = simulation[[
  enable_recipes{FHS, STEEL, PROM}
  build_platform(-14, 8, function() return 12 end)
  camera({0, -8}, {0, -8.5}, 0.85, true)
  power(1e7)

  local a_fhs = make("foundry", {-3.5, -8.5}, nil, FHS)
  local a_steel = make("foundry", {2.5, -8.5}, nil, STEEL)
  make("fast-inserter", {-0.5, -8.5}, defines.direction.west)

  local pipe = make("pipe", {-4.5, -6.5})
  make("pipe", {-4.5, -5.5})

  local function step()
    stock_fhs(a_fhs, pipe)
    stock(a_steel, SHELL_INPUTS)
  end
  step()
  run(step, 2.0)
]]

M.steel = simulation[[
  research(2.5, 1.2, 5)
  enable_recipes{"advanced-metallic-asteroid-crushing", "advanced-carbonic-asteroid-crushing",
    "advanced-oxide-asteroid-crushing", FHS, STEEL}
  build_platform(-20, 8, function(y) return y < -12 and math.floor((y + 22) * 1.5) or 15 end, true)
  camera({0, -10}, {0, -26}, 0.54, true)
  power(1e8)

  -- Left cannon: Tungsten artillery shells (imported)
  local turret_tungsten = make("artillery-turret", {-7.5, -12.5})
  assert(turret_tungsten, "turret_tungsten nil")
  stock(turret_tungsten, {["artillery-shell"] = 15})

  local chest_tungsten = make("requester-chest", {-7.5, -9.5})
  if chest_tungsten then
    stock(chest_tungsten, {["artillery-shell"] = 30})
    local lp = chest_tungsten.get_requester_point()
    if lp and lp.sections_count > 0 then
      lp.get_section(1).set_slot(1, {value = "artillery-shell", min = 30})
    end
  end
  -- Inserter picks up from South (chest at -9.5), drops into North (turret at -12.5)
  make("fast-inserter", {-7.5, -10.5}, defines.direction.south)

  -- Right cannon: Steel artillery shells (cast on platform)
  local turret_steel = make("artillery-turret", {7.5, -12.5})
  assert(turret_steel, "turret_steel nil")
  stock(turret_steel, {[STEEL] = 15})

  -- Shell Foundry (casts awe-art-steel-artillery-shell)
  local a_sh = make("foundry", {7.5, -6.5}, nil, STEEL)
  assert(a_sh, "a_sh nil")
  -- Inserter picks up from South (foundry at -6.5), drops into North (turret at -12.5)
  make("fast-inserter", {7.5, -10.5}, defines.direction.south)

  stock(make("requester-chest", {11.5, -6.5}), {explosives = 100, radar = 20})
  -- Inserter picks up from East (chest at 11.5), drops into West (foundry at 7.5)
  make("fast-inserter", {10.5, -6.5}, defines.direction.east)

  -- FHS Foundry (casts awe-art-flash-hardened-steel from molten iron + asteroid carbon/calcite/ice)
  local a_fhs = make("foundry", {1.5, -6.5}, nil, FHS)
  assert(a_fhs, "a_fhs nil")
  -- Inserter picks up from West (FHS foundry at 1.5), drops into East (Shell foundry at 7.5)
  make("fast-inserter", {4.5, -6.5}, defines.direction.west)

  stock(make("requester-chest", {1.5, -3.0}), {carbon = 50, calcite = 50, ice = 50})
  -- Inserter picks up from South (chest at -3.0), drops into North (foundry at -6.5)
  make("fast-inserter", {1.5, -4.0}, defines.direction.south)

  -- Molten iron pipe supply into a_fhs fluid port at x=0.5, y=-4.5
  local pipe = make("pipe", {0.5, -4.5})
  make("pipe", {0.5, -3.5})

  -- Targeting Computer between cannons, wired to both
  local comp = make("awe-art-targeting-computer", {0, -12.5})
  wire(comp, turret_steel)
  wire(comp, turret_tungsten)

  local function stock_craft()
    configure(comp)
    stock_fhs(a_fhs, pipe)
    stock(a_sh, SHELL_INPUTS)
    stock(turret_steel, {[STEEL] = 5})
    stock(turret_tungsten, {["artillery-shell"] = 5})
    stock(chest_tungsten, {["artillery-shell"] = 5})
  end
  stock_craft()

  local wave = {
    {"medium-metallic-asteroid", 6, -56, -0.005, 0.035},
    {"small-metallic-asteroid", 2, -52, 0.0, 0.04},
    {"big-carbonic-asteroid", -8, -60, 0.01, 0.035},
    {"huge-metallic-asteroid", 3, -62, -0.002, 0.025},
    {"small-oxide-asteroid", -2, -53, 0.002, 0.04},
    {"medium-oxide-asteroid", -5, -57, 0.005, 0.035},
    {"big-metallic-asteroid", 8, -60, -0.008, 0.035},
  }
  run(function()
    stock_craft()
    spawn_next(wave)
  end, 1.8, 0.2)
]]

M.prom = simulation[[
  research(1.5, 1.2, 6)
  enable_recipes{FHS, PROM}
  build_platform(-18, 8, function(y) return y < -10 and math.floor((y + 20) * 1.5) or 14 end, true)
  camera({0, -10}, {0, -26}, 0.54, true)
  power(1e8)

  local a_fhs = make("foundry", {1.5, -6.5}, nil, FHS)
  local a_prom = make("foundry", {7.5, -6.5}, nil, PROM)
  -- Inserter picks up from West (FHS foundry at 1.5), drops into East (Promethium foundry at 7.5)
  make("fast-inserter", {4.5, -6.5}, defines.direction.west)
  -- Inserter picks up from South (Promethium foundry at -6.5), drops into North (turret at -12.5)
  make("fast-inserter", {7.5, -10.5}, defines.direction.south)

  stock(make("requester-chest", {1.5, -3.0}), {carbon = 50, calcite = 50, ice = 50})
  -- Inserter picks up from South (chest at -3.0), drops into North (foundry at -6.5)
  make("fast-inserter", {1.5, -4.0}, defines.direction.south)

  stock(make("requester-chest", {11.5, -6.5}), {["promethium-asteroid-chunk"] = 50, explosives = 100, radar = 20})
  -- Inserter picks up from East (chest at 11.5), drops into West (foundry at 7.5)
  make("fast-inserter", {10.5, -6.5}, defines.direction.east)

  local pipe = make("pipe", {0.5, -4.5})
  make("pipe", {0.5, -3.5})

  local turrets = {
    make("artillery-turret", {-7.5, -12.5}),
    make("artillery-turret", {7.5, -12.5}),
  }
  for _, t in pairs(turrets) do stock(t, {[PROM] = 15}) end

  stock(make("requester-chest", {-7.5, -9.5}), {[PROM] = 30})
  -- Inserter picks up from South (chest at -9.5), drops into North (turret at -12.5)
  make("fast-inserter", {-7.5, -10.5}, defines.direction.south)

  local comp = make("awe-art-targeting-computer", {0, -12.5})
  wire(comp, turrets[1])
  wire(comp, turrets[2])

  local wave = {
    {"huge-promethium-asteroid", -6, -62, 0.005, 0.025},
    {"small-metallic-asteroid", 2, -52, 0.0, 0.04},
    {"huge-metallic-asteroid", 7, -62, -0.005, 0.025},
    {"big-promethium-asteroid", 0, -58, 0.0, 0.03},
    {"small-oxide-asteroid", -3, -53, 0.002, 0.04},
    {"huge-oxide-asteroid", -8, -62, 0.008, 0.025},
  }
  run(function()
    configure(comp)
    stock_fhs(a_fhs, pipe)
    stock(a_prom, SHELL_INPUTS)
    stock(a_prom, {["promethium-asteroid-chunk"] = 6})
    for _, t in pairs(turrets) do stock(t, {[PROM] = 5}) end
    spawn_next(wave)
  end, 2.2, 0.2)
]]

return M
