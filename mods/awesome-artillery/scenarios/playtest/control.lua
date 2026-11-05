-- Playtest scenario: a ready-made ship with 4 artillery turrets, front lasers and gun
-- turrets, a targeting computer, endless thruster fuel, looping Nauvis <-> Vulcanus.
-- Controlled from a panel. Headless: --test-arg "<case> <ticks>", see check_case.

local function say(fmt, ...) print("[PLAYTEST] " .. string.format(fmt, ...)) end

local SPEEDS = {0, 5, 10, 20} -- 0 = let the thrusters drive (natural is about 2)
local SIZES = {"small", "medium", "big", "huge"}
local CAUSES = {{"artillery-turret", "Artillery"}, {"gun-turret", "Guns"}, {"laser-turret", "Lasers"}, {"collision", "Hit hull"}}
local COMPUTER_POS = {6.5, -18.5}

local function virtual(name) return {type = "virtual", name = name, quality = "normal"} end

local function build_ship()
  local force = game.forces.player
  force.unlock_space_location("vulcanus")
  local platform = force.create_space_platform{name = "Artillery test", planet = "nauvis",
    starter_pack = "space-platform-starter-pack"}
  local hub = platform.apply_starter_pack()
  hub.destructible = false -- keeps the playtest going if things go badly
  local s = platform.surface
  for x = -8, 8 do for y = -8, 8 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()
  local tiles = {}
  for x = -20, 20 do for y = -32, 34 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
  s.set_tiles(tiles)

  local function make(name, pos, extra)
    local e = s.create_entity{name = name, position = pos, force = force, raise_built = true,
      direction = defines.direction.north}
    if not e then say("could not place %s at (%.1f,%.1f)", name, pos[1], pos[2]) end
    if e and extra then extra(e) end
    return e
  end
  storage.artillery = {}
  for _, pos in pairs{{-12, -22}, {0, -24}, {12, -22}, {0, -14}} do
    storage.artillery[#storage.artillery + 1] = make("artillery-turret", pos, function(e)
      e.insert{name = "artillery-shell", count = 15}
    end)
  end
  if storage.case ~= "tc-unpowered" then
    for _, pos in pairs{{-4, -26}, {4, -26}} do make("electric-energy-interface", pos) end
  end
  for _, pos in pairs{{-10, -26}, {10, -26}} do make("substation", pos) end
  for x = -18, 18, 4 do make("laser-turret", {x, -29}) end
  -- close-in layer: lasers barely scratch medium asteroids (90% laser resistance)
  storage.guns = {}
  for x = -16, 16, 4 do
    storage.guns[#storage.guns + 1] = make("gun-turret", {x, -31}, function(e)
      e.insert{name = "piercing-rounds-magazine", count = 20}
    end)
  end
  storage.thrusters = {}
  for _, pos in pairs{{-8, 24}, {8, 24}} do storage.thrusters[#storage.thrusters + 1] = make("thruster", pos) end

  local case = storage.case
  if case ~= "tc-none" and case ~= "perf-idle" then storage.computer = make("aa-targeting-computer", COMPUTER_POS) end
  local function wire_cc(target, pos, slots)
    local cc = make("constant-combinator", pos)
    local section = cc.get_or_create_control_behavior().sections[1] or cc.get_control_behavior().add_section()
    for i, sl in pairs(slots) do section.set_slot(i, {value = virtual(sl[1]), min = sl[2]}) end
    return cc.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      .connect_to(target.get_wire_connector(defines.wire_connector_id.circuit_red, true))
  end
  -- computer settings are applied on tick 1 (the mod's on_init runs after ours)
  local comp = storage.computer and storage.computer.unit_number
  storage.pending_cfg = {}
  if case == "tc-zone" or case == "tc-blueprint" then
    -- medium only, north, 90° wide
    storage.pending_cfg[comp] = {sizes = {medium = true}, dir = 0, arc = 90}
  elseif case == "tc-signals" then
    -- minimum size 2 (medium) from the default S signal
    say("tc-signals wired=%s", tostring(wire_cc(storage.computer, {9.5, -16.5}, {{"signal-S", 2}})))
    storage.pending_cfg[comp] = {use = {size = true}}
  elseif case == "tc-pick" then
    -- minimum size read from X instead of S; the wire carries X=2 and a misleading S=1
    say("tc-pick wired=%s", tostring(wire_cc(storage.computer, {9.5, -16.5}, {{"signal-X", 2}, {"signal-S", 1}})))
    storage.pending_cfg[comp] = {use = {size = true}, signals = {size = virtual("signal-X")}}
  elseif case == "tc-ignore" then
    -- S=4 on the wire, but the size input is not switched on: small asteroids still targeted
    say("tc-ignore wired=%s", tostring(wire_cc(storage.computer, {9.5, -16.5}, {{"signal-S", 4}})))
  elseif case == "tc-chunk" then
    -- metallic only, via the type slots
    storage.pending_cfg[comp] = {chunks = {"metallic-asteroid-chunk"}}
  elseif case == "tc-wires" then
    -- two computers with separate wires: A medium+ by signal, B small-only by settings
    say("tc-wires wired=%s", tostring(wire_cc(storage.computer, {9.5, -16.5}, {{"signal-S", 2}})))
    storage.computer_b = make("aa-targeting-computer", {-6.5, -18.5})
    storage.pending_cfg[comp] = {use = {size = true}}
    storage.pending_cfg[storage.computer_b.unit_number] = {sizes = {small = true}}
  end

  platform.schedule = {current = 1, records = {{station = "vulcanus"}, {station = "nauvis"}}}
  platform.paused = true -- departs once a player is aboard (see board)
  storage.platform = platform
end

-- stats ---------------------------------------------------------------------------------

script.on_event(defines.events.on_entity_died, function(e)
  local ent = e.entity
  local st = storage.stats
  if ent.type == "asteroid" then
    local size = ent.name:match("^(%a+)%-") or "?"
    local cause = e.cause and e.cause.name or "collision"
    st.kills[size] = st.kills[size] or {}
    st.kills[size][cause] = (st.kills[size][cause] or 0) + 1
  elseif ent.force.name == "player" then
    st.lost = st.lost + 1
  end
end)

local function summary_line()
  local st = storage.stats
  local kills, hull = 0, 0
  for _, by in pairs(st.kills) do
    kills = kills + (by["artillery-turret"] or 0)
    hull = hull + (by["collision"] or 0)
  end
  return string.format("%d s, %d shells, %d artillery kills (%.2f per shell), %d hit the hull, %d buildings lost, %d decoys",
    math.floor((game.tick - st.start) / 60), st.shells, kills, kills / math.max(st.shells, 1), hull, st.lost,
    remote.call("awesome-artillery", "decoy_count"))
end

-- controls ------------------------------------------------------------------------------

local function apply_research()
  local f, lv = game.forces.player, storage.levels
  f.set_ammo_damage_modifier("artillery-shell", 0.1 * lv.damage)
  f.set_gun_speed_modifier("artillery-shell", 1.0 * lv.rate)
  remote.call("awesome-artillery", "reset_damage")
  game.print(string.format("Artillery damage +%d%%, fire rate +%d%%", 10 * lv.damage, 100 * lv.rate))
end

-- panel ---------------------------------------------------------------------------------

local function button(parent, name, caption, tooltip, width)
  local b = parent.add{type = "button", name = name, caption = caption, tooltip = tooltip}
  b.style.width = width or 72
  return b
end

-- Manual checks before release: caption, how to check (tooltip).
local CHECKLIST = {
  {"Decoys: not on the map, no alerts",
    "Let the artillery fire for a while. Open the map (M): no enemy markers around the ship. No alerts at the bottom right."},
  {"Blueprint keeps computer settings",
    "Change the computer's settings (e.g. medium only, 90° north). Copy it (Ctrl+C) and paste it on free foundation. Once the platform builds it, open it: same settings."},
  {"Library blueprint keeps settings",
    "Put a blueprint in the library, then use its \"Select new contents\" on a configured computer. Build from that blueprint: same settings."},
  {"Copy-paste settings",
    "Shift+right-click a configured computer, then Shift+left-click another: it takes the settings."},
  {"Save and load mid-flight",
    "Save during flight (Esc → Save game), then load it. Artillery keeps firing; \"Show decoys and zones\" shows the decoys moving."},
  {"Multiplayer (optional)",
    "Host the save (Multiplayer → Host saved game) and join from a second client. Fly for a few minutes: no desync."},
}

local function build_gui(p)
  if p.gui.left.aa_panel then p.gui.left.aa_panel.destroy() end
  local f = p.gui.left.add{type = "frame", name = "aa_panel", caption = "Artillery playtest", direction = "vertical"}
  f.style.width = 440
  local inner = f.add{type = "frame", name = "inner", style = "inside_shallow_frame_with_padding", direction = "vertical"}
  inner.style.horizontally_stretchable = true

  inner.add{type = "label", name = "summary", style = "bold_label"}
  local stats = inner.add{type = "table", name = "stats", column_count = 1 + #CAUSES, draw_horizontal_line_after_headers = true}
  stats.style.horizontal_spacing = 16
  stats.add{type = "label", caption = "Asteroid", style = "bold_label"}
  for _, c in pairs(CAUSES) do stats.add{type = "label", caption = c[2], style = "bold_label"} end
  for _, size in pairs(SIZES) do
    stats.add{type = "label", caption = size}
    for _, c in pairs(CAUSES) do stats.add{type = "label", name = size .. "|" .. c[1], caption = "0"} end
  end

  inner.add{type = "line"}
  local ctl = inner.add{type = "table", name = "controls", column_count = 2, vertical_centering = true}
  ctl.style.vertical_spacing = 6
  local function control(label, tooltip)
    ctl.add{type = "label", caption = label, tooltip = tooltip}.style.width = 130
    return ctl.add{type = "flow", direction = "horizontal"}
  end

  local sp = control("Speed", "Platform speed while travelling")
  for _, v in pairs(SPEEDS) do
    button(sp, "aa_speed_" .. v, v == 0 and "Thrusters" or tostring(v),
      v == 0 and "Let the thrusters drive (about 2)" or ("Force platform speed " .. v), v == 0 and 88 or 48)
  end

  local function stepper(name, label, tooltip)
    local r = control(label, tooltip)
    button(r, "aa_" .. name .. "_minus", "-", nil, 32)
    local ro = r.add{type = "label", name = "aa_" .. name .. "_readout"}
    ro.style.width = 110
    ro.style.horizontal_align = "center"
    button(r, "aa_" .. name .. "_plus", "+", nil, 32)
  end
  stepper("damage", "Damage research", "Artillery shell damage, +10% per level (steps of 5 levels)")
  stepper("rate", "Fire-rate research", "Artillery shooting speed, +100% per level")

  local ms = control("Smallest target", "Mod setting: smallest asteroid artillery will shoot")
  ms.add{type = "drop-down", name = "aa_min_size", items = SIZES}.style.width = 120

  local tg = control("Options")
  tg.add{type = "checkbox", name = "aa_refill", caption = "Refill shells", state = storage.refill,
    tooltip = "Top up every artillery turret to 15 shells each second"}
  tg.add{type = "checkbox", name = "aa_debug", caption = "Show decoys and zones", state = storage.debug,
    tooltip = "Red circle = decoy (aim point), line from its asteroid; blue = every computer's zone"}

  inner.add{type = "line"}
  local b = inner.add{type = "flow", direction = "horizontal"}
  button(b, "aa_add_computer", "Add computer", "Place another targeting computer near the hub (powered)", 120)
  button(b, "aa_shot", "Screenshot", "Save your current view without the UI to script-output", 110)
  button(b, "aa_shot_ui", "With UI", "Save your current view including the UI to script-output", 90)

  inner.add{type = "line"}
  local h = inner.add{type = "flow", direction = "horizontal", vertical_centering = true}
  h.add{type = "label", name = "aa_checklist_title", style = "bold_label"}
  h.add{type = "empty-widget"}.style.horizontally_stretchable = true
  button(h, "aa_give_computers", "Computers to hub", "Put 5 targeting computers into the hub, so the platform can build your blueprints and pastes", 150)
  for i, item in pairs(CHECKLIST) do
    inner.add{type = "checkbox", name = "aa_check_" .. i, caption = item[1], tooltip = item[2], state = storage.checklist[i] or false}
  end
end

local function refresh_gui(p)
  local f = p.gui.left.aa_panel
  if not f then return end
  local inner = f.inner
  inner.summary.caption = summary_line()
  local done = 0
  for i in pairs(CHECKLIST) do if storage.checklist[i] then done = done + 1 end end
  for _, el in pairs(inner.children) do
    if el.aa_checklist_title then el.aa_checklist_title.caption = string.format("Release checklist: %d/%d", done, #CHECKLIST) end
  end
  for _, size in pairs(SIZES) do
    for _, c in pairs(CAUSES) do
      inner.stats[size .. "|" .. c[1]].caption = tostring((storage.stats.kills[size] or {})[c[1]] or 0)
    end
  end
  local ctl, lv = inner.controls, storage.levels
  for _, el in pairs(ctl.children) do
    if el.aa_damage_readout then el.aa_damage_readout.caption = string.format("%d (+%d%%)", lv.damage, 10 * lv.damage) end
    if el.aa_rate_readout then el.aa_rate_readout.caption = string.format("%d (+%d%%)", lv.rate, 100 * lv.rate) end
    if el.aa_min_size then
      for i, s in pairs(SIZES) do
        if s == settings.global["aa-min-size"].value and el.aa_min_size.selected_index ~= i then el.aa_min_size.selected_index = i end
      end
    end
    for _, v in pairs(SPEEDS) do
      local btn = el["aa_speed_" .. v]
      if btn then btn.toggled = (storage.forced_speed or 0) == v end
    end
  end
end

local function refresh_all() for _, p in pairs(game.connected_players) do refresh_gui(p) end end

script.on_event(defines.events.on_gui_click, function(e)
  local name = e.element.valid and e.element.name or ""
  if name:sub(1, 3) ~= "aa_" then return end
  local p = game.get_player(e.player_index)
  local lv = storage.levels
  local speed = name:match("^aa_speed_(%d+)$")
  if speed then
    speed = tonumber(speed)
    storage.forced_speed = speed > 0 and speed or nil
    game.print(speed > 0 and ("Platform speed forced to " .. speed) or "Platform speed back to thrusters")
  elseif name == "aa_damage_plus" then lv.damage = lv.damage + 5; apply_research()
  elseif name == "aa_damage_minus" then lv.damage = math.max(0, lv.damage - 5); apply_research()
  elseif name == "aa_rate_plus" then lv.rate = lv.rate + 1; apply_research()
  elseif name == "aa_rate_minus" then lv.rate = math.max(0, lv.rate - 1); apply_research()
  elseif name == "aa_add_computer" then
    local s = storage.platform.surface
    local pos = s.find_non_colliding_position("aa-targeting-computer", COMPUTER_POS, 8, 0.5)
    local c = pos and s.create_entity{name = "aa-targeting-computer", position = pos, force = "player", raise_built = true}
    p.print(c and string.format("Targeting computer placed at (%.1f, %.1f).", pos.x, pos.y) or "No free spot near the hub.")
  elseif name == "aa_give_computers" then
    local hub = storage.platform.hub
    local n = hub and hub.valid and hub.get_inventory(defines.inventory.hub_main).insert{name = "aa-targeting-computer", count = 5} or 0
    p.print(n .. " targeting computers put into the hub.")
  elseif name == "aa_shot" or name == "aa_shot_ui" then
    local path = string.format("awesome-artillery-%d%s.png", game.tick, name == "aa_shot_ui" and "-ui" or "")
    game.take_screenshot{player = p, resolution = {1920, 1080}, show_gui = name == "aa_shot_ui", path = path}
    p.print("Screenshot saved: script-output/" .. path)
  end
  refresh_all()
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  local el = e.element
  if el.name ~= "aa_min_size" then return end
  remote.call("awesome-artillery", "set_min_size", SIZES[el.selected_index])
  game.print("Artillery now targets " .. SIZES[el.selected_index] .. " asteroids and up.")
  refresh_all()
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local el = e.element
  local check = tonumber(el.name:match("^aa_check_(%d+)$"))
  if check then
    storage.checklist[check] = el.state
    for _, p in pairs(game.connected_players) do
      local f = p.gui.left.aa_panel
      if f and f.inner[el.name] then f.inner[el.name].state = el.state end
    end
    return refresh_all()
  end
  if el.name == "aa_refill" then storage.refill = el.state
  elseif el.name == "aa_debug" then
    storage.debug = el.state
    remote.call("awesome-artillery", "set_debug", el.state)
  else return end
  for _, p in pairs(game.connected_players) do
    local f = p.gui.left.aa_panel
    if f then
      for _, row in pairs(f.inner.controls.children) do
        if row[el.name] then row[el.name].state = el.state end
      end
    end
  end
end)

-- boarding ------------------------------------------------------------------------------

local function depart()
  local pf = storage.platform
  if pf and pf.valid and pf.paused then
    pf.paused = false
    say("platform departing")
    game.print("Platform departing for Vulcanus.")
  end
end

-- Put the player on the platform; fall back to remote view of it. Retried every second.
local function board(p)
  local pf = storage.platform
  if not (pf and pf.valid) or storage.boarded[p.index] then return end
  local ok, entered = pcall(p.enter_space_platform, pf)
  if ok and entered then
    storage.boarded[p.index] = true
    say("player %s boarded (enter_space_platform)", p.name)
  else
    say("enter_space_platform failed: %s", tostring(entered))
    local ok2, err2 = pcall(p.set_controller, {type = defines.controllers.remote, surface = pf.surface, position = {0, -10}})
    if ok2 then
      storage.boarded[p.index] = true
      say("player %s viewing platform (remote controller)", p.name)
    else
      say("remote controller failed: %s", tostring(err2))
      storage.board_tries = (storage.board_tries or 0) + 1
      if storage.board_tries <= 3 then p.print("Could not board the platform; retrying.") end
      return
    end
  end
  p.print("You are on the artillery test platform. Use the panel on the left.")
  depart()
end

-- headless checks ------------------------------------------------------------------------

-- Per-case invariants, checked every second; returns an error or nil.
local function check_case()
  local case, decoys = storage.case, remote.call("awesome-artillery", "decoy_list")
  if case == "tc-none" or case == "tc-unpowered" then
    if #decoys > 0 or storage.stats.shells > 0 then
      return string.format("%d decoys, %d shells without a working computer", #decoys, storage.stats.shells)
    end
  elseif case == "tc-zone" then
    local c = storage.computer.position
    for _, d in pairs(decoys) do
      local angle = math.deg(math.atan2(d.x - c.x, -(d.y - c.y))) % 360
      local off = math.abs((angle + 180) % 360 - 180)
      if not d.name:find("^medium") or off > 45 + 0.5 then
        return string.format("decoy %s at angle %.0f° outside medium/north-90° zone", d.name, angle)
      end
    end
  elseif case == "tc-signals" or case == "tc-pick" then
    for _, d in pairs(decoys) do
      if d.name:find("^small") then return "decoy for " .. d.name .. " despite minimum size 2 from the wire" end
    end
  elseif case == "tc-chunk" then
    for _, d in pairs(decoys) do
      if not d.name:find("metallic") then return "decoy for " .. d.name .. " despite metallic-only type slot" end
    end
  end
end

-- Checks over the whole run; returns an error or nil.
local function check_end()
  local seen = function(prefix)
    for k in pairs(storage.observed) do if k:find("^" .. prefix) then return true end end
  end
  local case = storage.case
  if case == "tc-wires" and not (seen("small") and seen("medium")) then
    return "expected both medium (computer A, by wire) and small (computer B, own settings) decoys"
  end
  if (case == "tc-signals" or case == "tc-pick" or case == "tc-zone") and not seen("medium") then
    return "no medium decoys at all: the filter blocked everything"
  end
  if case == "tc-ignore" and not seen("small") then return "no small decoys: an unticked input was read" end
  if case == "tc-chunk" and not seen("medium%-metallic") then return "no metallic decoys at all" end
end

-- lifecycle -----------------------------------------------------------------------------

script.on_init(function()
  storage.stats = {kills = {}, lost = 0, shells = 0, start = game.tick}
  storage.refill = true
  storage.debug = false
  storage.levels = {damage = 0, rate = 0}
  storage.forced_speed = nil
  storage.boarded = {}
  storage.observed = {}
  storage.checklist = {}
  -- start every playtest with small asteroids targeted (a saved mod setting would win otherwise)
  remote.call("awesome-artillery", "set_min_size", "small")
  local arg = script.test_arg
  -- update interval: from the case name ("perf-i30", "check-i60"), else the default 30
  local interval = arg and tonumber(arg:match("%-i(%d+)")) or 30
  remote.call("awesome-artillery", "set_interval", interval)
  if arg then
    storage.case = arg:match("^(%S+)")
    storage.test_until = tonumber(arg:match("%s(%d+)")) or 3600
  end
  build_ship()
  if arg then say("update interval %d ticks", settings.global["aa-update-interval"].value) end
  if arg and storage.case:find("^perf") then
    storage.forced_speed = tonumber(storage.case:match("%-s(%d+)")) or 10
    say("forced platform speed %d", storage.forced_speed)
    -- keep the whole ship alive so the load stays representative
    for _, ent in pairs(storage.platform.surface.find_entities_filtered{force = "player"}) do ent.destructible = false end
  end
  if arg then
    say("headless %s for %d ticks", storage.case, storage.test_until)
    depart() -- no player to wait for
  end
end)

script.on_event(defines.events.on_player_created, function(e)
  local p = game.get_player(e.player_index)
  p.cheat_mode = true
  build_gui(p)
  refresh_gui(p)
  board(p)
end)

script.on_event(defines.events.on_tick, function(e)
  for _, th in pairs(storage.thrusters) do
    if th and th.valid then
      th.insert_fluid{name = "thruster-fuel", amount = 1000}
      th.insert_fluid{name = "thruster-oxidizer", amount = 1000}
    end
  end
  local pf = storage.platform
  if storage.forced_speed and pf and pf.valid and pf.space_connection then
    pf.speed = storage.forced_speed
    -- perf runs stay in transit (loop back along the route before arriving)
    if storage.case and storage.case:find("^perf") and pf.distance > 0.8 then pf.distance = 0.2 end
  end
  if e.tick == 1 then
    -- the mod's on_init runs after ours, so computer settings are applied here
    for unit, cfg in pairs(storage.pending_cfg or {}) do
      if cfg.sizes then -- listed sizes only
        for _, s in pairs(SIZES) do cfg.sizes[s] = cfg.sizes[s] or false end
      end
      remote.call("awesome-artillery", "set_computer_cfg", unit, cfg)
    end
  end
  if e.tick == 2 and storage.test_until and storage.computer then
    -- build the computer's window headless so GUI mistakes fail the test
    for _, p in pairs(game.players) do remote.call("awesome-artillery", "open_computer", p.index, storage.computer.unit_number) end
    say("computer window opened for %d player(s)", #game.players)
  end
  if e.tick % 60 == 0 then
    for _, p in pairs(game.connected_players) do board(p) end
    for _, g in pairs(storage.guns or {}) do
      if g and g.valid then
        local n = g.get_inventory(defines.inventory.turret_ammo).get_item_count()
        if n < 20 then g.insert{name = "piercing-rounds-magazine", count = 20 - n} end
      end
    end
    if storage.refill then
      for _, t in pairs(storage.artillery) do
        if t and t.valid then
          local inv = t.get_inventory(defines.inventory.artillery_turret_ammo)
          local n = inv.get_item_count("artillery-shell")
          if n < 15 then
            storage.stats.shells = storage.stats.shells + 15 - n
            inv.insert{name = "artillery-shell", count = 15 - n}
          end
        end
      end
    end
    refresh_all()
  end
  -- vel: do existing asteroids keep their velocity when the platform changes speed?
  if storage.test_until and storage.case == "perf-vel" then
    local V = storage.vel or {track = {}, changes = {}, samples = 0}
    storage.vel = V
    local s = pf.surface
    if e.tick == 600 then storage.forced_speed = 20; say("t=600 platform speed 10 -> 20") end
    if e.tick % 10 == 0 and e.tick >= 300 then
      for _, a in pairs(s.find_entities_filtered{type = "asteroid", position = {0, 0}, radius = 200}) do
        local id = a.unit_number
        local p = a.position
        local tr = V.track[id]
        if tr then
          local vx, vy = (p.x - tr.x) / 10, (p.y - tr.y) / 10
          if tr.vx then
            local dv = math.sqrt((vx - tr.vx) ^ 2 + (vy - tr.vy) ^ 2)
            local phase = (tr.born < 600 and e.tick > 600) and "spans-change" or "steady"
            V.changes[phase] = V.changes[phase] or {n = 0, max = 0, sum = 0}
            local c = V.changes[phase]
            c.n, c.max, c.sum = c.n + 1, math.max(c.max, dv), c.sum + dv
            if tr.born < 600 and e.tick > 600 and not tr.reported and #V < 5 then
              V[#V + 1] = true
              tr.reported = true
              say("asteroid %d (seen before change): v before (%.4f,%.4f) now (%.4f,%.4f)", id, tr.v0x, tr.v0y, vx, vy)
            end
          else
            tr.v0x, tr.v0y = vx, vy
          end
          tr.x, tr.y, tr.vx, tr.vy = p.x, p.y, vx, vy
        else
          V.track[id] = {x = p.x, y = p.y, born = e.tick}
        end
      end
    end
    if e.tick >= storage.test_until then
      for phase, c in pairs(V.changes) do
        say("%s: %d samples, velocity change per 10 ticks: mean %.5f max %.5f tiles/tick", phase, c.n, c.sum / c.n, c.max)
      end
      return script.finish_test(true)
    end
    return
  end
  -- who: when a turret fires, which decoy did it aim at, and was that turret the nearest one?
  if storage.test_until and storage.case == "perf-who" then
    local W = storage.who or {ammo = {}, shots = 0, nearest = 0, ranks = {}, matched = 0}
    storage.who = W
    for i, t in pairs(storage.artillery) do
      local n = t.get_inventory(defines.inventory.artillery_turret_ammo).get_item_count("artillery-shell")
      if W.ammo[i] and n < W.ammo[i] then
        W.shots = W.shots + 1
        -- decoy whose bearing from this turret matches the barrel direction
        local o = t.relative_turret_orientation
        local best, best_off
        for _, d in pairs(remote.call("awesome-artillery", "decoy_list")) do
          local b = (math.atan2(d.x - t.position.x, -(d.y - t.position.y)) / (2 * math.pi)) % 1
          local off = math.abs((b - o + 0.5) % 1 - 0.5)
          if not best_off or off < best_off then best, best_off = d, off end
        end
        if best and best_off < 0.01 then
          W.matched = W.matched + 1
          local mine = (best.x - t.position.x) ^ 2 + (best.y - t.position.y) ^ 2
          local rank = 1
          for j, u in pairs(storage.artillery) do
            if j ~= i and (best.x - u.position.x) ^ 2 + (best.y - u.position.y) ^ 2 < mine then rank = rank + 1 end
          end
          W.ranks[rank] = (W.ranks[rank] or 0) + 1
        end
      end
      W.ammo[i] = n
    end
    if e.tick >= storage.test_until then
      local parts = {}
      for r = 1, #storage.artillery do parts[#parts + 1] = string.format("rank %d: %d", r, W.ranks[r] or 0) end
      say("shots=%d matched to a decoy=%d; firing turret's distance rank among turrets: %s",
        W.shots, W.matched, table.concat(parts, ", "))
      return script.finish_test(true)
    end
    return
  end
  -- blueprint: a computer built from a ghost with the settings tag gets those settings
  -- (the blueprint setup side needs a player selection; check that in a real game)
  if storage.test_until and storage.case == "tc-blueprint" then
    if e.tick == 5 then
      local src = remote.call("awesome-artillery", "computer_cfg", storage.computer.unit_number)
      local ghost = pf.surface.create_entity{name = "entity-ghost", inner_name = "aa-targeting-computer",
        position = {-6.5, -18.5}, force = "player", tags = {aa_cfg = src}}
      local _, built = ghost.revive{raise_revive = true}
      local got = built and remote.call("awesome-artillery", "computer_cfg", built.unit_number)
      local a, b = serpent.line(src, {sortkeys = true}), serpent.line(got, {sortkeys = true})
      say("source cfg: %s", a)
      say("built cfg:  %s", b)
      return script.finish_test(built ~= nil and a == b and src.arc == 90)
    end
    return
  end
  -- tech: the computer is researched, not available from the start, and needs rare+ chips
  if storage.test_until and storage.case == "tech" then
    local tech, recipe = prototypes.technology["aa-targeting-computer"], prototypes.recipe["aa-targeting-computer"]
    local prereqs = {}
    for name in pairs(tech.prerequisites) do prereqs[#prereqs + 1] = name end
    table.sort(prereqs)
    say("tech prerequisites: %s; cost %d", table.concat(prereqs, ", "), tech.research_unit_count)
    for _, i in pairs(recipe.ingredients) do
      say("ingredient %s x%d quality_min=%s", i.name, i.amount, tostring(i.quality_min))
    end
    local enabled = game.forces.player.recipes["aa-targeting-computer"].enabled
    say("recipe enabled at start: %s", tostring(enabled))
    return script.finish_test(not enabled and tech.prerequisites["electromagnetic-science-pack"] ~= nil
      and tech.prerequisites["metallurgic-science-pack"] ~= nil)
  end
  if storage.test_until and storage.case:find("^perf") then
    if e.tick == 600 then
      remote.call("awesome-artillery", "profile_start")
      say("profiling from t=600")
    end
    if e.tick >= storage.test_until then
      remote.call("awesome-artillery", "profile_report")
      say("%s", summary_line())
      return script.finish_test(true)
    end
    return
  end
  if storage.test_until then
    -- decoys of rarer sizes live briefly: sample often so check_end sees them
    if e.tick % 5 == 0 then
      for name, n in pairs(remote.call("awesome-artillery", "decoys_by_name")) do
        storage.observed[name] = (storage.observed[name] or 0) + n
      end
    end
    if e.tick % 60 == 0 then
      local err = check_case()
      if err then
        say("FAIL t=%d: %s", e.tick, err)
        return script.finish_test(false)
      end
    end
    if e.tick >= storage.test_until then
      local names = {}
      for k, v in pairs(storage.observed) do names[#names + 1] = k .. "=" .. v end
      table.sort(names)
      say("decoy samples: %s", table.concat(names, " "))
      say("%s", summary_line())
      local err = check_end()
      if err then say("FAIL: %s", err) end
      script.finish_test(err == nil)
    end
  end
end)
