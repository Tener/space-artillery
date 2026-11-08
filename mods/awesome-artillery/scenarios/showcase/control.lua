-- Showcase for screenshots: an arrow-shaped ship packed with turrets, flying Aquilo ->
-- solar system edge at speed through dense asteroids, huge ones included. Only UI: two
-- tiny screenshot buttons, bottom left. The ship is indestructible and the turrets are
-- kept stocked. Prints what artillery killed every 10 s (stdout, for headless checks).

local killed = {} -- not saved: stdout reporting only
script.on_event(defines.events.on_entity_died, function(e)
  if e.cause and e.cause.type == "artillery-turret" then killed[e.entity.name] = (killed[e.entity.name] or 0) + 1 end
end, {{filter = "type", type = "asteroid"}})
script.on_nth_tick(600, function()
  local parts = {}
  for name, n in pairs(killed) do if name:find("^huge") or name:find("^big") then parts[#parts + 1] = name .. "=" .. n end end
  table.sort(parts)
  local pf, near = storage.platform, {}
  if pf and pf.valid then
    for _, a in pairs(pf.surface.find_entities_filtered{type = "asteroid", position = {0, 0}, radius = 250}) do
      local size = a.name:match("^(%a+)%-")
      near[size] = (near[size] or 0) + 1
    end
  end
  local around = {}
  for size, n in pairs(near) do around[#around + 1] = size .. "=" .. n end
  table.sort(around)
  print(string.format("[SHOWCASE] t=%d %s speed=%.1f; around: %s; artillery kills (big/huge): %s", game.tick,
    pf and pf.valid and (pf.space_connection and "in transit" or "in orbit") or "no platform",
    pf and pf.valid and pf.speed or 0, table.concat(around, " "), table.concat(parts, " ")))
end)

local SPEED = 20
local TIP, HEAD_END, TAIL = -70, -14, 46 -- arrow tip, end of the arrowhead, tail (y)

-- arrow outline: half-width of the hull at row y (nil = no hull)
local function half_width(y)
  if y < TIP or y > TAIL then return nil end
  if y <= HEAD_END then return math.floor((y - TIP) * 0.62) end
  if y >= TAIL - 14 then return 11 + (y - (TAIL - 14)) end -- tail fins
  return 11
end

local function on_hull(x, y)
  local hw = half_width(y)
  return hw ~= nil and math.abs(x) <= hw
end

local function build_ship()
  local force = game.forces.player
  for _, loc in pairs{"fulgora", "aquilo", "solar-system-edge"} do force.unlock_space_location(loc) end
  force.set_ammo_damage_modifier("artillery-shell", 5) -- +500%: about 2 shells per huge asteroid
  force.set_gun_speed_modifier("artillery-shell", 2)
  remote.call("awesome-artillery", "reset_damage")
  remote.call("awesome-artillery", "set_min_size", "small")

  local platform = force.create_space_platform{name = "Awesome Artillery", planet = "aquilo",
    starter_pack = "space-platform-starter-pack"}
  platform.apply_starter_pack()
  local s = platform.surface
  for x = -6, 6 do for y = -6, 6 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()
  local tiles = {}
  for y = TIP, TAIL do
    local hw = half_width(y)
    for x = -hw - 1, hw do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
  end
  s.set_tiles(tiles)

  storage.stock = {}
  local function make(name, x, y, fill)
    if not s.can_place_entity{name = name, position = {x, y}, force = force,
      build_check_type = defines.build_check_type.script} then return end
    local e = s.create_entity{name = name, position = {x, y}, force = force, raise_built = true,
      direction = defines.direction.north}
    if e and fill then storage.stock[#storage.stock + 1] = {e, fill[1], fill[2], fill[3]} end
    return e
  end
  local function fits(x, y, r) -- footprint of radius r around (x, y) is all hull
    return on_hull(x - r, y - r) and on_hull(x + r, y - r) and on_hull(x - r, y + r) and on_hull(x + r, y + r)
  end

  -- thrusters at the tail, power, then turrets
  for _, x in pairs{-15, -5, 5, 15} do
    local t = make("thruster", x, TAIL - 7)
    if t then storage.thrusters = storage.thrusters or {}; storage.thrusters[#storage.thrusters + 1] = t end
  end
  for _, pos in pairs{{-6, 6}, {6, 6}} do
    local e = make("electric-energy-interface", pos[1], pos[2])
    if e then e.power_production = 1e9 / 60; e.electric_buffer_size = 1e9 end
  end
  for y = TIP + 10, TAIL, 14 do
    for x = -42, 42, 14 do if fits(x, y, 1) then make("substation", x, y) end end
  end
  local shell = {defines.inventory.artillery_turret_ammo, "artillery-shell", 10}
  local mag = {defines.inventory.turret_ammo, "piercing-rounds-magazine", 20}
  -- edges of the arrowhead: lasers outside, guns just inside
  for y = TIP + 6, HEAD_END + 10, 2 do
    local hw = half_width(y)
    for _, side in pairs{-1, 1} do
      make("laser-turret", side * (hw - 1), y)
      make("gun-turret", side * (hw - 4), y + 1, mag)
    end
  end
  -- artillery fills the arrowhead and the front of the shaft
  for y = TIP + 14, HEAD_END + 8, 5 do
    for x = -40, 40, 5 do
      if fits(x, y, 2) then make("artillery-turret", x, y, shell) end
    end
  end
  -- computer: everything, all around
  make("awe-art-targeting-computer", 0, 12)
  local counts = {}
  for _, e in pairs(s.find_entities_filtered{force = force}) do
    e.destructible = false
    counts[e.name] = (counts[e.name] or 0) + 1
  end
  local parts = {}
  for name, n in pairs(counts) do parts[#parts + 1] = name .. "=" .. n end
  table.sort(parts)
  print("[SHOWCASE] built: " .. table.concat(parts, " "))

  platform.schedule = {current = 1, records = {{station = "solar-system-edge"}, {station = "aquilo"}}}
  platform.paused = false
  storage.platform = platform
end

local function place_buttons(p)
  local f = p.gui.screen.awe_art_shots
  if not f then
    f = p.gui.screen.add{type = "flow", name = "awe_art_shots", direction = "horizontal"}
    for _, b in pairs{{"awe_art_shot_wide", "16:9", "Screenshot 3840×2160, no UI"},
                      {"awe_art_shot_square", "1:1", "Screenshot 2048×2048, no UI (thumbnail)"}} do
      local btn = f.add{type = "button", name = b[1], caption = b[2], tooltip = b[3], style = "mini_button"}
      btn.style.width, btn.style.height = 36, 20
      btn.style.font = "default-small"
    end
  end
  local scale = p.display_scale
  f.location = {8, p.display_resolution.height - math.ceil(28 * scale)}
end

script.on_init(function()
  storage.boarded = {}
  local arg = script.test_arg
  if arg then
    storage.save_at = tonumber(arg:match("(%d+)")) or 600
  end
  build_ship()
end)

script.on_event(defines.events.on_player_created, function(e)
  local p = game.get_player(e.player_index)
  p.cheat_mode = true
  place_buttons(p)
end)

script.on_event({defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed},
  function(e) place_buttons(game.get_player(e.player_index)) end)

script.on_event(defines.events.on_gui_click, function(e)
  local name = e.element.valid and e.element.name
  if name ~= "awe_art_shot_wide" and name ~= "awe_art_shot_square" then return end
  local p = game.get_player(e.player_index)
  local square = name == "awe_art_shot_square"
  local path = string.format("awesome-artillery-showcase-%d%s.png", game.tick, square and "-square" or "")
  game.take_screenshot{player = p, resolution = square and {2048, 2048} or {3840, 2160}, show_gui = false,
    show_entity_info = false, path = path}
  p.print("Saved script-output/" .. path)
end)

script.on_event(defines.events.on_tick, function(e)
  for _, th in pairs(storage.thrusters or {}) do
    if th.valid then
      th.insert_fluid{name = "thruster-fuel", amount = 1000}
      th.insert_fluid{name = "thruster-oxidizer", amount = 1000}
    end
  end
  local pf = storage.platform
  if not (pf and pf.valid) then return end
  -- board everyone once the client is ready; stay in transit forever
  if e.tick % 60 == 0 then
    for _, p in pairs(game.connected_players) do
      if not storage.boarded[p.index] and pcall(p.enter_space_platform, pf) then
        storage.boarded[p.index] = true
        p.zoom = 0.45
      end
    end
    for _, st in pairs(storage.stock) do
      local ent, inv_id, item, count = st[1], st[2], st[3], st[4]
      if ent.valid then
        local inv = ent.get_inventory(inv_id)
        local n = inv.get_item_count(item)
        if n < count then inv.insert{name = item, count = count - n} end
      end
    end
  end
  if pf.space_connection then
    pf.speed = SPEED
    if pf.distance > 0.8 then pf.distance = 0.2 end
  end
  if storage.save_at then
    if e.tick == storage.save_at then
      print("[SHOWCASE] saving _autosave-showcase at tick " .. e.tick)
      game.auto_save("showcase")
      if script.test_arg then return script.finish_test(true) end
    elseif e.tick == storage.save_at + 1 then
      local s = pf.surface
      game.take_screenshot{surface = s, position = {0, -55}, resolution = {1920, 1080}, zoom = 0.45,
        show_gui = false, show_entity_info = false, path = "showcase-16x9.png"}
      game.take_screenshot{surface = s, position = {0, -55}, resolution = {2048, 2048}, zoom = 0.45,
        show_gui = false, show_entity_info = false, path = "showcase-square.png"}
      game.take_screenshot{surface = s, position = {0, -55}, resolution = {512, 512}, zoom = 0.45,
        show_gui = false, show_entity_info = false, path = "showcase-thumb-512.png"}
      print("[SHOWCASE] screenshots written to script-output/showcase-*.png")
    end
  end
end)
