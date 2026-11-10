-- Controlled engine tests: one target at a time, no natural asteroid traffic or other weapons.
local math_tests = require("__space-artillery__/scenarios/core/math")
local ballistics = require("__space-artillery__/scripts/ballistics")
local balance = require("__space-artillery__/constants")
local COMPUTER = "space-art-targeting-computer"
local BALLISTICS = "space-art-asteroid-ballistics"
local MEDIUM, HUGE = "medium-metallic-asteroid", "huge-metallic-asteroid"
local STEEL, PROM = "space-art-steel-artillery-shell", "space-art-promethium-artillery-shell"

local function call(method, ...) return remote.call("space-artillery", method, ...) end
local function finish(label)
  print("[CORE] " .. label .. ": passed")
  script.finish_test(true)
end

local function make(name, position)
  return assert(storage.platform.surface.create_entity{
    name = name, position = position, force = "player", direction = defines.direction.north, raise_built = true,
  }, "could not create " .. name)
end

local function guns()
  return storage.platform.surface.find_entities_filtered{type = "artillery-turret"}
end

local function arm(shell, firing)
  for _, gun in pairs(guns()) do
    gun.artillery_auto_targeting = firing or false
    local inv = gun.get_inventory(defines.inventory.artillery_turret_ammo)
    inv.clear()
    inv.insert{name = shell, count = 15}
  end
end

local function target(name, position, velocity)
  if storage.target and storage.target.valid then storage.target.destroy() end
  storage.target = assert(storage.platform.surface.create_entity{
    name = name or MEDIUM, position = position or {0, -60}, velocity = velocity or {0, 0}, force = "enemy",
  })
  storage.killed, storage.shots, storage.speeds = false, 0, {}
  return storage.target
end

local function expect_decoys(count, label)
  if storage.computer.valid then assert(storage.computer.energy > 0, "fixture computer has no power") end
  local n = call("decoy_count")
  assert(n == count, string.format("%s: expected %d decoys, got %d", label, count, n))
end

local function tile(name, x, y)
  storage.platform.surface.set_tiles({{name = name, position = {x, y}}}, true, false, false, true)
end

local CASES = {}

CASES.math = function(tick)
  if tick == 1 then math_tests(); finish("math") end
end

CASES.hull = function(tick)
  if tick == 1 then target() end
  if tick == 20 then
    expect_decoys(1, "clear aim point")
    tile("space-platform-foundation", 6, -60)
  elseif tick == 40 then
    expect_decoys(0, "foundation within splash margin")
    tile("empty-space", 6, -60)
  elseif tick == 60 then
    expect_decoys(1, "foundation removal invalidates cached hull")
    target(MEDIUM, {16, -60})
    tile("space-platform-foundation", 6, -60)
    tile("space-platform-foundation", 26, -60)
  elseif tick == 80 then
    expect_decoys(1, "gap inside hull bounding box is safe")
    finish("hull safety and tile changes")
  end
end

CASES.damage = function(tick)
  if tick == 1 then
    local a = target(HUGE)
    local base = ballistics.damage(balance.shells[STEEL], a.prototype.resistances, 1)
    assert(base > 0, "fixture needs some explosion damage through huge armor")
    a.health = base * settings.global["space-art-max-shells"].value * 1.1
    arm(STEEL)
  elseif tick == 20 then
    expect_decoys(0, "steel cannot meet the shell budget")
    arm(PROM)
  elseif tick == 40 then
    expect_decoys(1, "promethium pierces huge armor")
    arm(STEEL)
  elseif tick == 60 then
    expect_decoys(0, "changing ammunition changes eligibility")
    game.forces.player.technologies["artillery-shell-damage-1"].researched = true
  elseif tick == 80 then
    expect_decoys(1, "damage research invalidates cached damage")
    finish("armor, ammunition changes, research and shell budget")
  end
end

CASES.combat = function(tick)
  if tick == 1 then
    assert(storage.platform.space_location.name == "fulgora" and not storage.platform.space_connection,
      "combat test must run in planet orbit")
    game.forces.player.technologies[COMPUTER].researched = true
    target()
    arm("artillery-shell", true)
    storage.phase, storage.deadline = 1, tick + 600
  end
  assert(tick < storage.deadline, "artillery did not kill the controlled target")
  if storage.target.valid then return end
  assert(storage.killed, "target must be killed by artillery")
  local progress = game.forces.player.technologies[BALLISTICS].saved_progress
  local expected_progress = storage.phase / balance.ballistics_kills
  assert(math.abs(progress - expected_progress) < 1e-7,
    string.format("orbital artillery kill %d: expected research progress %.3f, got %.3f",
      storage.phase, expected_progress, progress))
  print(string.format("[CORE] orbital artillery kill %d: field data progress %.3f", storage.phase, progress))
  local expected = storage.phase == 3 and 2 or 1
  assert(storage.shots == expected, string.format("target needs %d shells across three cannons; got %d", expected, storage.shots))
  local speed = assert(storage.speeds[1], "missing projectile speed")
  if storage.phase == 1 then
    storage.base_speed = speed
    game.forces.player.technologies["space-art-artillery-shell-velocity-1"].researched = true
    target(MEDIUM, {-20, -60}, {0.03, 0})
    storage.phase, storage.deadline = 2, tick + 600
  elseif storage.phase == 2 then
    assert(math.abs(speed / storage.base_speed - 1.2) < 1e-6, "velocity research must accelerate real projectiles")
    target("big-metallic-asteroid").health = 1500
    storage.phase, storage.deadline = 3, tick + 600
  else
    finish("orbital interceptions, field data, shell budgets and shell velocity")
  end
end

CASES.lifecycle = function(tick)
  if tick == 1 then target() end
  if tick == 20 then
    expect_decoys(1, "initial target")
    storage.target.destroy()
  elseif tick == 40 then
    expect_decoys(0, "destroyed target removes its decoy")
    target()
  elseif tick == 60 then
    expect_decoys(1, "replacement target")
    storage.computer.destroy{raise_destroy = true}
  elseif tick == 80 then
    expect_decoys(0, "destroyed computer stops targeting")
    storage.computer = make(COMPUTER, {6, 2})
    call("set_computer_cfg", storage.computer.unit_number, {dir = 0, arc = 90, near = 32, far = 200})
  elseif tick == 100 then
    expect_decoys(1, "replacement computer resumes targeting")
    storage.surface_index = storage.platform.surface.index
    storage.platform.destroy(1)
  elseif tick == 140 then
    assert(game.get_surface(storage.surface_index) == nil, "platform surface was not deleted")
    expect_decoys(0, "surface deletion removes tracked targets")
    finish("target, computer and surface deletion")
  end
end

CASES.save = function(tick)
  if tick == 1 then
    target()
    call("set_computer_cfg", storage.computer.unit_number, {dir = 0, arc = 90, near = 32, far = 200})
  elseif tick == 20 then
    expect_decoys(1, "before save")
    storage.resume_tick = tick
    game.auto_save("core-reload")
  elseif tick == 25 then
    finish("save created")
  end
end

CASES.reload = function(tick)
  assert(storage.resume_tick, "reload requires the save test's file")
  local elapsed = tick - storage.resume_tick
  if elapsed == 2 then
    expect_decoys(1, "tracking survives save/load")
    local cfg = assert(call("computer_cfg", storage.computer.unit_number))
    assert(cfg.arc == 90 and cfg.near == 32 and cfg.far == 200, "computer settings changed after reload")
    storage.target.destroy()
  elseif elapsed == 20 then
    expect_decoys(0, "loaded destruction registrations clean up decoys")
    target()
    arm("artillery-shell", true)
  elseif elapsed > 20 and not storage.target.valid then
    assert(storage.killed and storage.shots == 1, "loaded artillery must intercept once")
    finish("save/load targeting, settings and destruction registrations")
  end
end

script.on_init(function()
  local name = script.test_arg or "save"
  assert(CASES[name], "unknown core case: " .. tostring(name))
  local f = game.forces.player
  storage.platform = f.create_space_platform{
    name = "Core test", planet = name == "combat" and "fulgora" or "nauvis",
    starter_pack = "space-platform-starter-pack",
  }
  storage.platform.apply_starter_pack()
  storage.platform.paused = true
  if name ~= "combat" then
    f.unlock_space_location("vulcanus")
    storage.platform.space_connection = prototypes.space_connection["nauvis-vulcanus"]
    storage.platform.distance = 0.5
  end
  local s, tiles = storage.platform.surface, {}
  for x = -1, 1 do for y = -5, 1 do s.request_to_generate_chunks({x * 32, y * 32}, 0) end end
  s.force_generate_chunk_requests()
  for x = -12, 12 do for y = -15, 12 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
  s.set_tiles(tiles)
  for _, x in ipairs{-6, 0, 6} do make("artillery-turret", {x, -10}) end
  local power = make("electric-energy-interface", {-6, 8})
  power.power_production = 100000000
  power.electric_buffer_size = 100000000
  local left, right = make("substation", {-6, 4}), make("substation", {6, 8})
  local copper = defines.wire_connector_id.pole_copper
  left.get_wire_connector(copper, true).connect_to(right.get_wire_connector(copper, true))
  storage.computer = make(COMPUTER, {6, 2})
  arm("artillery-shell")
  call("set_interval", 1)
  call("set_min_size", "medium")
end)

script.on_event(defines.events.on_trigger_fired_artillery, function(e)
  storage.shots = (storage.shots or 0) + 1
  -- The mod handles the event after the scenario; read speed on the next tick.
  storage.projectile = e.entity
end)

script.on_event(defines.events.on_entity_died, function(e)
  if e.entity == storage.target then
    storage.killed = e.cause and e.cause.valid and e.cause.type == "artillery-turret"
  end
end)

script.on_event(defines.events.on_tick, function(e)
  if e.tick == 0 then return end
  if storage.projectile and storage.projectile.valid then
    storage.speeds[#storage.speeds + 1] = storage.projectile.speed
    storage.projectile = nil
  end
  if storage.platform.valid then
    storage.platform.speed = 0
    for _, a in pairs(storage.platform.surface.find_entities_filtered{type = "asteroid"}) do
      if a ~= storage.target then a.destroy() end
    end
  end
  assert(e.tick < 2000, "core case timed out without proving its behavior")
  local handler = assert(CASES[script.test_arg or "save"], "unknown core case")
  handler(e.tick)
end)
