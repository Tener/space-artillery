-- Showcase: Single unified realistic Space Age artillery platform.
-- Captures all 5 showcases in a single smooth Factorio run:
-- 1. Production (in-situ space casting: crushing, molten iron, FHS, shell casting, cannon loading)
-- 2. Combat (artillery battery firing and detonating incoming asteroid waves)
-- 3. Promethium (heavy kinetic shell penetrating a huge asteroid's 3,000 flat physical armor)
-- 4. Hero overview (full ship in space flight with thruster plumes and active factory)
-- 5. Targeting Computer GUI (open configuration window with visible sector cone overlay)

local wave_combat = {
  {"medium-metallic-asteroid", -6, -50, 0.0, 0.14},
  {"medium-carbonic-asteroid", 4, -48, -0.01, 0.13},
  {"big-metallic-asteroid", 0, -54, 0.0, 0.12},
  {"medium-oxide-asteroid", -10, -52, 0.02, 0.15},
  {"medium-metallic-asteroid", 8, -49, -0.02, 0.14},
}

local function build_ship()
  local force = game.forces.player
  force.unlock_space_location("vulcanus")
  force.unlock_space_location("aquilo")

  for _, r in pairs{
    "metallic-asteroid-crushing", "carbonic-asteroid-crushing", "oxide-asteroid-crushing",
    "iron-ore-melting", "awe-art-flash-hardened-steel", "awe-art-steel-artillery-shell",
    "awe-art-promethium-artillery-shell", "thruster-fuel", "thruster-oxidizer"
  } do
    if force.recipes[r] then force.recipes[r].enabled = true end
  end

  local platform = force.create_space_platform{
    name = "Artillery Vanguard",
    planet = "nauvis",
    starter_pack = "space-platform-starter-pack"
  }
  local hub = platform.apply_starter_pack()
  hub.destructible = false
  local s = platform.surface

  for x = -4, 4 do for y = -4, 4 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()

  -- Hull tiles: tapered prow, wide midsection, engine block
  local tiles = {}
  for y = -18, 16 do
    local half_w = 12
    if y < -12 then
      half_w = 6 + (y + 18) * 1  -- Prow tapers from 6 to 12
    elseif y > 10 then
      half_w = 8                 -- Engine bay tapers to 8
    end
    for x = -half_w, half_w do
      tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}}
    end
  end
  s.set_tiles(tiles)

  local function make(name, pos, dir, recipe)
    local e = s.create_entity{
      name = name,
      position = pos,
      force = force,
      raise_built = true,
      direction = dir or defines.direction.north,
      recipe = recipe
    }
    if not (e and e.valid) then
      e = s.find_entities_filtered{position = pos, radius = 1.0, force = force}[1]
    end
    if e and e.valid then e.destructible = false end
    return e
  end

  -- Power
  local eei = make("electric-energy-interface", {0, 10})
  if eei then eei.power_production = 1e9; eei.electric_buffer_size = 1e9 end
  make("substation", {-7, -4})
  make("substation", {7, -4})
  make("substation", {-7, 6})
  make("substation", {7, 6})

  -- Rear Thruster Bank
  local t1 = make("thruster", {-4, 13}, defines.direction.south)
  local t2 = make("thruster", {0, 13}, defines.direction.south)
  local t3 = make("thruster", {4, 13}, defines.direction.south)
  for _, t in pairs{t1, t2, t3} do
    if t and t.valid then
      t.insert_fluid{name = "thruster-fuel", amount = 1000}
      t.insert_fluid{name = "thruster-oxidizer", amount = 1000}
    end
  end
  -- Thruster piping
  for x = -5, 5 do make("pipe", {x, 11}) end

  -- Midship Factory Bay: In-situ space casting
  -- 1. Metallic Asteroid Crusher
  local c_metal = make("crusher", {-8, 0}, defines.direction.north, "metallic-asteroid-crushing")
  -- 2. Oxide Asteroid Crusher
  local c_oxide = make("crusher", {-8, -5}, defines.direction.north, "oxide-asteroid-crushing")
  -- 3. Carbonic Asteroid Crusher
  local c_carbon = make("crusher", {8, 0}, defines.direction.north, "carbonic-asteroid-crushing")

  -- 4. Melting Foundry: Iron Ore -> Molten Iron
  local f_melt = make("foundry", {-2.5, 0}, defines.direction.east, "iron-ore-melting")
  -- Inserter moving iron ore from crusher into melting foundry
  make("fast-inserter", {-5.5, 0}, defines.direction.east)

  -- Molten iron pipe from melting foundry to FHS foundry
  make("pipe", {-2.5, -3})
  make("pipe", {-2.5, -4})

  -- 5. Flash-Hardened Steel Foundry: Molten Iron + Carbon + Calcite + Ice -> FHS Plates
  local f_fhs = make("foundry", {-2.5, -7}, defines.direction.north, "awe-art-flash-hardened-steel")
  -- Inserter moving calcite & ice from oxide crusher to FHS foundry
  make("fast-inserter", {-5.5, -5}, defines.direction.east)

  -- 6. Steel Shell Foundry: FHS Plates + Explosives + Radar -> Steel Artillery Shells
  local f_shell = make("foundry", {3.5, -7}, defines.direction.north, "awe-art-steel-artillery-shell")
  -- Inserter moving FHS plates from f_fhs into f_shell
  make("fast-inserter", {0.5, -7}, defines.direction.east)

  -- Belts carrying finished shells forward to the artillery turrets
  make("transport-belt", {3.5, -10}, defines.direction.north)
  make("transport-belt", {3.5, -11}, defines.direction.north)
  make("transport-belt", {3.5, -12}, defines.direction.west)
  make("transport-belt", {2.5, -12}, defines.direction.west)
  make("transport-belt", {1.5, -12}, defines.direction.west)
  make("transport-belt", {-1.5, -12}, defines.direction.west)
  make("transport-belt", {-2.5, -12}, defines.direction.west)
  make("transport-belt", {-3.5, -12}, defines.direction.west)

  -- Inserter unloading shells from f_shell onto belt
  make("fast-inserter", {3.5, -9.5}, defines.direction.north)

  -- Forward Artillery Battery on Prow
  local t_left = make("artillery-turret", {-5, -14}, defines.direction.north)
  local t_right = make("artillery-turret", {5, -14}, defines.direction.north)

  -- Inserters loading shells from belt into artillery turrets
  make("fast-inserter", {-5, -12}, defines.direction.north)
  make("fast-inserter", {5, -12}, defines.direction.north)

  -- Point Defense along perimeter
  make("laser-turret", {-10, -14})
  make("laser-turret", {10, -14})
  make("gun-turret", {-8, -17})
  make("gun-turret", {8, -17})

  -- Targeting Computer between the cannons
  local comp = make("awe-art-targeting-computer", {0, -14})

  -- Connect red circuit wire from computer to both artillery cannons
  if comp and comp.valid then
    local comp_c = comp.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    if t_left and t_left.valid then
      local tl_c = t_left.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      comp_c.connect_to(tl_c)
    end
    if t_right and t_right.valid then
      local tr_c = t_right.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      comp_c.connect_to(tr_c)
    end
  end

  -- Initial ammo stock
  if t_left and t_left.valid then t_left.insert{name = "awe-art-steel-artillery-shell", count = 15} end
  if t_right and t_right.valid then t_right.insert{name = "awe-art-steel-artillery-shell", count = 15} end

  storage.platform = platform
  storage.hub = hub
  storage.comp = comp
  storage.t_left = t_left
  storage.t_right = t_right
  storage.t1 = t1
  storage.t2 = t2
  storage.t3 = t3
  storage.c_metal = c_metal
  storage.c_oxide = c_oxide
  storage.c_carbon = c_carbon
  storage.f_melt = f_melt
  storage.f_fhs = f_fhs
  storage.f_shell = f_shell

  -- Schedule platform towards Aquilo so starfield moves smoothly
  platform.schedule = {current = 1, records = {{station = "solar-system-edge"}, {station = "aquilo"}}}
  platform.paused = false
end

script.on_init(function()
  build_ship()
end)

script.on_event(defines.events.on_tick, function(e)
  local pf = storage.platform
  if not (pf and pf.valid) then return end
  local s = pf.surface

  if script.test_arg then
    if e.tick >= (tonumber(script.test_arg) or 60) then
      return script.finish_test(true)
    end
  end

  -- Configure targeting computer once remote is available
  if not storage.configured and remote.interfaces["awesome-artillery"] then
    storage.configured = true
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    if storage.comp and storage.comp.valid then
      remote.call("awesome-artillery", "set_computer_cfg", storage.comp.unit_number, {
        sizes = {small = false, medium = true, big = true, huge = true},
        dir = 0, arc = 90, near = 24, far = 56,
      })
    end
  end

  -- Maintain thruster fuel and production inputs
  if e.tick % 30 == 0 then
    for _, t in pairs{storage.t1, storage.t2, storage.t3} do
      if t and t.valid then
        t.insert_fluid{name = "thruster-fuel", amount = 100}
        t.insert_fluid{name = "thruster-oxidizer", amount = 100}
      end
    end
    if storage.c_metal and storage.c_metal.valid then storage.c_metal.insert{name = "metallic-asteroid-chunk", count = 5} end
    if storage.c_oxide and storage.c_oxide.valid then storage.c_oxide.insert{name = "oxide-asteroid-chunk", count = 5} end
    if storage.c_carbon and storage.c_carbon.valid then storage.c_carbon.insert{name = "carbonic-asteroid-chunk", count = 5} end
    if storage.f_melt and storage.f_melt.valid then
      storage.f_melt.insert{name = "iron-ore", count = 10}
      storage.f_melt.insert{name = "calcite", count = 2}
    end
    if storage.f_fhs and storage.f_fhs.valid then
      storage.f_fhs.insert_fluid{name = "molten-iron", amount = 100}
      storage.f_fhs.insert{name = "carbon", count = 5}
      storage.f_fhs.insert{name = "calcite", count = 2}
      storage.f_fhs.insert{name = "ice", count = 2}
    end
    if storage.f_shell and storage.f_shell.valid then
      storage.f_shell.insert{name = "awe-art-flash-hardened-steel", count = 4}
      storage.f_shell.insert{name = "explosives", count = 10}
      storage.f_shell.insert{name = "radar", count = 2}
    end
  end

  -- Maintain platform flight speed
  if pf.space_connection then
    pf.speed = 12
    if pf.distance > 0.85 then pf.distance = 0.15 end
  end

  -- Visual Capture Timeline
  -- Phase 1: Production (Ticks 60 - 180)
  -- Focused directly on the midship factory bay, crushers, foundries, fluid pipes, belts, inserters
  local P1_START = 60
  local P1_END = 180
  if e.tick == P1_START then
    game.take_screenshot{
      surface = s, position = {0, -5}, resolution = {1920, 1080}, zoom = 0.95,
      show_gui = false, show_entity_info = true, path = "production-16x9.png"
    }
    print("[SHOWCASE] production still written")
  end
  if e.tick >= P1_START and e.tick <= P1_END and (e.tick - P1_START) % 3 == 0 then
    local f = math.floor((e.tick - P1_START) / 3) + 1
    game.take_screenshot{
      surface = s, position = {0, -5}, resolution = {960, 540}, zoom = 0.95,
      show_gui = false, show_entity_info = true, path = string.format("production-frame-%04d.png", f)
    }
  end

  -- Phase 2: Combat (Ticks 180 - 300)
  -- Framing at {0, -26}, zoom 0.52: Prow cannons at Y=-14 are in lower third; asteroid wave at Y=-45 to -55 in upper half
  local P2_START = 180
  local P2_END = 300
  if e.tick >= P2_START and e.tick <= P2_END and (e.tick - P2_START) % 25 == 0 then
    local idx = math.floor((e.tick - P2_START) / 25) % #wave_combat + 1
    local w = wave_combat[idx]
    s.create_entity{name = w[1], position = {w[2], w[3]}, velocity = {w[4], w[5]}}
  end
  if e.tick == P2_START + 15 then
    game.take_screenshot{
      surface = s, position = {0, -26}, resolution = {1920, 1080}, zoom = 0.52,
      show_gui = false, show_entity_info = true, path = "combat-16x9.png"
    }
    print("[SHOWCASE] combat still written")
  end
  if e.tick >= P2_START and e.tick <= P2_END and (e.tick - P2_START) % 3 == 0 then
    local f = math.floor((e.tick - P2_START) / 3) + 1
    game.take_screenshot{
      surface = s, position = {0, -26}, resolution = {960, 540}, zoom = 0.52,
      show_gui = false, show_entity_info = true, path = string.format("combat-frame-%04d.png", f)
    }
  end

  -- Phase 3: Promethium Penetration (Ticks 300 - 420)
  -- Turrets switch to heavy promethium shells. Huge asteroid approaches; kinetic explosion penetrates 3000 flat armor.
  local P3_START = 300
  local P3_END = 420
  if e.tick == P3_START then
    if storage.t_left and storage.t_left.valid then
      storage.t_left.clear_items_inside()
      storage.t_left.insert{name = "awe-art-promethium-artillery-shell", count = 15}
    end
    if storage.t_right and storage.t_right.valid then
      storage.t_right.clear_items_inside()
      storage.t_right.insert{name = "awe-art-promethium-artillery-shell", count = 15}
    end
    s.create_entity{name = "huge-promethium-asteroid", position = {0, -52}, velocity = {0.0, 0.10}}
  end
  if e.tick == P3_START + 25 then
    game.take_screenshot{
      surface = s, position = {0, -26}, resolution = {1920, 1080}, zoom = 0.52,
      show_gui = false, show_entity_info = true, path = "promethium-16x9.png"
    }
    print("[SHOWCASE] promethium still written")
  end
  if e.tick >= P3_START and e.tick <= P3_END and (e.tick - P3_START) % 3 == 0 then
    local f = math.floor((e.tick - P3_START) / 3) + 1
    game.take_screenshot{
      surface = s, position = {0, -26}, resolution = {960, 540}, zoom = 0.52,
      show_gui = false, show_entity_info = true, path = string.format("promethium-frame-%04d.png", f)
    }
  end

  -- Phase 4: Hero Overview (Ticks 420 - 540)
  -- Wide cinematic view of the whole ship in flight
  local P4_START = 420
  local P4_END = 540
  if e.tick == P4_START then
    game.take_screenshot{
      surface = s, position = {0, 0}, resolution = {1920, 1080}, zoom = 0.42,
      show_gui = false, show_entity_info = true, path = "hero-16x9.png"
    }
    game.take_screenshot{
      surface = s, position = {0, 0}, resolution = {1080, 1080}, zoom = 0.42,
      show_gui = false, show_entity_info = true, path = "hero-square.png"
    }
    print("[SHOWCASE] hero stills written")
  end
  if e.tick >= P4_START and e.tick <= P4_END and (e.tick - P4_START) % 3 == 0 then
    local f = math.floor((e.tick - P4_START) / 3) + 1
    game.take_screenshot{
      surface = s, position = {0, 0}, resolution = {960, 540}, zoom = 0.42,
      show_gui = false, show_entity_info = true, path = string.format("hero-frame-%04d.png", f)
    }
  end

  -- Phase 5: Targeting Computer GUI (Tick 545 - 550)
  if e.tick == 545 then
    local p = game.get_player(1)
    if p and storage.comp and storage.comp.valid then
      remote.call("awesome-artillery", "open_computer", 1, storage.comp.unit_number)
    end
  end
  if e.tick == 550 then
    local p = game.get_player(1)
    if p then
      p.game_view_settings.show_entity_info = true
    end
    game.take_screenshot{
      surface = s, position = {0, -12}, resolution = {1920, 1080}, zoom = 0.85,
      show_gui = true, show_entity_info = true, path = "computer-gui.png"
    }
    print("[SHOWCASE] computer GUI screenshot written")
    print("[SHOWCASE] CAPTURE_COMPLETE")
  end
end)
