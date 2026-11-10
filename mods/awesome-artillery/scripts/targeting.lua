-- Targeting assignment & topology management for Awesome Artillery.
-- Handles:
-- 1. Topology detection: finds which artillery turrets share circuit network (red/green wire)
--    with each Targeting Computer.
-- 2. Turret auto_targeting gating: turrets wired to a computer have artillery_auto_targeting
--    managed strictly so they only fire at targets authorized by their controlling computer.
-- 3. Pure-stickiness angular selection: matches idle cannons to incoming asteroids closest to
--    their current barrel orientation to eliminate unnecessary swivel latencies.

local geometry = require("__awesome-artillery__/scripts/geometry")

local M = {}

-- 16 coarse angular sectors around platform center (22.5 deg each)
local NUM_SECTORS = 16
local DEG_PER_SECTOR = 360 / NUM_SECTORS

function M.angular_sector(dx, dy)
  return math.floor(geometry.bearing(dx, dy) / DEG_PER_SECTOR)
end

-- The red and green circuit networks an entity is on.
function M.circuit_networks(entity)
  local nets = {}
  for _, id in pairs{defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green} do
    local net = entity.get_circuit_network(id)
    if net then nets[#nets + 1] = net end
  end
  return nets
end

-- Find all network IDs an entity is connected to on red & green wires
local function get_entity_networks(entity)
  local nets = {}
  if not (entity and entity.valid) then return nets end
  for _, net in pairs(M.circuit_networks(entity)) do nets[net.network_id] = true end
  return nets
end

-- Refresh wire topology for a surface: maps each computer unit_number -> list of wired turrets,
-- and maps turret unit_number -> controlling computer unit_number (or nil if unwired).
function M.update_surface_topology(surface_index, all_turrets, computers)
  local comp_to_turrets = {} -- comp_unit_number -> {turret, ...}
  local turret_to_comp = {}   -- turret_unit_number -> comp_unit_number
  local unwired_turrets = {}

  -- Build map of computer network IDs
  local comp_nets = {} -- net_id -> comp_unit_number
  for _, c in pairs(computers) do
    if c.entity.valid and c.entity.surface.index == surface_index then
      comp_to_turrets[c.entity.unit_number] = {}
      local nets = get_entity_networks(c.entity)
      for nid in pairs(nets) do
        comp_nets[nid] = c.entity.unit_number
      end
    end
  end

  for _, t in pairs(all_turrets) do
    if t.valid and t.surface.index == surface_index then
      local tu = t.unit_number
      local assigned_comp = nil
      local nets = get_entity_networks(t)
      for nid in pairs(nets) do
        if comp_nets[nid] then
          assigned_comp = comp_nets[nid]
          break
        end
      end

      if assigned_comp then
        turret_to_comp[tu] = assigned_comp
        local list = comp_to_turrets[assigned_comp]
        list[#list + 1] = t
      else
        unwired_turrets[#unwired_turrets + 1] = t
      end
    end
  end

  return {
    comp_to_turrets = comp_to_turrets,
    turret_to_comp = turret_to_comp,
    unwired_turrets = unwired_turrets,
  }
end

-- Count how many turrets are wired to a given computer
function M.wired_turret_count(comp_unit_number, topo)
  if not (topo and topo.comp_to_turrets) then return 0 end
  local list = topo.comp_to_turrets[comp_unit_number]
  return list and #list or 0
end

-- Pick the best turret from an idle list for a target at (aim_x, aim_y), optimizing for stickiness:
-- picks the turret whose current orientation requires the minimal angular turn.
function M.pick_sticky_turret(turrets, aim_x, aim_y)
  local best_t = nil
  local min_diff = math.huge

  for _, t in pairs(turrets) do
    if t.valid then
      local tp = t.position
      local dx, dy = aim_x - tp.x, aim_y - tp.y
      local target_deg = geometry.bearing(dx, dy)
      -- relative_turret_orientation is in [0..1), 0=North, 0.25=East, 0.5=South, 0.75=West
      local barrel_deg = ((t.relative_turret_orientation or 0) * 360) % 360
      local diff = geometry.angle_diff(target_deg, barrel_deg)
      if diff < min_diff then
        min_diff = diff
        best_t = t
        if min_diff < 5 then break end -- already basically pointing straight at it
      end
    end
  end

  return best_t, min_diff
end

return M
