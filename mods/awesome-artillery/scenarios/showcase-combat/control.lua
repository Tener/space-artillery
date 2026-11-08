-- Showcase Combat: Long-range kinetic interception. Focuses on artillery cannons
-- swiveling, leading shots, projectile flight, and mid-space asteroid explosions.

local function build_combat_platform()
  local force = game.forces.player
  force.unlock_space_location("vulcanus")
  force.set_ammo_damage_modifier("artillery-shell", 3.0)
  force.set_gun_speed_modifier("artillery-shell", 1.5)
  if force.technologies["awe-art-artillery-shell-velocity-1"] then force.technologies["awe-art-artillery-shell-velocity-1"].level = 6 end

  local platform = force.create_space_platform{name = "Combat Platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
  local hub = platform.apply_starter_pack()
  hub.destructible = false
  local s = platform.surface

  for x = -3, 3 do for y = -3, 3 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()

  local tiles = {}
  for y = -22, 4 do
    local hw = y < -14 and math.floor((y + 24) * 1.4) or 10
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

  local eei = make("electric-energy-interface", {0, 2})
  if eei then eei.power_production = 1e8; eei.electric_buffer_size = 1e8 end

  local t_left = make("artillery-turret", {-5.5, -14.5})
  local t_right = make("artillery-turret", {5.5, -14.5})
  assert(t_left and t_right, "turrets nil")
  t_left.insert{name = "awe-art-steel-artillery-shell", count = 30}
  t_right.insert{name = "awe-art-steel-artillery-shell", count = 30}

  local c_left = make("requester-chest", {-5.5, -11.5})
  if c_left then c_left.insert{name = "awe-art-steel-artillery-shell", count = 50} end
  make("fast-inserter", {-5.5, -12.5}, defines.direction.south)

  local c_right = make("requester-chest", {5.5, -11.5})
  if c_right then c_right.insert{name = "awe-art-steel-artillery-shell", count = 50} end
  make("fast-inserter", {5.5, -12.5}, defines.direction.south)

  local comp = make("awe-art-targeting-computer", {0, -15.5})
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
  build_combat_platform()
end)

local wave = {
  {"big-metallic-asteroid", -4, -54, 0.005, 0.035},
  {"medium-oxide-asteroid", 6, -50, -0.005, 0.035},
  {"big-carbonic-asteroid", 2, -56, 0.0, 0.035},
  {"medium-metallic-asteroid", -7, -48, 0.008, 0.035},
  {"big-oxide-asteroid", -2, -55, 0.002, 0.035},
}
local wave_idx = 0

script.on_event(defines.events.on_tick, function(e)
  local pf = storage.platform
  if not (pf and pf.valid) then return end
  local s = pf.surface

  if script.test_arg then
    if e.tick >= tonumber(script.test_arg) or 60 then
      return script.finish_test(true)
    end
  end

  if pf.space_connection then
    pf.speed = 10
    if pf.distance > 0.8 then pf.distance = 0.2 end
  end

  if e.tick % 60 == 0 then
    if storage.c_left and storage.c_left.valid then storage.c_left.insert{name = "awe-art-steel-artillery-shell", count = 5} end
    if storage.c_right and storage.c_right.valid then storage.c_right.insert{name = "awe-art-steel-artillery-shell", count = 5} end
    if storage.t_left and storage.t_left.valid then storage.t_left.insert{name = "awe-art-steel-artillery-shell", count = 5} end
    if storage.t_right and storage.t_right.valid then storage.t_right.insert{name = "awe-art-steel-artillery-shell", count = 5} end
  end

  if not storage.configured and remote.interfaces["awesome-artillery"] then
    storage.configured = true
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    if storage.comp and storage.comp.valid then
      remote.call("awesome-artillery", "set_computer_cfg", storage.comp.unit_number, {
        sizes = {small = false, medium = true, big = true, huge = true},
        dir = 0, arc = 90, near = 30, far = 55,
      })
    end
  end

  if e.tick % 40 == 0 then
    wave_idx = (wave_idx % #wave) + 1
    local w = wave[wave_idx]
    s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
  end

  for _, a in pairs(s.find_entities_filtered{type = "asteroid"}) do
    if a.position.y > -10 or a.position.y < -75 or math.abs(a.position.x) > 30 then a.destroy() end
  end

  local CAPTURE_START = 180
  local CAPTURE_END = 360
  local CAPTURE_INTERVAL = 3

  if not script.test_arg then
    if e.tick == CAPTURE_START then
      game.take_screenshot{surface = s, position = {0, -32}, resolution = {1920, 1080}, zoom = 0.70,
        show_gui = false, show_entity_info = false, path = "combat-16x9.png"}
      print("[SHOWCASE] combat still screenshot written at tick " .. e.tick)
    end
    if e.tick >= CAPTURE_START and e.tick <= CAPTURE_END and (e.tick - CAPTURE_START) % CAPTURE_INTERVAL == 0 then
      local f = math.floor((e.tick - CAPTURE_START) / CAPTURE_INTERVAL) + 1
      game.take_screenshot{surface = s, position = {0, -32}, resolution = {960, 540}, zoom = 0.70,
        show_gui = false, show_entity_info = false, path = string.format("combat-frame-%04d.png", f)}
      if e.tick == CAPTURE_END then
        print(string.format("[SHOWCASE] CAPTURE_COMPLETE frames=%d", f))
      end
    end
  end
end)
