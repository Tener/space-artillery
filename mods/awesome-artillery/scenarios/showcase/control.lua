-- A flying platform with asteroid-to-shell production and sustained interceptions.
-- Resource fields and combat waves are staged; collection and manufacture are physical.
local FRAME_EVERY = 3
local factory_builder = require("factory")
local WIDTH, HEIGHT = 1280, 720
local WARMUP = 48000
local SHOTS = {
  {name = "production", ticks = 2160, position = {-4, -52}, zoom = 0.5,
    title = "Collect and crush incoming asteroids",
    subtitle = "Separate metallic, carbonic, oxide and promethium feeds", alt = true},
  {name = "combat", ticks = 1200, position = {0, -93}, zoom = 0.26,
    title = "Intercept incoming asteroids",
    subtitle = "Steel shells | damage +300% | fire rate 4x | rotation VI | velocity IV"},
  {name = "promethium", ticks = 1200, position = {0, -93}, zoom = 0.26,
    title = "Break a huge promethium asteroid",
    subtitle = "Big/huge target profile | promethium shells | damage +300% | fire rate 4x"},
  {name = "hero", ticks = 900, position = {0, -48}, zoom = 0.1,
    title = "Asteroid-fed artillery in flight",
    subtitle = "Asteroid collection to shells, turbo belts and powered targeting in flight"},
}
local next_tick = WARMUP
for _, shot in ipairs(SHOTS) do
  shot.first = next_tick
  shot.last = next_tick + shot.ticks - 1
  shot.frames = shot.ticks / FRAME_EVERY
  next_tick = next_tick + shot.ticks
end
local END_TICK = next_tick

local function say(fmt, ...)
  print("[SHOWCASE] " .. string.format(fmt, ...))
end

local function ammo(turret)
  return turret.get_inventory(defines.inventory.artillery_turret_ammo).get_item_count()
end

local function build_ship()
  local factory = factory_builder.build()
  for name, value in pairs(factory) do storage[name] = value end
  storage.melt, storage.steel, storage.shells = storage.nodes.melt, storage.nodes.steel, storage.nodes.shells
  storage.stats = {shots = {}, kills = {}, laser_kills = {}, events = {}}
  storage.targets = {}
  game.speed = 32
end

local function caption(shot)
  for _, object in pairs(storage.caption or {}) do object.destroy() end
  local half_width, half_height = WIDTH / (64 * shot.zoom), HEIGHT / (64 * shot.zoom)
  local left, top = shot.position[1] - half_width, shot.position[2] - half_height
  local panel_height = 80 / (32 * shot.zoom)
  storage.caption = {
    rendering.draw_rectangle{surface = storage.platform.surface,
      left_top = {left, top}, right_bottom = {left + half_width * 2, top + panel_height},
      color = {0.025, 0.035, 0.05, 0.92}, filled = true, draw_on_ground = false},
    rendering.draw_text{surface = storage.platform.surface, text = shot.title,
      target = {left + 24 / (32 * shot.zoom), top + 10 / (32 * shot.zoom)},
      color = {1, 1, 1}, font = "default-large-bold", scale = 1 / shot.zoom},
    rendering.draw_text{surface = storage.platform.surface, text = shot.subtitle,
      target = {left + 24 / (32 * shot.zoom), top + 46 / (32 * shot.zoom)},
      color = {0.8, 0.87, 0.94}, font = "default", scale = 1 / shot.zoom},
  }
end

local function set_view(shot, position, zoom, title, subtitle)
  local view = {first = game.tick, position = position or shot.position, zoom = zoom or shot.zoom,
    title = title or shot.title, subtitle = subtitle or shot.subtitle}
  storage.view = view
  shot.views = shot.views or {}
  shot.views[#shot.views + 1] = view
  caption(view)
end

local function spawn(name, position, velocity, label)
  local entity = assert(storage.platform.surface.create_entity{
    name = name, position = position, velocity = {x = velocity[1], y = velocity[2]}, force = "enemy",
  })
  local huge = name == "huge-promethium-asteroid"
  local target = {entity = entity, name = label, huge = huge, phase = storage.phase,
    registration = script.register_on_object_destroyed(entity)}
  target.label = rendering.draw_text{
    surface = storage.platform.surface, target = {entity = entity, offset = {0, huge and 6 or 2.5}},
    text = label, color = {1, 0.9, 0.65}, font = "default-bold", alignment = "center",
    scale = 1 / SHOTS[2].zoom,
  }
  storage.targets[#storage.targets + 1] = target
  return entity
end

local function begin_shot(shot)
  for _, target in ipairs(storage.targets) do
    if target.label.valid then target.label.destroy() end
  end
  storage.targets = {}
  for _, entity in pairs(storage.platform.surface.find_entities_filtered{type = "asteroid"}) do
    entity.destroy()
  end
  if shot.name == "production" then
    game.speed = 1
    storage.turrets[1].clear_items_inside()
    storage.stats.production = {}
    for name, entity in pairs(storage.nodes) do
      if entity.type == "assembling-machine" or entity.type == "furnace" then
        assert(entity.products_finished > 0, "production stage has not run: " .. name)
        storage.stats.production[name] = entity.products_finished
      end
    end
  end
  storage.phase = shot.name
  storage.stats.shots[shot.name], storage.stats.kills[shot.name] = 0, 0
  storage.stats.laser_kills[shot.name] = 0
  storage.products_before = storage.shells.products_finished
  storage.ammo_before = 0
  for _, turret in ipairs(storage.turrets) do storage.ammo_before = storage.ammo_before + ammo(turret) end
  assert(storage.platform.space_connection and storage.platform.speed > 0, "each demo must show a ship in flight")
  storage.stats.flight = storage.stats.flight or {}
  storage.stats.flight[shot.name] = {speed = storage.platform.speed, distance = storage.platform.distance}
  set_view(shot)
  remote.call("awesome-artillery", "set_computer_cfg", storage.computer.unit_number, {
    sizes = {small = false, medium = shot.name ~= "promethium", big = true, huge = true},
    dir = 0, arc = 150, near = 32, far = 70,
  })
  if shot.name == "promethium" or shot.name == "hero" then
    for _, turret in ipairs(storage.turrets) do turret.clear_items_inside() end
  end
  for i, loader in ipairs(storage.steel_loaders) do
    loader.disabled_by_script = shot.name == "promethium"
    storage.prom_loaders[i].disabled_by_script = shot.name ~= "promethium"
  end
  if shot.name ~= "production" then
    for i = 1, 8 do
      storage.platform.surface.create_entity{
        name = (shot.name == "promethium" and "small-" or "medium-") ..
          ({"metallic", "carbonic", "oxide"})[i % 3 + 1] .. "-asteroid",
        position = {-35 + (i - 1) * 10, -101 - (i % 3)}, velocity = {x = 0, y = 0.045}, force = "enemy",
      }
    end
  end
  if shot.name == "hero" then
    for _, label in ipairs{
      {"Collection", {-100, -64}, {-68, -61}, {-30.5, -61.5}},
      {"Shell casting", {-100, -34}, {-68, -31}, {-16.5, -35.5}},
      {"Artillery battery", {90, -55}, {82, -52}, {12.5, -52.5}},
      {"Fuel and oxidizer", {90, 22}, {82, 25}, {24, 20.5}},
    } do
      storage.caption[#storage.caption + 1] = rendering.draw_text{
        surface = storage.platform.surface, text = label[1], target = label[2],
        font = "default-bold", color = {0.8, 0.87, 0.94}, scale = 1 / shot.zoom,
      }
      storage.caption[#storage.caption + 1] = rendering.draw_line{
        surface = storage.platform.surface, from = label[3], to = label[4],
        color = {0.55, 0.65, 0.75}, width = 1,
      }
    end
  end
  say("%s begins at tick %d", shot.name, game.tick)
end

local function verify_shot(shot)
  local stats = storage.stats
  if shot.name == "production" then
    local made = storage.shells.products_finished - storage.products_before
    local loaded = 0
    for _, turret in ipairs(storage.turrets) do loaded = loaded + ammo(turret) end
    loaded = loaded + stats.shots.production - storage.ammo_before
    say("production: %d crafts, %d shells loaded; total crafts melt=%d steel=%d shells=%d",
      made, loaded, storage.melt.products_finished, storage.steel.products_finished, storage.shells.products_finished)
    assert(made > 0 and loaded > 0, "production must craft and load shells during the clip")
    assert(storage.melt.products_finished > 0 and storage.steel.products_finished > 0,
      "production chain must run from raw ingredients")
  elseif shot.name == "combat" then
    say("combat: %d shots, %d asteroid kills", stats.shots.combat, stats.kills.combat)
    for _, target in ipairs(storage.targets) do
      say("%s: intercepted=%s health=%s", target.name, tostring(target.intercepted or false),
        target.entity.valid and tostring(target.entity.health) or "dead")
    end
    assert(stats.kills.combat >= 12, "combat must intercept a sustained asteroid stream")

  elseif shot.name == "promethium" then
    assert(storage.huge and not storage.huge.valid and stats.kills.promethium > 0, "huge asteroid must be destroyed on camera")
    for _, target in ipairs(storage.targets) do
      assert(target.intercepted, "each huge target must be destroyed by artillery on camera")
    end
    say("promethium: %d shots, %d huge interceptions", stats.shots.promethium, #storage.targets)
  elseif shot.name == "hero" then
    assert(storage.shells.products_finished > storage.products_before, "overview factory must keep working")
    local loaded = 0
    for _, turret in ipairs(storage.turrets) do loaded = loaded + ammo(turret) end
    say("overview: %d shots, %d shells loaded, speed %.2f", stats.shots.hero, loaded, storage.platform.speed)
    assert(loaded + stats.shots.hero > 0, "overview artillery must receive shells")
    assert(storage.platform.space_connection and storage.platform.speed > 0, "overview must show flight")
  end
end

script.on_init(build_ship)

script.on_event(defines.events.on_trigger_fired_artillery, function(event)
  local phase = storage.phase
  if not phase then return end
  storage.stats.shots[phase] = storage.stats.shots[phase] + 1
  storage.stats.events[#storage.stats.events + 1] = {kind = "shot", phase = phase, tick = event.tick}
end)

script.on_event(defines.events.on_entity_died, function(event)
  if not storage.phase or event.entity.type ~= "asteroid" then return end
  if event.cause and event.cause.valid and event.cause.name == "laser-turret" then
    local phase = storage.phase
    storage.stats.laser_kills[phase] = storage.stats.laser_kills[phase] + 1
    return
  end
  if not (event.cause and event.cause.valid and event.cause.type == "artillery-turret") then return end
  local phase = storage.phase
  for _, target in ipairs(storage.targets) do
    if target.registration == script.register_on_object_destroyed(event.entity) then
      target.intercepted = true
      target.dead_tick = event.tick
      target.label.target = {event.entity.position.x, event.entity.position.y + (target.huge and 6 or 2.5)}
      target.label.text = target.name .. " destroyed"
      target.label.color = {0.65, 1, 0.7}
    end
  end
  storage.stats.kills[phase] = storage.stats.kills[phase] + 1
  storage.stats.events[#storage.stats.events + 1] = {
    kind = "kill", phase = phase, tick = event.tick, name = event.entity.name,
  }
end)

script.on_event(defines.events.on_tick, function(event)
  local platform = storage.platform
  if event.tick == WARMUP - 600 then platform.paused = false end
  if platform.space_connection and platform.distance > 0.7 then platform.distance = 0.25 end
  -- Physical resource fields: collectors must catch every input. No intermediate
  -- item, shell, or production fluid is inserted by the scenario.
  if event.tick % 45 == 0 then
    local chunks = {}
    for _, spec in ipairs{{-30, "metallic"}, {-10, "carbonic"}, {10, "oxide"}, {30, "promethium"}} do
      chunks[#chunks + 1] = {name = spec[2] .. "-asteroid-chunk",
        position = {spec[1] + math.sin(event.tick / 70) * 3, -68.5}, movement = {0, 0.035}}
    end
    platform.create_asteroid_chunks(chunks)
  end
  if event.tick == 1 then
    remote.call("awesome-artillery", "set_interval", 10)
    remote.call("awesome-artillery", "set_debug", false)
    remote.call("awesome-artillery", "set_computer_cfg", storage.computer.unit_number, {
      sizes = {small = false, medium = false, big = false, huge = false},
      dir = 0, arc = 150, near = 32, far = 70,
    })
    if not script.test_arg then game.set_wait_for_screenshots_to_finish() end
  end
  for _, shot in ipairs(SHOTS) do
    if event.tick == shot.first then begin_shot(shot) end
    if event.tick >= shot.first and event.tick <= shot.last then
      local elapsed = event.tick - shot.first
      if shot.name == "production" and elapsed == 720 then
        set_view(shot, {-6, 2}, 0.4, "Manufacture every shell ingredient onboard",
          "Separate belts: ore, carbon, sulfur, ice, calcite, circuits, radar and explosives")
      elseif shot.name == "production" and elapsed == 1440 then
        set_view(shot, {0, -33}, 0.3, "Cast shells and feed the battery",
          "Asteroid-derived shells > hub magazine > four artillery turrets")
      end
      if elapsed % 120 == 60 and shot.name ~= "production" then
        for i = 1, 4 do
          local x = -35 + ((elapsed / 120 * 13 + i * 17) % 70)
          local name = ({"metallic", "carbonic", "oxide"})[(i + math.floor(elapsed / 120)) % 3 + 1]
          local asteroid = platform.surface.create_entity{
            name = (shot.name == "promethium" and "small-" or "medium-") .. name .. "-asteroid", position = {x, -116 - i * 2},
            velocity = {x = -x * 0.0004, y = 0.045 + i * 0.004}, force = "enemy",
          }
          assert(asteroid)
        end
      end
      if shot.name == "promethium" and elapsed % 300 == 120 and elapsed <= 720 then
        local huge = spawn("huge-promethium-asteroid", {(elapsed - 420) / 37.5, -126}, {0.002, 0.016}, "Huge promethium")
        storage.huge = huge
      end
      local extra = " | artillery kills: " .. storage.stats.kills[shot.name]
      if shot.name == "promethium" then extra = extra .. " | laser kills: " .. storage.stats.laser_kills[shot.name] end
      if shot.name == "combat" or shot.name == "promethium" then
        storage.caption[3].text = shot.subtitle .. extra
      end
      for _, target in ipairs(storage.targets) do
        if target.entity.valid then
          target.label.text = target.name .. " | " .. math.ceil(target.entity.health) .. " HP"
        elseif target.dead_tick and event.tick - target.dead_tick > 120 and target.label.valid then
          target.label.destroy()
        end
      end
      if not script.test_arg and elapsed % FRAME_EVERY == 0 then
        local view = storage.view
        game.take_screenshot{
          surface = storage.platform.surface, position = view.position,
          resolution = {WIDTH, HEIGHT}, zoom = view.zoom, show_gui = false,
          show_entity_info = shot.alt or false, hide_health_bars = false,
          force_render = true, path = string.format("showcase/%s-frame-%04d.png", shot.name, elapsed / FRAME_EVERY),
        }
      end
      if event.tick == shot.last then verify_shot(shot) end
    end
  end
  if event.tick == END_TICK then
    helpers.write_file("showcase/manifest.json", helpers.table_to_json{
      fps = 60 / FRAME_EVERY, width = WIDTH, height = HEIGHT, shots = SHOTS, stats = storage.stats,
    }, false)
    say("CAPTURE_COMPLETE")
    if script.test_arg then script.finish_test(true) end
  end
end)
