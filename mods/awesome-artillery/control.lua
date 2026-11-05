-- Decoy controller: keeps one invisible decoy per eligible asteroid at the asteroid's lead
-- point, with the asteroid's health, so vanilla artillery auto-targeting shoots it.

local computer = require("scripts.computer")

local SIZE_RANK = {chunk = 0, small = 1, medium = 2, big = 3, huge = 4}
-- Vanilla artillery shell damage (projectile prototypes aren't readable at runtime).
local SHELL_DAMAGE = {physical = 1000, explosion = 1000}
local BLAST_RADIUS = 4
local FOUNDATION = "space-platform-foundation"
local BUILD_FILTER = {{filter = "type", type = "artillery-turret"}, {filter = "name", name = computer.NAME, mode = "or"}}

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
  storage.tracked = storage.tracked or {}   -- registration number -> {a, d, last, tick, v, seen}
  storage.damage = {}                       -- force index -> asteroid name -> damage per shell
  storage.debug = storage.debug or false
  storage.const = nil
  computer.init()
end

local function add_turret(t)
  if not (t and t.valid and t.type == "artillery-turret" and t.surface.platform) then return end
  local list = storage.turrets[t.surface.index] or {}
  list[t.unit_number] = t
  storage.turrets[t.surface.index] = list
end

local function rescan()
  storage.turrets = {}
  for _, s in pairs(game.surfaces) do
    if s.platform then
      for _, t in pairs(s.find_entities_filtered{type = "artillery-turret"}) do add_turret(t) end
    end
  end
end

-- size rank from the data-stage catalogue (works for modded asteroids)
local function size_of(name)
  local info = computer.catalogue()[name]
  return info and info.size or 0
end

local function shell_damage(force, name)
  local per_force = storage.damage[force.index] or {}
  storage.damage[force.index] = per_force
  if per_force[name] then return per_force[name] end
  local resist = prototypes.entity[name].resistances or {}
  local mult = 1 + force.get_ammo_damage_modifier("artillery-shell")
  local total = 0
  for type, amount in pairs(SHELL_DAMAGE) do
    local r = resist[type] or {decrease = 0, percent = 0}
    local d = amount * mult - r.decrease
    if d > 0 then total = total + d * (1 - r.percent) end
  end
  per_force[name] = total
  return total
end

-- ctx: per-update values read once (settings, turret positions); see update_surface.
-- Every asteroid in the catalogue has a decoy prototype (both come from max_health asteroids).
local function eligible(name, health, force, ctx)
  if size_of(name) < ctx.min_rank then return false end
  local dmg = shell_damage(force, name)
  return dmg > 0 and health / dmg <= ctx.max_shells
end

local function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

-- Lead from the turrets' centre (vanilla picks the firing turret, often not the nearest
-- one; measured). Solves |r + v t| = s t for the shell flight time t, where r is the
-- asteroid's offset from the centre. Returns the aim point, or nil if it is outside the
-- band the turrets can reach (range/min range widened by the turrets' spread).
-- The error from the firing turret not being at the centre is left to shell speed research.
local function intercept(px, py, vx, vy, ctx)
  -- the decoy stays put until the next update, and the shot can come at any point in
  -- between: aim for the middle of the interval, which halves the worst-case staleness
  px, py = px + vx * ctx.half_interval, py + vy * ctx.half_interval
  local rx, ry = px - ctx.cx, py - ctx.cy
  local s = ctx.shell_speed
  local a = vx * vx + vy * vy - s * s -- < 0: shells are faster than asteroids
  local b = 2 * (rx * vx + ry * vy)
  local c = rx * rx + ry * ry
  local t = (-b - math.sqrt(b * b - 4 * a * c)) / (2 * a) -- the positive root
  local d = s * t
  if d < ctx.reach_min or d > ctx.reach_max then return nil end
  return px + vx * t, py + vy * t
end

-- Profiling (headless measurement only; not saved). Enabled via remote profile_start.
local P
local function count(key) if P then P.n[key] = (P.n[key] or 0) + 1 end end
local function timed(key, fn, ...)
  if not P then return fn(...) end
  local t = helpers.create_profiler()
  local a, b = fn(...)
  t.stop()
  P.t[key].add(t)
  return a, b
end

-- Hull outline per surface: one box per chunk that has foundation, with the exact tile
-- extent inside that chunk. Rebuilt on tile changes and every 10 s (tiles can also be
-- destroyed by asteroid impacts). A stale outline only makes the check slower, not unsafe,
-- because points near any box still get the exact tile query.
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
  count("safety_checks")
  if P and P.no_safety then return true end
  local r = ctx.blast
  local x, y = aim[1], aim[2]
  for _, b in pairs(ctx.hull) do
    if x > b[1] - r and x < b[3] + r and y > b[2] - r and y < b[4] + r then
      count("tile_queries")
      return s.count_tiles_filtered{position = aim, radius = r, name = FOUNDATION, limit = 1} == 0
    end
  end
  return true
end

local function drop_decoy(tr)
  if tr.d and tr.d.valid then tr.d.destroy() end
  tr.d = nil
end

local TELEPORT_MIN = 0.5 -- tiles; smaller aim changes don't move the decoy (blast radius is 4)

local function update_asteroid(tr, s, ctx, force, interval, rules)
  local a, p, name = tr.a, tr.a.position, tr.name
  local px, py = p.x, p.y
  local dt = game.tick - tr.tick
  if dt > 0 then tr.vx, tr.vy = (px - tr.lx) / dt, (py - tr.ly) / dt end
  tr.lx, tr.ly, tr.tick = px, py, game.tick
  count("asteroids")
  if P and P.extra_alloc then
    -- profiling only: extra garbage, to measure what allocation costs
    for _ = 1, P.extra_alloc do P.sink = {px, py} end
  end
  local health = a.health
  local ax, ay
  if tr.vx and eligible(name, health, force, ctx) then ax, ay = intercept(px, py, tr.vx, tr.vy, ctx) end
  if not ax then return drop_decoy(tr) end
  local aim = tr.aim
  if not aim then aim = {ax, ay}; tr.aim = aim end
  local moved = (ax - aim[1]) ^ 2 + (ay - aim[2]) ^ 2 >= TELEPORT_MIN * TELEPORT_MIN
  aim[1], aim[2] = ax, ay
  if not safe(s, aim, ctx) then return drop_decoy(tr) end
  if rules and not computer.allows(rules, name, ax, ay) then return drop_decoy(tr) end
  if tr.d and tr.d.valid then
    if moved and not (P and P.skip.teleport) then count("teleports"); tr.d.teleport(aim) end
  else
    count("creates")
    tr.d = s.create_entity{name = "aa-decoy-" .. name, position = aim, force = "enemy"}
    tr.dh = nil
  end
  if tr.d and tr.dh ~= health and not (P and P.skip.health) then tr.d.health = health; tr.dh = health end
  if storage.debug then
    rendering.draw_circle{color = {1, 0.2, 0.2}, radius = 1, width = 2, target = aim, surface = s, time_to_live = interval + 1}
    rendering.draw_line{color = {1, 0.6, 0.2}, width = 1, from = a, to = aim, surface = s, time_to_live = interval + 1}
  end
end

local function update_surface(s, turrets, interval)
  local c = constants()
  local force = s.platform.force
  local range = c.range * (1 + force.artillery_range_modifier)
  -- read once per update: turret positions, settings, hull outline
  local g = settings.global
  local ctx = {turrets = {}, min_rank = SIZE_RANK[g["aa-min-size"].value], max_shells = g["aa-max-shells"].value,
    blast = BLAST_RADIUS + g["aa-safety-margin"].value, hull = hull_boxes(s)}
  local cx, cy = 0, 0
  for i, t in pairs(turrets) do
    local p = t.position
    ctx.turrets[i] = {p.x, p.y}
    cx, cy = cx + p.x, cy + p.y
  end
  cx, cy = cx / #turrets, cy / #turrets
  local spread = 0
  for _, t in pairs(ctx.turrets) do spread = math.max(spread, dist(cx, cy, t[1], t[2])) end
  ctx.cx, ctx.cy, ctx.shell_speed, ctx.half_interval = cx, cy, c.shell_speed, interval / 2
  -- some turret can reach a point whose distance from the centre is within this band
  ctx.reach_min, ctx.reach_max = math.max(0, c.min_range - spread), range + spread
  -- targeting computers: nil rules = no restriction (only when computers aren't required and none are built)
  local rules, present = timed("rules", computer.rules, s.index)
  if not present and not settings.global["aa-require-computer"].value then rules = nil end
  if rules and #rules == 0 then return end -- nothing allowed; stale decoys are dropped by the caller
  -- TODO(perf): every asteroid in this circle gets a full update, even ones that can never
  -- get a decoy. Possible improvements, worth it when computers restrict targeting:
  --  * name prefilter: per update, the set of asteroid names that could pass (min size,
  --    computers' sizes/chunks, shell limit at full health); skip others after a.name.
  --  * scan only the computers' zones (sector bounding boxes) instead of the full circle.
  --  * update asteroids without a decoy less often (see the per-asteroid interval plan).
  local found = timed("scan", s.find_entities_filtered, {type = "asteroid", position = {cx, cy}, radius = range + spread})
  timed("asteroids", function()
    for _, a in pairs(found) do
      local id
      if P and P.skip.register then
        id = a.unit_number
        if not id and not P.warned then P.warned = true; print("[AA-PROFILE] asteroids have no unit_number") end
        id = id or script.register_on_object_destroyed(a)
      else
        id = script.register_on_object_destroyed(a)
      end
      local tr = storage.tracked[id]
      if not tr then
        local p = a.position
        tr = {a = a, name = a.name, lx = p.x, ly = p.y, tick = game.tick}
        storage.tracked[id] = tr
      end
      tr.seen = game.tick
      update_asteroid(tr, s, ctx, force, interval, rules)
    end
  end)
end

local update -- defined below; wrapped for profiling
script.on_event(defines.events.on_tick, function(e)
  local interval = settings.global["aa-update-interval"].value
  if e.tick % interval ~= 0 then return end
  if P then
    P.n.updates = (P.n.updates or 0) + 1
    -- rough allocation measure: Lua heap growth across the update (undercounts if a GC
    -- step runs in between; those samples are dropped)
    local ok, before = pcall(collectgarbage, "count")
    timed("total", update, e, interval)
    local ok2, after = pcall(collectgarbage, "count")
    if ok and ok2 then
      if after >= before then
        P.n.alloc_kb = (P.n.alloc_kb or 0) + (after - before)
        P.n.alloc_samples = (P.n.alloc_samples or 0) + 1
      end
    elseif not P.gc_warned then
      P.gc_warned = true
      print("[AA-PROFILE] collectgarbage not available: " .. tostring(before))
    end
  else
    update(e, interval)
  end
end)

update = function(e, interval)
  for index, list in pairs(storage.turrets) do
    local s = game.get_surface(index)
    if not (s and s.valid and s.platform) then
      storage.turrets[index] = nil
    else
      local turrets = {}
      for k, t in pairs(list) do
        if t.valid then turrets[#turrets + 1] = t else list[k] = nil end
      end
      if #turrets > 0 then update_surface(s, turrets, interval) end
    end
  end
  -- asteroids no longer near any artillery (or not allowed by any computer): drop their decoys
  local decoys = timed("cleanup", function()
    local n = 0
    for id, tr in pairs(storage.tracked) do
      if tr.seen ~= e.tick then drop_decoy(tr); storage.tracked[id] = nil
      elseif tr.d then n = n + 1 end
    end
    return n
  end)
  if P then P.n.decoy_samples = (P.n.decoy_samples or 0) + decoys end
  timed("refresh", computer.refresh_open)
end

script.on_event(defines.events.on_object_destroyed, function(e)
  local tr = storage.tracked[e.registration_number]
  if tr then drop_decoy(tr); storage.tracked[e.registration_number] = nil end
end)

local function on_built(e)
  local ent = e.entity or e.destination
  if not (ent and ent.valid) then return end
  if ent.name == computer.NAME then computer.add(ent, e.tags) else add_turret(ent) end
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

local function reset_damage() storage.damage = {} end
script.on_event(defines.events.on_research_finished, reset_damage)
script.on_event(defines.events.on_research_reversed, reset_damage)

script.on_init(function() init_storage(); rescan(); computer.rescan() end)
script.on_configuration_changed(function() init_storage(); rescan(); computer.rescan() end)

commands.add_command("aa-debug", "Toggle drawing of artillery decoys (red circle = aim point).", function(cmd)
  storage.debug = not storage.debug
  local p = cmd.player_index and game.get_player(cmd.player_index)
  local msg = "aa-debug " .. (storage.debug and "on" or "off")
  if p then p.print(msg) else print(msg) end
end)

-- Read-only view for scenarios and tests.
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
  -- decoys by asteroid name, e.g. {["medium-metallic-asteroid"] = 3}
  decoys_by_name = function()
    local out = {}
    for _, tr in pairs(storage.tracked) do
      if tr.d and tr.d.valid and tr.a.valid then out[tr.a.name] = (out[tr.a.name] or 0) + 1 end
    end
    return out
  end,
  reset_damage = reset_damage,
  set_debug = function(on) storage.debug = on and true or false end,
  -- Micro-benchmark of single operations over the live tracked asteroids/decoys.
  bench = function(passes)
    local list = {}
    for _, tr in pairs(storage.tracked) do
      if tr.a.valid and tr.d and tr.d.valid then
        local p = tr.d.position
        tr.cached = {p.x, p.y}
        list[#list + 1] = tr
      end
    end
    local n = #list
    if n == 0 then print("[AA-BENCH] no live decoys") return end
    local s = list[1].d.surface
    local c = constants()
    local ctx = {cx = 0, cy = -20, shell_speed = c.shell_speed, reach_min = 20, reach_max = 260, half_interval = 5}
    local rules = computer.rules(s.index)
    print(string.format("[AA-BENCH] %d asteroids with decoys, %d passes", n, passes))
    local base
    local function run(label, fn)
      local prof = helpers.create_profiler()
      for _ = 1, passes do for i = 1, n do fn(list[i]) end end
      prof.stop()
      prof.divide(passes * n)
      localised_print{"", "[AA-BENCH] ", label, ": ", prof, " per call"}
    end
    run("baseline (empty function call)", function(tr) end)
    run("a.valid", function(tr) local _ = tr.a.valid end)
    run("a.name", function(tr) local _ = tr.a.name end)
    run("a.unit_number", function(tr) local _ = tr.a.unit_number end)
    run("a.health", function(tr) local _ = tr.a.health end)
    run("a.position", function(tr) local _ = tr.a.position end)
    run("a.position.x + .y", function(tr) local p = tr.a.position; local _ = p.x + p.y end)
    run("d.valid", function(tr) local _ = tr.d.valid end)
    run("register_on_object_destroyed (again)", function(tr) script.register_on_object_destroyed(tr.a) end)
    run("d.teleport(cached position)", function(tr) tr.d.teleport(tr.cached) end)
    run("d.health = same value", function(tr) tr.d.health = tr.dh or 1 end)
    run("settings.global[...].value", function() local _ = settings.global["aa-max-shells"].value end)
    run("prototypes.entity[name]", function(tr) local _ = prototypes.entity[tr.name] end)
    run("catalogue()[name]", function(tr) local _ = computer.catalogue()[tr.name] end)
    run("new table {x, y}", function(tr) local _ = {1, 2} end)
    run("intercept (closed form, Lua only)", function(tr)
      intercept(tr.cached[1], tr.cached[2], 0.01, 0.14, ctx)
    end)
    run("computer.allows", function(tr) computer.allows(rules, tr.name, tr.cached[1], tr.cached[2]) end)
    run("count_tiles_filtered (radius 8)", function(tr)
      local _ = s.count_tiles_filtered{position = tr.cached, radius = 8, name = FOUNDATION, limit = 1}
    end)
    run("dist via (dx)^2 + sqrt", function(tr)
      local _ = math.sqrt((tr.cached[1] - 8) ^ 2 + (tr.cached[2] + 10) ^ 2)
    end)
    run("dist via dx*dx + sqrt", function(tr)
      local dx, dy = tr.cached[1] - 8, tr.cached[2] + 10
      local _ = math.sqrt(dx * dx + dy * dy)
    end)
    -- real moves: alternate between two points 1.5 tiles apart (like a decoy following its asteroid)
    local flip = false
    run("d.teleport(moved 1.5 tiles)", function(tr)
      flip = not flip
      tr.d.teleport({tr.cached[1] + (flip and 1.5 or 0), tr.cached[2]})
    end)
    run("d.teleport(moved 1.5 tiles, cached tables)", function(tr)
      tr.alt = tr.alt or {tr.cached[1] + 1.5, tr.cached[2]}
      flip = not flip
      tr.d.teleport(flip and tr.alt or tr.cached)
    end)
    run("d.teleport(moved 40 tiles)", function(tr)
      flip = not flip
      tr.d.teleport({tr.cached[1] + (flip and 40 or 0), tr.cached[2]})
    end)
    for _, tr in pairs(list) do if tr.d.valid then tr.d.teleport(tr.cached) end end
  end,
  profile_start = function(opts)
    P = {t = {}, n = {}, no_safety = opts and opts.no_safety, skip = opts and opts.skip or {},
      extra_alloc = opts and opts.extra_alloc}
    if P.extra_alloc then print("[AA-PROFILE] extra allocation: " .. P.extra_alloc .. " tables per asteroid") end
    for _, k in pairs{"total", "rules", "scan", "asteroids", "cleanup", "refresh"} do P.t[k] = helpers.create_profiler(true) end
  end,
  profile_report = function()
    if not P then return end
    local n = P.n
    local updates = math.max(n.updates or 0, 1)
    print(string.format("[AA-PROFILE] updates=%d asteroids/update=%.1f decoys/update=%.1f safety_checks=%d tile_queries=%d teleports=%d creates=%d%s",
      updates, (n.asteroids or 0) / updates, (n.decoy_samples or 0) / updates, n.safety_checks or 0,
      n.tile_queries or 0, n.teleports or 0, n.creates or 0, P.no_safety and " (hull check OFF)" or ""))
    local vs, vn = 0, 0
    for _, tr in pairs(storage.tracked) do
      if tr.vx then vs, vn = vs + math.sqrt(tr.vx * tr.vx + tr.vy * tr.vy), vn + 1 end
    end
    if vn > 0 then print(string.format("[AA-PROFILE] mean asteroid speed relative to the platform: %.3f tiles/tick", vs / vn)) end
    if n.alloc_samples then
      print(string.format("[AA-PROFILE] alloc: %.1f KB per update (%d of %d updates measured, rest had a GC step)",
        n.alloc_kb / n.alloc_samples, n.alloc_samples, updates))
    end
    for _, k in pairs{"total", "rules", "scan", "asteroids", "cleanup", "refresh"} do
      P.t[k].divide(updates)
      localised_print{"", "[AA-PROFILE] ", k, " per update: ", P.t[k]}
    end
  end,
  open_computer = function(player_index, unit_number)
    local c = storage.computers[unit_number]
    if c then computer.open(game.get_player(player_index), c.entity) end
  end,
  computer_cfg = function(unit_number)
    local c = storage.computers[unit_number]
    return c and c.cfg
  end,
  set_computer_cfg = function(unit_number, cfg)
    local c = storage.computers[unit_number]
    if c then c.cfg = computer.complete(cfg) end
  end,
  -- only the owning mod may change its runtime-global settings
  set_min_size = function(size) settings.global["aa-min-size"] = {value = size} end,
  set_interval = function(ticks) settings.global["aa-update-interval"] = {value = ticks} end,
})
