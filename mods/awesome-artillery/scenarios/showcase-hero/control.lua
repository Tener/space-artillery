-- Showcase Hero: A realistic, operational Space Age exploration ship cruising
-- in transit. 2 forward artillery cannons wired to a central targeting computer,
-- point defense on the flanks, thrusters at the stern, engaging an asteroid field.

local function build_hero_ship()
  local force = game.forces.player
  force.unlock_space_location("vulcanus")
  force.set_ammo_damage_modifier("artillery-shell", 2.0)
  force.set_gun_speed_modifier("artillery-shell", 1.5)
  if force.technologies["awe-art-artillery-shell-velocity-1"] then force.technologies["awe-art-artillery-shell-velocity-1"].level = 5 end

  local platform = force.create_space_platform{name = "Hero Ship", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
  local hub = platform.apply_starter_pack()
  hub.destructible = false
  local s = platform.surface

  for x = -4, 4 do for y = -4, 4 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()

  -- Sleek arrow-tapered hull
  local tiles = {}
  for y = -26, 8 do
    local hw
    if y < -16 then
      hw = math.max(6, math.floor(12 - math.abs(y + 20) * 1.2))
    elseif y < 4 then
      hw = 12
    else
      hw = 10
    end
    for x = -hw, hw do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
  end
  s.set_tiles(tiles)

  local function make(name, pos, dir)
    local e = s.create_entity{name = name, position = pos, force = force, raise_built = true, direction = dir or defines.direction.north}
    if not (e and e.valid) then
      e = s.find_entities_filtered{position = pos, radius = 1.5, force = force}[1]
    end
    if e and e.valid then e.destructible = false end
    return e
  end

  local eei = make("electric-energy-interface", {0, 5})
  if eei then eei.power_production = 1e8; eei.electric_buffer_size = 1e8 end

  -- Thrusters
  local t1 = make("thruster", {-6, 7})
  local t2 = make("thruster", {6, 7})
  storage.thrusters = {t1, t2}

  -- Artillery battery
  local t_left = make("artillery-turret", {-6.5, -16.5})
  local t_right = make("artillery-turret", {6.5, -16.5})
  assert(t_left and t_right, "turrets nil")
  t_left.insert{name = "awe-art-steel-artillery-shell", count = 20}
  t_right.insert{name = "awe-art-steel-artillery-shell", count = 20}

  -- Inserters and supply chests
  local c_left = make("requester-chest", {-6.5, -13.5})
  if c_left then c_left.insert{name = "awe-art-steel-artillery-shell", count = 50} end
  make("fast-inserter", {-6.5, -14.5}, defines.direction.south)

  local c_right = make("requester-chest", {6.5, -13.5})
  if c_right then c_right.insert{name = "awe-art-steel-artillery-shell", count = 50} end
  make("fast-inserter", {6.5, -14.5}, defines.direction.south)

  -- Point defense on prow and flanks
  for _, pos in pairs{{-10, -18}, {10, -18}} do
    local g = make("gun-turret", pos)
    if g then g.insert{name = "piercing-rounds-magazine", count = 100} end
  end
  make("laser-turret", {-3, -22})
  make("laser-turret", {3, -22})

  -- Targeting computer in center, wired to both cannons
  local comp = make("awe-art-targeting-computer", {0, -17.5})
  if comp and t_left and t_right then
    local red = defines.wire_connector_id.circuit_red
    local conn_c = comp.get_wire_connector(red, true)
    local conn_l = t_left.get_wire_connector(red, true)
    local conn_r = t_right.get_wire_connector(red, true)
    if conn_c and conn_l then conn_c.connect_to(conn_l, false) end
    if conn_c and conn_r then conn_c.connect_to(conn_r, false) end
  end

  platform.schedule = {current = 1, records = {{station = "vulcanus"}, {station = "nauvis"}}}
  platform.paused = false
  storage.platform = platform
  storage.comp = comp
  storage.t_left = t_left
  storage.t_right = t_right
  storage.c_left = c_left
  storage.c_right = c_right
end

script.on_init(function()
  build_hero_ship()
end)

local wave = {
  {"medium-metallic-asteroid", -8, -62, 0.01, 0.035},
  {"small-metallic-asteroid", 2, -55, 0.0, 0.04},
  {"big-oxide-asteroid", 0, -68, 0.0, 0.03},
  {"medium-carbonic-asteroid", 8, -60, -0.01, 0.035},
  {"big-metallic-asteroid", -6, -65, 0.008, 0.03},
  {"small-oxide-asteroid", -3, -56, 0.002, 0.04},
  {"huge-metallic-asteroid", 4, -70, -0.004, 0.025},
}
local wave_idx = 0

script.on_event(defines.events.on_tick, function(e)
  local pf = storage.platform
  if not (pf and pf.valid) then return end
  local s = pf.surface

  -- Headless test check
  if script.test_arg then
    if e.tick >= tonumber(script.test_arg) or 60 then
      return script.finish_test(true)
    end
  end

  for _, th in pairs(storage.thrusters or {}) do
    if th and th.valid then
      th.insert_fluid{name = "thruster-fuel", amount = 500}
      th.insert_fluid{name = "thruster-oxidizer", amount = 500}
    end
  end

  if pf.space_connection then
    pf.speed = 12
    if pf.distance > 0.8 then pf.distance = 0.2 end
  end

  -- Restock
  if e.tick % 60 == 0 then
    if storage.c_left and storage.c_left.valid then storage.c_left.insert{name = "awe-art-steel-artillery-shell", count = 5} end
    if storage.c_right and storage.c_right.valid then storage.c_right.insert{name = "awe-art-steel-artillery-shell", count = 5} end
    if storage.t_left and storage.t_left.valid then storage.t_left.insert{name = "awe-art-steel-artillery-shell", count = 5} end
    if storage.t_right and storage.t_right.valid then storage.t_right.insert{name = "awe-art-steel-artillery-shell", count = 5} end
  end

  -- Configure computer once
  if not storage.configured and remote.interfaces["awesome-artillery"] then
    storage.configured = true
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    if storage.comp and storage.comp.valid then
      remote.call("awesome-artillery", "set_computer_cfg", storage.comp.unit_number, {
        sizes = {small = false, medium = true, big = true, huge = true},
        dir = 0, arc = 120, near = 30, far = 60,
      })
    end
  end

  -- Spawn asteroids
  if e.tick % 45 == 0 then
    wave_idx = (wave_idx % #wave) + 1
    local w = wave[wave_idx]
    s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
  end

  for _, a in pairs(s.find_entities_filtered{type = "asteroid"}) do
    if a.position.y > -10 or a.position.y < -85 or math.abs(a.position.x) > 40 then a.destroy() end
  end

  -- Visual capture
  local CAPTURE_START = 200
  local CAPTURE_END = 380
  local CAPTURE_INTERVAL = 3 -- 61 frames = 3 seconds @ 20 fps

  if not script.test_arg then
    if e.tick == CAPTURE_START then
      game.take_screenshot{surface = s, position = {0, -28}, resolution = {1920, 1080}, zoom = 0.58,
        show_gui = false, show_entity_info = false, path = "hero-16x9.png"}
      game.take_screenshot{surface = s, position = {0, -28}, resolution = {1024, 1024}, zoom = 0.58,
        show_gui = false, show_entity_info = false, path = "hero-square.png"}
      print("[SHOWCASE] hero still screenshots taken at tick " .. e.tick)
    end
    if e.tick >= CAPTURE_START and e.tick <= CAPTURE_END and (e.tick - CAPTURE_START) % CAPTURE_INTERVAL == 0 then
      local f = math.floor((e.tick - CAPTURE_START) / CAPTURE_INTERVAL) + 1
      game.take_screenshot{surface = s, position = {0, -28}, resolution = {960, 540}, zoom = 0.58,
        show_gui = false, show_entity_info = false, path = string.format("hero-frame-%04d.png", f)}
      if e.tick == CAPTURE_END then
        print(string.format("[SHOWCASE] CAPTURE_COMPLETE frames=%d", f))
      end
    end
  end
end)
