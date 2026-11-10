-- Focused clips for the mod page. Each take films one subject for longer than the published
-- loop; tools/capture-clips.sh cuts the loops from the takes using the events recorded here.
-- The ship is the showcase factory: every shell fired is made on board, mostly off camera.
-- Headless (--test-scenario): no frames, only the checks at the end of each take.
local factory_builder = require("__awesome-artillery__/scenarios/showcase/factory")
local geometry = require("__awesome-artillery__/scripts/geometry")

local FRAME_EVERY = 3
local WIDTH, HEIGHT = 1280, 720
local WARMUP = 48000
-- What a player has soon after unlocking the mod: a few levels of each research, normal
-- quality, and the next trip ahead of them (Fulgora to Aquilo, the first route with big asteroids).
local PROFILE = {damage = 0.3, fire_rate = 1, rotation = 2, velocity = 2,
  laser_quality = "normal", laser_damage = 0.5, laser_fire_rate = 0.5,
  origin = "fulgora", destination = "aquilo"}
local SPEED = 3 -- platform speed held during filming; asteroids are the route's own
local TRACKED = 2 -- cannon the follow take stays with
local SECTOR = {dir = 0, arc = 150, near = 32, far = 70}
-- tactical take: the sector narrows and swings left halfway through
local TACTICAL = {{dir = 0, arc = 150, near = 32, far = 60}, {dir = 320, arc = 60, near = 32, far = 60}}
local SETTLE = 180 -- ticks after a sector change in which shells already aimed may still land

-- The factory makes shells more slowly than four cannons spend them, so the cannons hold
-- fire between takes while the reserve is rebuilt at high game speed.
local REFILL = 24000
local TAKES = {
  {name = "follow", ticks = 1800},
  {name = "tactical", ticks = 1800, position = {0, -80}, zoom = 0.3},
  {name = "production", ticks = 1200},
}
local next_tick = WARMUP
for _, take in ipairs(TAKES) do
  take.first, take.last = next_tick, next_tick + take.ticks - 1
  take.frames = take.ticks / FRAME_EVERY
  next_tick = next_tick + take.ticks + REFILL
end
local END_TICK = next_tick - REFILL

local function say(fmt, ...) print("[CLIPS] " .. string.format(fmt, ...)) end
local function event(e) storage.events[#storage.events + 1] = e end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(t)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t)
end

local function ammo(turret)
  return turret.get_inventory(defines.inventory.artillery_turret_ammo).get_item_count()
end

-- hold_fire: no size allowed, so the cannons stay silent and the hub's shell reserve builds up
local function set_computer(sector, hold_fire)
  remote.call("awesome-artillery", "set_computer_cfg", storage.computer.unit_number, {
    sizes = {small = false, medium = not hold_fire, big = not hold_fire, huge = not hold_fire},
    dir = sector.dir, arc = sector.arc, near = sector.near, far = sector.far,
  })
  storage.sector = sector
end

local function frame(camera, index, position, zoom, alt)
  game.take_screenshot{
    surface = storage.platform.surface, position = position, resolution = {WIDTH, HEIGHT}, zoom = zoom,
    show_gui = false, show_entity_info = alt or false, hide_health_bars = false, force_render = true,
    quality = 92, path = string.format("clips/%s-frame-%04d.jpg", camera, index),
  }
end

-- follow ----------------------------------------------------------------------------------
-- The camera waits on one cannon. When it fires, the camera rides the shell to its aim point,
-- holds on the result and returns. Each ride is one "cycle" in the manifest.

local FLIGHT_ZOOM, HOLD_ZOOM, HOLD, RETURN = 0.7, 0.9, 60, 40

local function follow_home()
  local p = storage.turrets[TRACKED].position
  return {p.x, p.y - 2}
end

-- The decoy the cannon is pointing at: where its shell will land.
local function aim_point(turret)
  local barrel = turret.relative_turret_orientation * 360
  local best, best_off
  for _, d in pairs(remote.call("awesome-artillery", "decoy_list")) do
    local off = geometry.angle_diff(geometry.bearing(d.x - turret.position.x, d.y - turret.position.y), barrel)
    if not best_off or off < best_off then best, best_off = d, off end
  end
  if best and best_off < 3.6 then return {best.x, best.y} end
end

local function draw_crosshair(at)
  local s, color = storage.platform.surface, {1, 0.85, 0.3}
  local objects = {rendering.draw_circle{surface = s, target = at, radius = 1.5, width = 3, color = color}}
  for _, d in ipairs{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
    objects[#objects + 1] = rendering.draw_line{surface = s, width = 3, color = color,
      from = {at[1] + d[1] * 1.5, at[2] + d[2] * 1.5}, to = {at[1] + d[1] * 3, at[2] + d[2] * 3}}
  end
  return objects
end

local function follow_fired(e)
  if storage.cycle or e.source ~= storage.turrets[TRACKED] then return end
  local aim = aim_point(e.source)
  storage.cycle = {fire = e.tick, projectile = e.entity, last = follow_home(), aim = aim,
    crosshair = aim and draw_crosshair(aim) or {}}
end

local function follow_tick(tick)
  local c = storage.cycle
  if not c then return end
  if c.projectile and c.projectile.valid then
    c.last = {c.projectile.position.x, c.projectile.position.y}
  elseif not c.impact then
    c.impact = tick
  elseif tick - c.impact > HOLD + RETURN then
    for _, object in pairs(c.crosshair) do object.destroy() end
    event{kind = "cycle", fire = c.fire, impact = c.impact, done = tick, kill = c.kill, marked = c.aim ~= nil}
    storage.cycle = nil
  end
end

local function follow_view(tick)
  local home, c = follow_home(), storage.cycle
  if not c then return home, 1 end
  if not c.impact then return c.last, lerp(1, FLIGHT_ZOOM, smooth((tick - c.fire) / 20)) end
  local held = tick - c.impact
  if held <= HOLD then return c.last, lerp(FLIGHT_ZOOM, HOLD_ZOOM, smooth(held / 30)) end
  local t = smooth((held - HOLD) / RETURN)
  return {lerp(c.last[1], home[1], t), lerp(c.last[2], home[2], t)}, lerp(HOLD_ZOOM, 1, t)
end

-- tactical --------------------------------------------------------------------------------

local function in_sector(sector, x, y, margin)
  local c = storage.computer.position
  local dx, dy = x - c.x, y - c.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < sector.near - margin or d > sector.far + margin then return false end
  local slack = math.deg(math.atan2(margin, d))
  return geometry.angle_diff(geometry.bearing(dx, dy), sector.dir) <= sector.arc / 2 + slack
end

-- production ------------------------------------------------------------------------------
-- Fixed cameras film at once: a collector catching chunks, the foundry casting shells, and
-- each pair of cannons being loaded and firing (which cannon reloads first varies by run).

local function production_cameras()
  local collector, foundry = storage.nodes.metal_collector.position, storage.shells.position
  local turrets = storage.turrets
  return {
    {name = "catch", position = {collector.x, collector.y - 3}, zoom = 1.2},
    {name = "cast", position = {foundry.x, foundry.y}, zoom = 1.6, alt = true},
    {name = "load-left", position = {(turrets[1].position.x + turrets[2].position.x) / 2, turrets[1].position.y + 1}, zoom = 1.4},
    {name = "load-right", position = {(turrets[3].position.x + turrets[4].position.x) / 2, turrets[3].position.y + 1}, zoom = 1.4},
  }
end

-- takes -----------------------------------------------------------------------------------

local function begin_take(take)
  storage.take = take.name
  storage.stats[take.name] = {shots = 0, kills = 0}
  remote.call("awesome-artillery", "set_debug", take.name == "tactical")
  set_computer(take.name == "tactical" and TACTICAL[1] or SECTOR)
  if take.name == "production" then
    storage.crafted, storage.loaded = storage.shells.products_finished, {}
    for i, turret in ipairs(storage.turrets) do storage.loaded[i] = ammo(turret) end
  end
  assert(storage.platform.space_connection and storage.platform.speed > 0, "every take must show a ship in flight")
  local sizes = {}
  for _, a in pairs(storage.platform.surface.find_entities_filtered{type = "asteroid"}) do
    local size = a.name:match("^(%a+)%-")
    sizes[size] = (sizes[size] or 0) + 1
  end
  local loaded = {}
  for i, turret in ipairs(storage.turrets) do loaded[i] = ammo(turret) end
  say("%s begins at tick %d; route position %.2f; asteroids small/medium/big/huge %d/%d/%d/%d; shells per cannon %s; cast so far %d",
    take.name, game.tick, storage.platform.distance, sizes.small or 0, sizes.medium or 0, sizes.big or 0, sizes.huge or 0,
    table.concat(loaded, "/"), storage.shells.products_finished)
end

local function verify_take(take)
  local stats = storage.stats[take.name]
  if take.name == "follow" then
    local cycles, kills, by_gun = 0, 0, {0, 0, 0, 0}
    for _, e in ipairs(storage.events) do
      if e.kind == "cycle" then cycles = cycles + 1; if e.kill then kills = kills + 1 end end
      if e.kind == "fire" and e.take == "follow" and e.gun then by_gun[e.gun] = by_gun[e.gun] + 1 end
    end
    say("follow: %d shots (per cannon %s), %d kills on the ship; %d rides filmed, %d ending in a kill",
      stats.shots, table.concat(by_gun, "/"), stats.kills, cycles, kills)
    assert(kills >= 1, "follow needs at least one filmed shell that kills its asteroid")
  elseif take.name == "tactical" then
    say("tactical: %d kills in the wide sector, %d in the narrow one, %d outside the active sector",
      stats.wide or 0, stats.narrow or 0, stats.outside or 0)
    assert((stats.wide or 0) >= 3 and (stats.narrow or 0) >= 3, "tactical needs kills in both sectors")
    assert((stats.outside or 0) == 0, "tactical: artillery killed outside the active sector")
  elseif take.name == "production" then
    say("production: %d shells cast, %d loaded into cannons, %d shots, %d of them from a cannon reloaded on camera",
      stats.cast or 0, stats.load or 0, stats.shots, stats.fired or 0)
    assert((stats.cast or 0) >= 1 and (stats.load or 0) >= 1 and (stats.fired or 0) >= 1,
      "production needs a shell cast, and a cannon loaded and then firing, during the take")
  end
end

script.on_init(function()
  for name, value in pairs(factory_builder.build(PROFILE)) do storage[name] = value end
  storage.shells = storage.nodes.shells
  -- No clip fires promethium shells; left running, they pile up in the hub (one per slot)
  -- until steel shells no longer fit.
  storage.nodes.prom_shells.disabled_by_script = true
  storage.stats, storage.events, storage.reloaded = {}, {}, {}
  game.speed = 32
end)

script.on_event(defines.events.on_trigger_fired_artillery, function(e)
  local take = storage.take
  if not take then return end
  storage.stats[take].shots = storage.stats[take].shots + 1
  local gun
  for i, turret in ipairs(storage.turrets) do if e.source == turret then gun = i end end
  event{kind = "fire", take = take, tick = e.tick, gun = gun}
  if take == "follow" then follow_fired(e) end
  if take == "production" and gun and storage.reloaded[gun] then
    storage.stats[take].fired = (storage.stats[take].fired or 0) + 1
  end
end)

script.on_event(defines.events.on_entity_died, function(e)
  local take = storage.take
  if not take or e.entity.type ~= "asteroid" then return end
  if not (e.cause and e.cause.valid and e.cause.type == "artillery-turret") then return end
  local stats, p = storage.stats[take], e.entity.position
  stats.kills = stats.kills + 1
  event{kind = "kill", take = take, tick = e.tick, name = e.entity.name, x = p.x, y = p.y}
  if take == "follow" and storage.cycle and e.cause == storage.turrets[TRACKED] then storage.cycle.kill = e.entity.name end
  if take == "tactical" then
    local settling = storage.sector_changed and e.tick - storage.sector_changed < SETTLE
    local which = storage.sector == TACTICAL[1] and "wide" or "narrow"
    if in_sector(storage.sector, p.x, p.y, 8) then
      stats[which] = (stats[which] or 0) + 1
    elseif not settling then
      stats.outside = (stats.outside or 0) + 1
      say("kill outside the %s sector: %s at (%.0f, %.0f)", which, e.entity.name, p.x, p.y)
    end
  end
end)

script.on_event(defines.events.on_tick, function(e)
  local platform, tick = storage.platform, e.tick
  if tick == WARMUP - 1800 then platform.paused = false end
  if tick >= WARMUP - 1500 and platform.space_connection then
    platform.speed = SPEED
    if platform.distance > 0.7 then platform.distance = 0.25 end
  end
  -- Physical resource fields: collectors must catch every input. No intermediate
  -- item, shell, or production fluid is inserted by the scenario.
  if tick % 45 == 0 then
    local chunks = {}
    for _, spec in ipairs{{-30, "metallic"}, {-10, "carbonic"}, {10, "oxide"}, {30, "promethium"}} do
      chunks[#chunks + 1] = {name = spec[2] .. "-asteroid-chunk",
        position = {spec[1] + math.sin(tick / 70) * 3, -68.5}, movement = {0, 0.035}}
    end
    platform.create_asteroid_chunks(chunks)
  end
  if tick == 1 then
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    set_computer(SECTOR, true)
    if not script.test_arg then game.set_wait_for_screenshots_to_finish() end
  end
  for _, take in ipairs(TAKES) do
    if tick == take.first then
      game.speed = 1
      begin_take(take)
    end
    if tick >= take.first and tick <= take.last then
      local elapsed = tick - take.first
      local filming = not script.test_arg and elapsed % FRAME_EVERY == 0
      local index = elapsed / FRAME_EVERY
      if take.name == "follow" then
        follow_tick(tick)
        if filming then
          local position, zoom = follow_view(tick)
          frame("follow", index, position, zoom)
        end
      elseif take.name == "tactical" then
        if elapsed == take.ticks / 2 then
          set_computer(TACTICAL[2])
          storage.sector_changed = tick
          event{kind = "sector", tick = tick}
        end
        if filming then frame("tactical", index, take.position, take.zoom) end
      elseif take.name == "production" then
        local stats = storage.stats.production
        local crafted = storage.shells.products_finished
        if crafted > storage.crafted then
          stats.cast = (stats.cast or 0) + crafted - storage.crafted
          event{kind = "cast", tick = tick}
        end
        storage.crafted = crafted
        for i, turret in ipairs(storage.turrets) do
          local loaded = ammo(turret)
          if loaded > storage.loaded[i] then
            stats.load = (stats.load or 0) + loaded - storage.loaded[i]
            storage.reloaded[i] = true
            event{kind = "load", tick = tick, gun = i}
          end
          storage.loaded[i] = loaded
        end
        if filming then
          for _, camera in ipairs(production_cameras()) do frame(camera.name, index, camera.position, camera.zoom, camera.alt) end
        end
      end
      if tick == take.last then
        verify_take(take)
        storage.take = nil
        set_computer(SECTOR, true)
        game.speed = 32
      end
    end
  end
  if tick == END_TICK then
    helpers.write_file("clips/manifest.json", helpers.table_to_json{
      fps = 60 / FRAME_EVERY, frame_every = FRAME_EVERY, width = WIDTH, height = HEIGHT,
      takes = TAKES, events = storage.events, stats = storage.stats, profile = PROFILE, speed = SPEED,
    }, false)
    say("CAPTURE_COMPLETE")
    if script.test_arg then script.finish_test(true) end
  end
end)
