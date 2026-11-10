-- Factoriopedia and Tips & Tricks simulations. COMMON runs before each scene.

local COMMON = [[
  require("__core__/lualib/story")
  local player = game.simulation.create_test_player{name = "Spaceman"}
  local force = player.force
  local FHS = "space-art-flash-hardened-steel"
  local STEEL = "space-art-steel-artillery-shell"
  local PROM = "space-art-promethium-artillery-shell"
  local COMPUTER = "space-art-targeting-computer"
  local s

  local function make(name, position, direction, recipe)
    local entity = s.create_entity{
      name = name, position = position, force = force, raise_built = true,
      direction = direction or defines.direction.north, recipe = recipe,
    }
    -- Rotation research can replace the turret during the built event.
    if name == "artillery-turret" and not (entity and entity.valid) then
      entity = s.find_entities_filtered{position = position, radius = 0.5, type = name, force = force, limit = 1}[1]
    end
    assert(entity and entity.valid, "could not place " .. name)
    entity.destructible = false
    return entity
  end

  local function build_platform(bow, width)
    local platform = force.create_space_platform{
      name = "Artillery demonstration", planet = "nauvis", starter_pack = "space-platform-starter-pack",
    }
    platform.apply_starter_pack().destructible = false
    platform.paused = true
    s = platform.surface
    s.request_to_generate_chunks({0, -32}, 3)
    s.force_generate_chunk_requests()
    local tiles = {}
    for y = bow, 7 do
      local half_width = math.min(width, 7 + y - bow)
      for x = -half_width, half_width do
        tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}}
      end
    end
    s.set_tiles(tiles)

    make("substation", {0, -6})
    local power = make("electric-energy-interface", {6.5, -3.5})
    power.power_production = 25e6
    power.electric_buffer_size = 25e6
  end

  local function camera(position, zoom, alt_info)
    player.teleport({0, 0}, s)
    game.simulation.camera_player = player
    game.simulation.camera_surface_index = s.index
    game.simulation.camera_position = position
    game.simulation.camera_zoom = zoom
    game.simulation.camera_alt_info = alt_info or false
    game.simulation.hide_cursor = true
  end

  local function stock(entity, items)
    for name, count in pairs(items) do
      local missing = count - entity.get_item_count(name)
      if missing > 0 then entity.insert{name = name, count = missing} end
    end
  end

  local function research(damage)
    force.set_ammo_damage_modifier("artillery-shell", damage)
    force.set_gun_speed_modifier("artillery-shell", 1)
    force.technologies["space-art-artillery-shell-velocity-1"].level = 3
  end

  local function configure(computer, cfg, debug_overlay)
    cfg.sizes = cfg.sizes or {medium = true, big = true, huge = true}
    cfg.near, cfg.far = 24, 52
    remote.call("space-artillery", "set_interval", 10)
    remote.call("space-artillery", "set_computer_cfg", computer.unit_number, cfg)
    remote.call("space-artillery", "set_debug", debug_overlay)
  end

  -- The first story point must be the jump destination. Jumping back to the
  -- current point would advance past it instead of restarting its timer.
  local function run(step, period, update)
    tip_story_init({{
      {name = "start", action = step},
      {update = update, condition = story_elapsed_check(period),
        action = function() story_jump_to(storage.story, "start") end},
    }})
  end

  local function spawn(name, x, y, vx, vy)
    return s.create_entity{name = name, position = {x, y}, velocity = {vx, vy}, force = "enemy"}
  end

  local function steel_foundry()
    force.recipes[FHS].enabled = true
    make("foundry", {-3.5, -11.5}, defines.direction.south, FHS)
    local inputs = make("steel-chest", {-7.5, -11.5})
    make("bulk-inserter", {-6.5, -11.5}, defines.direction.west)
    local iron = make("pipe", {-4.5, -14.5})
    make("pipe", {-4.5, -15.5})
    return function()
      stock(inputs, {carbon = 25, calcite = 25, ice = 25})
      iron.insert_fluid{name = "molten-iron", amount = 100}
    end
  end
]]

local function simulation(scene, warmup)
  return {
    mods = {"space-artillery"},
    hide_factoriopedia_gradient = true,
    mute_wind_sounds = false,
    init_update_count = warmup,
    init = COMMON .. scene,
  }
end

local M = {}

M.space = simulation([[
  build_platform(-16, 11)
  camera({25, 0}, 0.34)
  research(0.3)
  local computer = make(COMPUTER, {6.5, 0.5})
  local upper = make("artillery-turret", {8.5, -7.5}, defines.direction.east)
  local lower = make("artillery-turret", {8.5, 5.5}, defines.direction.east)

  local configured, side = false, 1
  run(function()
    if not configured then
      configure(computer, {dir = 90, arc = 22}, true)
      configured = true
    end
    stock(upper, {["artillery-shell"] = 5})
    stock(lower, {["artillery-shell"] = 5})
    for _, a in pairs(s.find_entities_filtered{type = "asteroid"}) do
      if a.position.x < 30 then a.destroy() end
    end
    spawn("medium-metallic-asteroid", 46, side * 4, -0.08, 0)
    spawn("medium-oxide-asteroid", 44, side * 10, -0.12, 0)
    side = -side
  end, 2.6)
]], 45)

M.fhs = simulation([[
  build_platform(-17, 10)
  camera({-3.5, -11.5}, 1.15, true)
  local feed = steel_foundry()
  make("bulk-inserter", {-0.5, -11.5}, defines.direction.west)
  make("steel-chest", {0.5, -11.5})
  run(feed, 1)
]], 240)

M.steel = simulation([[
  build_platform(-21, 11)
  camera({0, -12.5}, 0.82, true)
  research(0.3)
  local feed = steel_foundry()
  force.recipes[STEEL].enabled = true
  make("foundry", {2.5, -11.5}, nil, STEEL)
  make("bulk-inserter", {-0.5, -11.5}, defines.direction.west)
  local inputs = make("steel-chest", {6.5, -11.5})
  make("bulk-inserter", {5.5, -11.5}, defines.direction.east)
  local cannon = make("artillery-turret", {2.5, -16.5})
  make("bulk-inserter", {2.5, -14.5}, defines.direction.south)
  local computer = make(COMPUTER, {-5.5, -5.5})

  local configured, target = false, nil
  run(function()
    if not configured then
      configure(computer, {dir = 0, arc = 100}, false)
      configured = true
    end
    feed()
    stock(inputs, {explosives = 40, radar = 10})
    if target and target.valid and target.position.y > -24 then target.destroy() end
    if cannon.get_item_count(STEEL) > 0 and not (target and target.valid) then
      target = spawn("medium-metallic-asteroid", 0, -57, 0, 0.06)
    end
  end, 1)
]], 900)

M.prom = simulation([[
  build_platform(-21, 11)
  local home = {0, -17.5}
  camera(home, 0.75, true)
  research(1.5)
  local computer = make(COMPUTER, {0.5, -12.5})
  local left = make("artillery-turret", {-4.5, -16.5})
  local right = make("artillery-turret", {4.5, -16.5})

  local configured, target, side = false, nil, 1
  local shell, last_position, hold_until
  local function follow(event)
    if not shell then
      shell = s.find_entities_filtered{name = "space-art-promethium-artillery-projectile", limit = 1}[1]
    end
    if shell and shell.valid then
      last_position = shell.position
      hold_until = event.tick + 65
      game.simulation.camera_position = last_position
    elseif hold_until then
      local t = math.max(0, math.min(1, (event.tick - hold_until) / 30))
      game.simulation.camera_position = {
        last_position.x * (1 - t),
        last_position.y + (home[2] - last_position.y) * t,
      }
    end
  end

  run(function()
    if not configured then
      configure(computer, {dir = 0, arc = 100, sizes = {huge = true}}, false)
      configured = true
    end
    stock(left, {[PROM] = 4})
    stock(right, {[PROM] = 4})
    if target and target.valid then
      if target.position.y < -29 then return end
      target.destroy()
    end
    shell, hold_until = nil, nil
    game.simulation.camera_position = home
    target = spawn("huge-promethium-asteroid", side * 3, -56, 0, 0.045)
    side = -side
  end, 3.4, follow)
]], 8)

return M
