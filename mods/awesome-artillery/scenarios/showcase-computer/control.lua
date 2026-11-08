-- Showcase Computer: Focuses on the Targeting Computer entity, its circuit
-- network connection to artillery cannons, and its configuration GUI with the
-- live sector zone overlay.

local function build_computer_scene()
  local force = game.forces.player
  local platform = force.create_space_platform{name = "Computer Showcase", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
  local hub = platform.apply_starter_pack()
  hub.destructible = false
  local s = platform.surface

  for x = -3, 3 do for y = -3, 3 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()

  local tiles = {}
  for y = -16, 4 do
    for x = -10, 10 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
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

  local t_left = make("artillery-turret", {-5.5, -10.5})
  local t_right = make("artillery-turret", {5.5, -10.5})
  local comp = make("awe-art-targeting-computer", {0, -6.5})
  local cc = make("constant-combinator", {3.5, -6.5})

  if comp and t_left and t_right then
    local red = defines.wire_connector_id.circuit_red
    local conn_c = comp.get_wire_connector(red, true)
    local conn_l = t_left.get_wire_connector(red, true)
    local conn_r = t_right.get_wire_connector(red, true)
    if conn_c and conn_l then conn_c.connect_to(conn_l, false) end
    if conn_c and conn_r then conn_c.connect_to(conn_r, false) end
    if cc and conn_c then
      local conn_cc = cc.get_wire_connector(red, true)
      if conn_cc then conn_cc.connect_to(conn_c, false) end
    end
  end

  storage.platform = platform
  storage.comp = comp
end

script.on_init(function()
  build_computer_scene()
end)

script.on_event(defines.events.on_tick, function(e)
  local pf = storage.platform
  if not (pf and pf.valid) then return end
  local s = pf.surface

  if script.test_arg then
    if e.tick >= tonumber(script.test_arg) or 60 then
      return script.finish_test(true)
    end
  end

  local p = game.get_player(1) or game.connected_players[1]
  if p and p.valid and not storage.player_ready then
    p.enter_space_platform(pf)
    p.teleport({0, -3.5}, s)
    p.zoom = 0.8
    storage.player_ready = true
  end

  if e.tick == 40 and p and p.valid and storage.comp and storage.comp.valid then
    remote.call("awesome-artillery", "set_computer_cfg", storage.comp.unit_number, {
      sizes = {small = false, medium = true, big = true, huge = true},
      dir = 0, arc = 90, near = 30, far = 60,
    })
    remote.call("awesome-artillery", "open_computer", p.index, storage.comp.unit_number)
    print("[SHOWCASE] computer GUI opened for player")
  end

  if e.tick == 80 then
    if p and p.valid then
      game.take_screenshot{player = p, resolution = {1920, 1080}, show_gui = true,
        show_entity_info = false, path = "computer-gui.png"}
      print("[SHOWCASE] computer GUI screenshot written")
    else
      game.take_screenshot{surface = s, position = {0, -6}, resolution = {1920, 1080}, zoom = 0.8,
        show_gui = true, show_entity_info = false, path = "computer-gui.png"}
    end
    print("[SHOWCASE] CAPTURE_COMPLETE frames=1")
  end
end)
