-- Showcase Production: In-situ space casting. Shows real platform logistics:
-- melting asteroid ore into molten iron, casting flash-hardened steel plates with
-- asteroid ice & calcite, casting steel artillery shells, and inserting into the cannon.

local function build_production_scene()
  local force = game.forces.player
  for _, r in pairs{"iron-ore-melting", "awe-art-flash-hardened-steel", "awe-art-steel-artillery-shell"} do
    if force.recipes[r] then force.recipes[r].enabled = true end
  end

  local platform = force.create_space_platform{name = "Production Showcase", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
  local hub = platform.apply_starter_pack()
  hub.destructible = false
  local s = platform.surface

  for x = -3, 3 do for y = -3, 3 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()

  local tiles = {}
  for y = -18, 4 do
    for x = -12, 12 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
  end
  s.set_tiles(tiles)

  local function make(name, pos, dir, recipe)
    local e = s.create_entity{name = name, position = pos, force = force, raise_built = true,
      direction = dir or defines.direction.north, recipe = recipe}
    if not (e and e.valid) then
      e = s.find_entities_filtered{position = pos, radius = 1.5, force = force}[1]
    end
    if e and e.valid then e.destructible = false end
    return e
  end

  local eei = make("electric-energy-interface", {0, 3})
  if eei then eei.power_production = 1e8; eei.electric_buffer_size = 1e8 end

  -- 1. Melting Foundry (casts molten-iron)
  local a_melt = make("foundry", {-6.5, -6.5}, defines.direction.east, "iron-ore-melting")
  local c_ore = make("requester-chest", {-6.5, -2.5})
  if c_ore then
    c_ore.insert{name = "iron-ore", count = 100}
    c_ore.insert{name = "calcite", count = 50}
  end
  make("fast-inserter", {-6.5, -3.5}, defines.direction.south)

  -- 2. Flash-hardened steel Foundry
  local a_fhs = make("foundry", {0.5, -6.5}, defines.direction.north, "awe-art-flash-hardened-steel")
  local c_fhs = make("requester-chest", {0.5, -2.5})
  if c_fhs then
    c_fhs.insert{name = "carbon", count = 100}
    c_fhs.insert{name = "calcite", count = 50}
    c_fhs.insert{name = "ice", count = 50}
  end
  make("fast-inserter", {0.5, -3.5}, defines.direction.south)

  -- Fluid pipe connection from Melting to FHS Foundry
  local pipe1 = make("pipe", {-3.5, -6.5})
  local pipe2 = make("pipe", {-2.5, -6.5})

  -- 3. Shell Foundry
  local a_sh = make("foundry", {7.5, -6.5}, defines.direction.north, "awe-art-steel-artillery-shell")
  -- Inserter moving FHS plates from a_fhs into a_sh
  make("fast-inserter", {4.5, -6.5}, defines.direction.west)

  local c_sh = make("requester-chest", {7.5, -2.5})
  if c_sh then
    c_sh.insert{name = "explosives", count = 100}
    c_sh.insert{name = "radar", count = 20}
  end
  make("fast-inserter", {7.5, -3.5}, defines.direction.south)

  -- 4. Artillery Turret receiving finished shells
  local turret = make("artillery-turret", {7.5, -12.5})
  -- Inserter moving shells from a_sh into turret
  make("fast-inserter", {7.5, -10.0}, defines.direction.south)

  storage.platform = platform
  storage.a_melt = a_melt
  storage.a_fhs = a_fhs
  storage.a_sh = a_sh
  storage.c_ore = c_ore
  storage.c_fhs = c_fhs
  storage.c_sh = c_sh
  storage.pipe1 = pipe1
  storage.turret = turret
end

script.on_init(function()
  build_production_scene()
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

  -- Keep fluids and supplies cycling
  if e.tick % 30 == 0 then
    if storage.pipe1 and storage.pipe1.valid then storage.pipe1.insert_fluid{name = "molten-iron", amount = 100} end
    if storage.a_fhs and storage.a_fhs.valid then storage.a_fhs.insert_fluid{name = "molten-iron", amount = 200} end
    if storage.c_ore and storage.c_ore.valid then
      storage.c_ore.insert{name = "iron-ore", count = 10}
      storage.c_ore.insert{name = "calcite", count = 5}
    end
    if storage.c_fhs and storage.c_fhs.valid then
      storage.c_fhs.insert{name = "carbon", count = 10}
      storage.c_fhs.insert{name = "calcite", count = 5}
      storage.c_fhs.insert{name = "ice", count = 5}
    end
    if storage.c_sh and storage.c_sh.valid then
      storage.c_sh.insert{name = "explosives", count = 10}
      storage.c_sh.insert{name = "radar", count = 2}
    end
  end

  local CAPTURE_START = 120
  local CAPTURE_END = 300
  local CAPTURE_INTERVAL = 3

  if not script.test_arg then
    if e.tick == CAPTURE_START then
      game.take_screenshot{surface = s, position = {0.5, -7.5}, resolution = {1920, 1080}, zoom = 0.82,
        show_gui = false, show_entity_info = false, path = "production-16x9.png"}
      print("[SHOWCASE] production still screenshot written")
    end
    if e.tick >= CAPTURE_START and e.tick <= CAPTURE_END and (e.tick - CAPTURE_START) % CAPTURE_INTERVAL == 0 then
      local f = math.floor((e.tick - CAPTURE_START) / CAPTURE_INTERVAL) + 1
      game.take_screenshot{surface = s, position = {0.5, -7.5}, resolution = {960, 540}, zoom = 0.82,
        show_gui = false, show_entity_info = false, path = string.format("production-frame-%04d.png", f)}
      if e.tick == CAPTURE_END then
        print(string.format("[SHOWCASE] CAPTURE_COMPLETE frames=%d", f))
      end
    end
  end
end)
