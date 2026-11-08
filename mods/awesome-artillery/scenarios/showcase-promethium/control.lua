-- Showcase Promethium: Promethium ballistics vs Huge Asteroids.
-- A colossal huge asteroid approaches; point defense barely scratches its 3,000 flat
-- armor. A heavy Promethium artillery shell fires and shatters it in one kinetic blast.

local function build_promethium_scene()
  local force = game.forces.player
  force.unlock_space_location("aquilo")
  force.unlock_space_location("solar-system-edge")
  force.set_ammo_damage_modifier("artillery-shell", 1.5)
  if force.technologies["awe-art-artillery-shell-velocity-1"] then force.technologies["awe-art-artillery-shell-velocity-1"].level = 6 end

  local platform = force.create_space_platform{name = "Promethium Showcase", planet = "aquilo", starter_pack = "space-platform-starter-pack"}
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

  -- Center Promethium Cannon
  local turret = make("artillery-turret", {0, -14.5})
  assert(turret, "turret nil")
  turret.insert{name = "awe-art-promethium-artillery-shell", count = 30}

  local chest = make("requester-chest", {0, -11.5})
  if chest then chest.insert{name = "awe-art-promethium-artillery-shell", count = 50} end
  make("fast-inserter", {0, -12.5}, defines.direction.south)

  -- Flanking point defense
  for _, pos in pairs{{-6, -16}, {6, -16}} do
    local g = make("gun-turret", pos)
    if g then g.insert{name = "piercing-rounds-magazine", count = 100} end
  end
  make("laser-turret", {-4, -18})
  make("laser-turret", {4, -18})

  -- Targeting computer wired to the cannon
  local comp = make("awe-art-targeting-computer", {3.5, -13.5})
  if comp and turret then
    local red = defines.wire_connector_id.circuit_red
    local conn_c = comp.get_wire_connector(red, true)
    local conn_t = turret.get_wire_connector(red, true)
    if conn_c and conn_t then conn_c.connect_to(conn_t, false) end
  end

  platform.schedule = {current = 1, records = {{station = "solar-system-edge"}, {station = "aquilo"}}}
  platform.paused = false
  storage.platform = platform
  storage.comp = comp
  storage.turret = turret
  storage.chest = chest
end

script.on_init(function()
  build_promethium_scene()
end)

local wave = {
  {"huge-promethium-asteroid", -2, -56, 0.003, 0.025},
  {"huge-metallic-asteroid", 3, -60, -0.003, 0.025},
  {"huge-oxide-asteroid", -4, -58, 0.004, 0.025},
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
    if storage.chest and storage.chest.valid then storage.chest.insert{name = "awe-art-promethium-artillery-shell", count = 5} end
    if storage.turret and storage.turret.valid then storage.turret.insert{name = "awe-art-promethium-artillery-shell", count = 5} end
  end

  if not storage.configured and remote.interfaces["awesome-artillery"] then
    storage.configured = true
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    if storage.comp and storage.comp.valid then
      remote.call("awesome-artillery", "set_computer_cfg", storage.comp.unit_number, {
        sizes = {small = false, medium = false, big = true, huge = true},
        dir = 0, arc = 90, near = 30, far = 58,
      })
    end
  end

  if e.tick % 60 == 0 then
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
        show_gui = false, show_entity_info = false, path = "promethium-16x9.png"}
      print("[SHOWCASE] promethium still screenshot written")
    end
    if e.tick >= CAPTURE_START and e.tick <= CAPTURE_END and (e.tick - CAPTURE_START) % CAPTURE_INTERVAL == 0 then
      local f = math.floor((e.tick - CAPTURE_START) / CAPTURE_INTERVAL) + 1
      game.take_screenshot{surface = s, position = {0, -32}, resolution = {960, 540}, zoom = 0.70,
        show_gui = false, show_entity_info = false, path = string.format("promethium-frame-%04d.png", f)}
      if e.tick == CAPTURE_END then
        print(string.format("[SHOWCASE] CAPTURE_COMPLETE frames=%d", f))
      end
    end
  end
end)
