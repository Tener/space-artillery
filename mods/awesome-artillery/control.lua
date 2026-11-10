-- Decoy controller: manages artillery targeting for asteroids.
-- Features:
-- 1. Wired computer binding: artillery turrets wired via red/green circuit network to a
--    Targeting Computer are controlled exclusively by that computer.
-- 2. Pure-stickiness orientation optimization: cannons prioritize targets closest to their
--    current barrel orientation to eliminate unnecessary swivel latencies.
-- 3. In-flight damage tracking: avoids wasting shells on asteroids already doomed.

local balance = require("constants")
local computer = require("__awesome-artillery__/scripts/computer")
local targeting = require("__awesome-artillery__/scripts/targeting")

local SIZE_RANK = {small = 1, medium = 2, big = 3, huge = 4}
-- Artillery shell damage by ammo name (projectile prototypes aren't readable at runtime).
local SHELLS = balance.shells
local BLAST_RADIUS = 4
local FOUNDATION = "space-platform-foundation"
local BUILD_FILTER = {
  {filter = "type", type = "artillery-turret"},
  {filter = "name", name = computer.NAME, mode = "or"},
  {filter = "ghost_name", name = computer.NAME, mode = "or"},
}
local ASTEROID_FILTER = {{filter = "type", type = "asteroid"}}
local BALLISTICS_TECH = "awe-art-asteroid-ballistics"
local PROMETHIUM_BALLISTICS_TECH = "awe-art-promethium-ballistics"
local BALLISTICS_KILLS = balance.ballistics_kills
local BALLISTICS_CHUNKS = {"metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk"}
local MAX_ROTATION_LEVEL = balance.rotation_levels
local VELOCITY_STEP = balance.velocity_percent / 100

local function constants()
  if not storage.const then
    local gun = prototypes.item["artillery-wagon-cannon"].attack_parameters
    local speed = 1
    pcall(function()
      speed = prototypes.item["artillery-shell"].get_ammo_type().action[1].action_delivery[1].starting_speed or 1
    end)
    storage.const = {range = gun.range, min_range = gun.min_range or 0, shell_speed = speed}
  end
  return storage.const
end

local function init_storage()
  storage.turrets = storage.turrets or {}   -- surface index -> unit_number -> turret
  storage.tracked = storage.tracked or {}   -- registration number -> {a, d, surface, slot, seen, ...}
  storage.ctx = storage.ctx or {}           -- surface index -> ctx from the surface's last scan
  storage.surface_topo = storage.surface_topo or {} -- surface index -> topology
  storage.interval = nil                    -- forces a bucket rebuild on the next tick
  storage.damage = {}                       -- force|shell -> asteroid name -> damage per shell
  storage.kills = storage.kills or {}       -- force index -> chunk name -> medium/big/huge artillery kills
  storage.promethium_killed = storage.promethium_killed or {} -- force index -> bool
  storage.debug = storage.debug or false
  storage.const = nil
  computer.init()
end

local function rotation_turret_name(force)
  for level = MAX_ROTATION_LEVEL, 1, -1 do
    local tech = force.technologies["awe-art-artillery-rotation-" .. level]
    if tech and tech.researched then return "awe-art-artillery-turret-r" .. level end
  end
  return "artillery-turret"
end

local function shell_velocity_mult(force)
  local tech = force and force.technologies["awe-art-artillery-shell-velocity-1"]
  if not tech then return 1 end
  local levels = (tech.level or 1) - 1
  if tech.researched then levels = levels + 1 end
  return 1 + VELOCITY_STEP * math.max(0, levels)
end

local function sync_turret_rotation(t)
  if not (t and t.valid and t.type == "artillery-turret") then return t end
  local want = rotation_turret_name(t.force)
  if t.name == want or not prototypes.entity[want] then return t end
  local s, u = t.surface, t.unit_number
  local list = storage.turrets and storage.turrets[s.index]
  if list and u then list[u] = nil end
  local dir, pos, force, qual, hp, kills, dmg, orient =
    t.direction, t.position, t.force, t.quality, t.health, t.kills, t.damage_dealt, t.relative_turret_orientation
  local replaced = s.create_entity{
    name = want, position = pos, direction = dir, force = force, quality = qual,
    fast_replace = true, spill = false, create_build_effect_smoke = false,
  }
  if replaced and replaced.valid then
    replaced.health = hp
    replaced.kills = kills
    replaced.damage_dealt = dmg
    replaced.relative_turret_orientation = orient
    return replaced
  end
  return t
end

local function add_turret(t)
  if not (t and t.valid and t.type == "artillery-turret") then return end
  t = sync_turret_rotation(t)
  if not (t and t.valid and t.surface.platform) then return end
  local list = storage.turrets[t.surface.index] or {}
  list[t.unit_number] = t
  storage.turrets[t.surface.index] = list
  if storage.surface_topo then storage.surface_topo[t.surface.index] = nil end
end

local function rescan()
  storage.turrets = {}
  storage.surface_topo = {}
  for _, s in pairs(game.surfaces) do
    for _, t in pairs(s.find_entities_filtered{type = "artillery-turret"}) do add_turret(t) end
  end
end

-- size rank from the data-stage catalogue (works for modded asteroids)
local function size_of(name)
  local info = computer.catalogue()[name]
  return info and info.size or 0
end

local function shell_damage(force, shell, name)
  local key = force.index .. "|" .. shell
  local per_force = storage.damage[key] or {}
  storage.damage[key] = per_force
  if per_force[name] then return per_force[name] end
  local resist = prototypes.entity[name].resistances or {}
  local mult = 1 + force.get_ammo_damage_modifier("artillery-shell")
  local total = 0
  for type, amount in pairs(SHELLS[shell] or SHELLS["artillery-shell"]) do
    local r = resist[type] or {decrease = 0, percent = 0}
    local d = amount * mult - r.decrease
    if d > 0 then total = total + d * (1 - r.percent) end
  end
  per_force[name] = total
  return total
end

local function eligible(name, health, force, ctx)
  if size_of(name) < ctx.min_rank then return false end
  local dmg = shell_damage(force, ctx.shell, name)
  return dmg > 0 and health / dmg <= ctx.max_shells
end

local function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

local function intercept(px, py, vx, vy, ctx)
  px, py = px + vx * ctx.half_interval, py + vy * ctx.half_interval
  local rx, ry = px - ctx.cx, py - ctx.cy
  local s = ctx.shell_speed
  local a = vx * vx + vy * vy - s * s
  local b = 2 * (rx * vx + ry * vy)
  local c = rx * rx + ry * ry
  local t = (-b - math.sqrt(b * b - 4 * a * c)) / (2 * a)
  local d = s * t
  if d < ctx.reach_min or d > ctx.reach_max then return nil end
  return px + vx * t, py + vy * t
end

local function hull_boxes(s)
  storage.hull = storage.hull or {}
  local h = storage.hull[s.index]
  if h and game.tick - h.tick < 600 then return h.boxes end
  local boxes = {}
  for chunk in s.get_chunks() do
    local tiles = s.find_tiles_filtered{area = chunk.area, name = FOUNDATION}
    if #tiles > 0 then
      local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
      for _, t in pairs(tiles) do
        local p = t.position
        x1, y1 = math.min(x1, p.x), math.min(y1, p.y)
        x2, y2 = math.max(x2, p.x + 1), math.max(y2, p.y + 1)
      end
      boxes[#boxes + 1] = {x1, y1, x2, y2}
    end
  end
  storage.hull[s.index] = {tick = game.tick, boxes = boxes}
  return boxes
end

local function invalidate_hull(e)
  if storage.hull and e.surface_index then storage.hull[e.surface_index] = nil end
end

local function safe(s, aim, ctx)
  local r = ctx.blast
  local x, y = aim[1], aim[2]
  for _, b in pairs(ctx.hull) do
    if x > b[1] - r and x < b[3] + r and y > b[2] - r and y < b[4] + r then
      return s.count_tiles_filtered{position = aim, radius = r, name = FOUNDATION, limit = 1} == 0
    end
  end
  return true
end

local function drop_decoy(tr)
  if tr.d and tr.d.valid then tr.d.destroy() end
  tr.d = nil
end

local TELEPORT_MIN = 0.5

local function assign_slot(id, tr)
  local slot = id % storage.interval
  tr.slot = slot
  local b = storage.buckets[slot] or {}
  b[id] = true
  storage.buckets[slot] = b
end

local function rebuild_buckets(interval)
  storage.buckets, storage.interval = {}, interval
  for id, tr in pairs(storage.tracked) do assign_slot(id, tr) end
end

local function track(id, tr)
  storage.tracked[id] = tr
  assign_slot(id, tr)
end

local function untrack(id)
  local tr = storage.tracked[id]
  if not tr then return end
  drop_decoy(tr)
  storage.tracked[id] = nil
  local b = storage.buckets[tr.slot]
  if b then b[id] = nil end
end

-- Refresh wire topology for surface
local function surface_topology(s_index, turrets, force)
  storage.surface_topo = storage.surface_topo or {}
  local topo = storage.surface_topo[s_index]
  if not force and topo and (game.tick - topo.tick < 300) then return topo end
  local new_topo = targeting.update_surface_topology(s_index, turrets, storage.computers or {})
  new_topo.tick = game.tick
  storage.surface_topo[s_index] = new_topo
  return new_topo
end

local function update_asteroid(tr, ctx)
  local s, force, rules, interval = ctx.s, ctx.force, ctx.rules, ctx.interval
  local a, p, name = tr.a, tr.a.position, tr.name
  local px, py = p.x, p.y
  local dt = game.tick - tr.tick
  if dt > 0 then tr.vx, tr.vy = (px - tr.lx) / dt, (py - tr.ly) / dt end
  tr.lx, tr.ly, tr.tick = px, py, game.tick
  local health = a.health
  local ax, ay
  if tr.vx and eligible(name, health, force, ctx) then ax, ay = intercept(px, py, tr.vx, tr.vy, ctx) end
  if not ax then return drop_decoy(tr) end
  local aim = tr.aim
  if not aim then aim = {ax, ay}; tr.aim = aim end
  local moved = (ax - aim[1]) ^ 2 + (ay - aim[2]) ^ 2 >= TELEPORT_MIN * TELEPORT_MIN
  aim[1], aim[2] = ax, ay
  if not safe(s, aim, ctx) then return drop_decoy(tr) end

  local topo = ctx.topo
  local matching_comps = {}
  local allowed_any = false

  if rules then
    for comp_unit, r in pairs(rules) do
      if computer.allows({r}, name, ax, ay) then
        allowed_any = true
        matching_comps[comp_unit] = true
      end
    end
    if not allowed_any then return drop_decoy(tr) end
  end

  -- Determine if any turret is authorized and available to shoot this target.
  -- 1. If any matching computer has wired turrets, assign target stickily among them.
  -- 2. If matching computer has no wired turrets, unwired platform turrets can engage.
  local candidate_turrets = {}
  local has_wired_system = false

  if topo then
    for comp_unit in pairs(matching_comps) do
      local wired = topo.comp_to_turrets[comp_unit]
      if wired and #wired > 0 then
        has_wired_system = true
        for _, t in pairs(wired) do
          if t.valid then candidate_turrets[#candidate_turrets + 1] = t end
        end
      end
    end

    if not has_wired_system and topo.unwired_turrets then
      for _, t in pairs(topo.unwired_turrets) do
        if t.valid then candidate_turrets[#candidate_turrets + 1] = t end
      end
    end
  end

  if #candidate_turrets == 0 then return drop_decoy(tr) end

  -- Sticky orientation: candidate turret closest to this heading is chosen
  local best_turret = targeting.pick_sticky_turret(candidate_turrets, ax, ay)
  if best_turret and best_turret.valid then
    best_turret.artillery_auto_targeting = true
  end

  if tr.d and tr.d.valid then
    if moved then tr.d.teleport(aim) end
  else
    tr.d = s.create_entity{name = "awe-art-decoy-" .. name, position = aim, force = "enemy"}
    tr.dh = nil
  end
  if tr.d and tr.dh ~= health then tr.d.health = health; tr.dh = health end

  if storage.debug then
    rendering.draw_circle{color = {1, 0.2, 0.2}, radius = 1, width = 2, target = aim, surface = s, time_to_live = interval + 1}
    rendering.draw_line{color = {1, 0.6, 0.2}, width = 1, from = a, to = aim, surface = s, time_to_live = interval + 1}
  end
end

-- Scan surface once per interval: collects turrets, builds topology, resets gated auto_targeting
local function scan_surface(s, turrets, interval)
  local c = constants()
  local force = s.platform.force
  local range = c.range * (1 + force.artillery_range_modifier)
  local g = settings.global
  local topo = surface_topology(s.index, turrets)

  -- Gate auto_targeting: any turret wired to a computer defaults to false until assigned a target
  for comp_unit, wired in pairs(topo.comp_to_turrets) do
    for _, t in pairs(wired) do
      if t.valid then t.artillery_auto_targeting = false end
    end
  end

  local ctx = {s = s, force = force, interval = interval, scan_tick = game.tick,
    min_rank = SIZE_RANK[g["awe-art-min-size"].value], max_shells = g["awe-art-max-shells"].value,
    blast = BLAST_RADIUS + g["awe-art-safety-margin"].value, hull = hull_boxes(s), topo = topo}
  storage.ctx[s.index] = ctx

  local cx, cy = 0, 0
  local positions = {}
  local has_promethium, has_tungsten, has_steel = false, false, false
  for i, t in pairs(turrets) do
    local p = t.position
    positions[i] = {p.x, p.y}
    cx, cy = cx + p.x, cy + p.y
    local inv = t.get_inventory(defines.inventory.artillery_turret_ammo)
    if inv then
      if inv.get_item_count("awe-art-promethium-artillery-shell") > 0 then has_promethium = true end
      if inv.get_item_count("artillery-shell") > 0 then has_tungsten = true end
      if inv.get_item_count("awe-art-steel-artillery-shell") > 0 then has_steel = true end
    end
  end
  ctx.shell = has_promethium and "awe-art-promethium-artillery-shell"
    or ((has_tungsten or not has_steel) and "artillery-shell" or "awe-art-steel-artillery-shell")
  cx, cy = cx / #turrets, cy / #turrets
  local spread = 0
  for _, t in pairs(positions) do spread = math.max(spread, dist(cx, cy, t[1], t[2])) end
  ctx.cx, ctx.cy, ctx.shell_speed, ctx.half_interval = cx, cy, c.shell_speed * shell_velocity_mult(force), interval / 2
  ctx.reach_min, ctx.reach_max = math.max(0, c.min_range - spread), range + spread

  local rules_by_comp, present = computer.rules(s.index)
  if not present and not settings.global["awe-art-require-computer"].value then
    rules_by_comp = nil
  end
  ctx.rules = rules_by_comp
  if rules_by_comp and next(rules_by_comp) == nil then return 0 end

  local found = s.find_entities_filtered{type = "asteroid", position = {cx, cy}, radius = range + spread}
  for _, a in pairs(found) do
    local id = script.register_on_object_destroyed(a)
    local tr = storage.tracked[id]
    if not tr then
      local p = a.position
      tr = {a = a, name = a.name, surface = s.index, lx = p.x, ly = p.y, tick = game.tick}
      track(id, tr)
    end
    tr.seen = game.tick
  end
  return #found
end

local function update_slot(slot)
  local bucket = storage.buckets[slot]
  if not bucket then return 0 end
  local n = 0
  for id in pairs(bucket) do
    local tr = storage.tracked[id]
    local ctx = storage.ctx[tr.surface]
    if not (ctx and tr.seen == ctx.scan_tick and tr.a.valid) then
      untrack(id)
    else
      n = n + 1
      update_asteroid(tr, ctx)
    end
  end
  return n
end

local function scan_due(tick, interval)
  local found = 0
  for index, list in pairs(storage.turrets) do
    if (tick + index) % interval == 0 then
      local s = game.get_surface(index)
      if not (s and s.valid and s.platform) then
        storage.turrets[index], storage.ctx[index] = nil, nil
        if storage.surface_topo then storage.surface_topo[index] = nil end
      else
        local turrets = {}
        for k, t in pairs(list) do
          if t.valid then turrets[#turrets + 1] = t else list[k] = nil end
        end
        if #turrets > 0 then found = found + scan_surface(s, turrets, interval) else storage.ctx[index] = nil end
      end
    end
  end
  return found
end

local P

local function update(tick, interval)
  if storage.interval ~= interval then rebuild_buckets(interval) end
  local found = scan_due(tick, interval)
  local n = update_slot(tick % interval)
  if tick % interval == 0 then computer.refresh_open() end
  return n, found
end

script.on_event(defines.events.on_tick, function(e)
  local interval = settings.global["awe-art-update-interval"].value
  if not P then return update(e.tick, interval) end
  local t = helpers.create_profiler()
  local n, found = update(e.tick, interval)
  t.stop()
  P.total.add(t)
  P.ticks, P.asteroids = P.ticks + 1, P.asteroids + n
  P.asteroids_max, P.found_max = math.max(P.asteroids_max, n), math.max(P.found_max, found)
end)

script.on_event(defines.events.on_object_destroyed, function(e) untrack(e.registration_number) end)

local function on_built(e)
  local ent = e.entity or e.destination
  if not (ent and ent.valid) then return end
  if computer.is_computer(ent) then
    computer.add(ent, e.tags)
    if storage.surface_topo and ent.surface then storage.surface_topo[ent.surface.index] = nil end
  else
    add_turret(ent)
  end
end
for _, ev in pairs{defines.events.on_built_entity, defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive} do
  script.on_event(ev, on_built, BUILD_FILTER)
end

for _, ev in pairs{defines.events.on_space_platform_built_tile, defines.events.on_space_platform_mined_tile,
  defines.events.on_player_built_tile, defines.events.on_robot_built_tile, defines.events.on_player_mined_tile,
  defines.events.on_robot_mined_tile, defines.events.script_raised_set_tiles} do
  script.on_event(ev, invalidate_hull)
end

local function prerequisites_researched(tech)
  for _, p in pairs(tech.prerequisites) do if not p.researched then return false end end
  return true
end

local function check_ballistics_tech(force)
  local tech = force.technologies[BALLISTICS_TECH]
  if tech and not tech.researched then
    local k = storage.kills[force.index]
    if k then
      local sum = 0
      for _, chunk in pairs(BALLISTICS_CHUNKS) do
        sum = sum + (k[chunk] or 0)
      end
      pcall(function() tech.saved_progress = math.min(0.999, sum / BALLISTICS_KILLS) end)
      if sum >= BALLISTICS_KILLS and prerequisites_researched(tech) then force.script_trigger_research(BALLISTICS_TECH) end
    end
  end
  local ptech = force.technologies[PROMETHIUM_BALLISTICS_TECH]
  if ptech and not ptech.researched and storage.promethium_killed[force.index] and prerequisites_researched(ptech) then
    force.script_trigger_research(PROMETHIUM_BALLISTICS_TECH)
  end
end

script.on_event(defines.events.on_entity_died, function(e)
  local info = computer.catalogue()[e.entity.name]
  if not (info and info.chunk and info.size >= 2) then return end
  local cause = e.cause
  local force = (cause and cause.valid and cause.force) or e.force
  if not force then return end
  if info.chunk == "promethium-asteroid-chunk" then
    storage.promethium_killed[force.index] = true
    check_ballistics_tech(force)
  end
  if not (cause and cause.valid and (cause.type == "artillery-turret" or cause.type == "artillery-wagon")) then return end
  local k = storage.kills[force.index] or {}
  storage.kills[force.index] = k
  k[info.chunk] = (k[info.chunk] or 0) + 1
  check_ballistics_tech(force)
end, ASTEROID_FILTER)

script.on_event(defines.events.on_trigger_fired_artillery, function(e)
  local proj = e.entity
  if not (proj and proj.valid) then return end
  local force = (e.source and e.source.valid and e.source.force) or proj.force
  local mult = shell_velocity_mult(force)
  if mult ~= 1 then proj.speed = proj.speed * mult end
end)

local function on_research_changed(e)
  storage.damage = {}
  rescan()
  if e.research and e.research.force then check_ballistics_tech(e.research.force) end
end
script.on_event(defines.events.on_research_finished, on_research_changed)
script.on_event(defines.events.on_research_reversed, on_research_changed)

script.on_init(function() init_storage(); rescan(); computer.rescan() end)
script.on_configuration_changed(function()
  init_storage()
  rescan()
  computer.rescan()
  for _, f in pairs(game.forces) do check_ballistics_tech(f) end
end)

commands.add_command("awe-art-debug", "Toggle drawing of artillery decoys (red circle = aim point).", function(cmd)
  storage.debug = not storage.debug
  local p = cmd.player_index and game.get_player(cmd.player_index)
  local msg = "awe-art-debug " .. (storage.debug and "on" or "off")
  if p then p.print(msg) else print(msg) end
end)

remote.add_interface("awesome-artillery", {
  decoy_count = function()
    local n = 0
    for _, tr in pairs(storage.tracked) do if tr.d and tr.d.valid then n = n + 1 end end
    return n
  end,
  decoy_list = function()
    local out = {}
    for _, tr in pairs(storage.tracked) do
      if tr.d and tr.d.valid and tr.a.valid then out[#out + 1] = {name = tr.a.name, x = tr.d.position.x, y = tr.d.position.y} end
    end
    return out
  end,
  decoys_by_name = function()
    local out = {}
    for _, tr in pairs(storage.tracked) do
      if tr.d and tr.d.valid and tr.a.valid then out[tr.a.name] = (out[tr.a.name] or 0) + 1 end
    end
    return out
  end,
  reset_damage = function() storage.damage = {} end,
  set_debug = function(on) storage.debug = on and true or false end,
  profile_start = function()
    P = {total = helpers.create_profiler(true), ticks = 0, asteroids = 0, asteroids_max = 0, found_max = 0}
  end,
  profile_report = function()
    if not P then return end
    local ticks = math.max(P.ticks, 1)
    print(string.format("[AA-PROFILE] ticks=%d asteroids updated per tick: avg %.1f, max %d; asteroids found per scan tick: max %d",
      P.ticks, P.asteroids / ticks, P.asteroids_max, P.found_max))
    P.total.divide(ticks)
    localised_print{"", "[AA-PROFILE] per tick: ", P.total}
  end,
  open_computer = function(player_index, unit_number)
    computer.init()
    local c = storage.computers and storage.computers[unit_number]
    if c then computer.open(game.get_player(player_index), c.entity) end
  end,
  computer_cfg = function(unit_number)
    computer.init()
    local c = storage.computers and storage.computers[unit_number]
    return c and c.cfg
  end,
  set_computer_cfg = function(unit_number, cfg)
    computer.init()
    computer.set_cfg(unit_number, cfg)
  end,
  test_gui_check = function(e)
    computer.handle_checked_state_changed(e)
  end,
  surface_topology = function(surface_index, force)
    local list = storage.turrets[surface_index] or {}
    local turrets = {}
    for _, t in pairs(list) do if t.valid then turrets[#turrets + 1] = t end end
    return surface_topology(surface_index, turrets, force)
  end,
  set_min_size = function(size) settings.global["awe-art-min-size"] = {value = size} end,
  set_interval = function(ticks) settings.global["awe-art-update-interval"] = {value = ticks} end,
})
