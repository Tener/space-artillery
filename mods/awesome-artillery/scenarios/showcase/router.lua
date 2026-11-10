-- Grid bookkeeping and routing shared by the scenario ships: which cells are taken, pipes and
-- belts routed between machines, and a spanning-tree power grid.
local M = {}
local FOUNDATION = "space-platform-foundation"
local DIRS = {{0, -1, defines.direction.north}, {1, 0, defines.direction.east},
  {0, 1, defines.direction.south}, {-1, 0, defines.direction.west}}
M.DIRS = DIRS
local function key(x, y) return x .. "," .. y end
local function point(p) return {p[1] + 0.5, p[2] + 0.5} end
local function distance(a, b) return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) end
M.key, M.point, M.distance = key, point, distance

-- bounds: {x1, y1, x2, y2}, the tile range routes may use. Call after the hull tiles are set:
-- every cell without foundation starts out taken.
function M.new(surface, force, bounds)
  local g = {surface = surface, force = force, bounds = bounds,
    occupied = {}, tunnels = {}, fluid_cells = {}, fluid_reservations = {},
    port_reservations = {}, active_ports = {}, dry_access = {}, nodes = {}}
  local occupied, tunnels, fluid_cells, fluid_reservations = g.occupied, g.tunnels, g.fluid_cells, g.fluid_reservations
  for x = bounds[1], bounds[3] do
    for y = bounds[2], bounds[4] do
      if surface.get_tile(x, y).name ~= FOUNDATION then occupied[key(x, y)] = {solid = true} end
    end
  end

  -- Marks an entity's footprint as taken.
  function g.claim(entity)
    local box = entity.bounding_box
    for x = math.floor(box.left_top.x), math.ceil(box.right_bottom.x) - 1 do
      for y = math.floor(box.left_top.y), math.ceil(box.right_bottom.y) - 1 do
        occupied[key(x, y)] = {entity = entity, solid = true}
      end
    end
  end

  function g.make(name, p, direction, extra)
    local args = {name = name, position = p, force = force, direction = direction or defines.direction.north,
      raise_built = true}
    for k, v in pairs(extra or {}) do args[k] = v end
    assert(surface.can_place_entity(args), "showcase blocked: " .. name .. " " .. serpent.line(p))
    local entity = assert(surface.create_entity(args))
    entity.destructible = false
    g.claim(entity)
    return entity
  end

  -- Deterministic A* with underground crossings. Machine footprints cannot be
  -- tunneled through; perpendicular tunnels may cross, parallel tunnels may not.
  function g.route(start, goal, kind, fluid, finish_dir, normal_start)
    local heap, best, previous, states = {}, {}, {}, {}
    local function push(state, cost, estimate, parent)
      local id = key(state[1], state[2]) .. "," .. state[3] .. "," .. tostring(state[4])
      if best[id] and best[id] <= cost then return end
      best[id], previous[id], states[id] = cost, parent, state
      local item = {id = id, cost = cost, score = cost + estimate}
      heap[#heap + 1] = item
      local j = #heap
      while j > 1 do
        local p = math.floor(j / 2)
        if heap[p].score <= item.score then break end
        heap[j], j = heap[p], p
      end
      heap[j] = item
    end
    local function pop()
      local item, last = heap[1], table.remove(heap)
      if #heap > 0 then
        local j = 1
        while j * 2 <= #heap do
          local child = j * 2
          if child < #heap and heap[child + 1].score < heap[child].score then child = child + 1 end
          if last.score <= heap[child].score then break end
          heap[j], j = heap[child], child
        end
        heap[j] = last
      end
      return item
    end
    local function free(x, y)
      if x < bounds[1] or x > bounds[3] or y < bounds[2] or y > bounds[4] then return false end
      local cell = occupied[key(x, y)]
      if cell and not (kind == "pipe" and cell.fluid == fluid) then return false end
      if kind == "belt" and g.port_reservations[key(x, y)] and not g.active_ports[key(x, y)] then return false end
      if kind == "pipe" then
        if g.dry_access[key(x, y)] then return false end
        local reserved = fluid_reservations[key(x, y)]
        if reserved and reserved ~= fluid then return false end
        for _, d in ipairs(DIRS) do
          local f = fluid_cells[key(x + d[1], y + d[2])]
          f = f or fluid_reservations[key(x + d[1], y + d[2])]
          if f and f ~= fluid then return false end
        end
      end
      return true
    end
    if not free(start[1], start[2]) or not free(goal[1], goal[2]) then return end
    push({start[1], start[2], 0, false}, 0, distance(start, goal))
    local visited = 0
    while #heap > 0 do
      local entry = pop()
      if entry.cost == best[entry.id] then
        local state = states[entry.id]
        visited = visited + 1
        if visited > 100000 then return end
        if state[1] == goal[1] and state[2] == goal[2] and
          (not state[4] or (kind == "belt" and state[3] == finish_dir)) then
          local path, id = {}, entry.id
          while id do table.insert(path, 1, states[id]); id = previous[id] end
          local seen = {}
          for _, p in ipairs(path) do
            local cell = key(p[1], p[2])
            if seen[cell] then return end
            seen[cell] = true
          end
          return path
        end
        for dir, d in ipairs(DIRS) do
          if (not state[4] or state[3] == dir) and
            (state[3] == 0 or dir ~= (state[3] + 1) % 4 + 1) then
            local x, y = state[1] + d[1], state[2] + d[2]
            if free(x, y) then
              local cost = entry.cost + 1 + ((state[3] ~= 0 and state[3] ~= dir) and 0.3 or 0)
              push({x, y, dir, false}, cost, distance({x, y}, goal), entry.id)
            elseif (state[3] == dir or (state[3] == 0 and not normal_start)) and
              not occupied[key(state[1], state[2])] then
              local axis = d[1] == 0 and "v" or "h"
              for length = 2, (kind == "pipe" and 10 or 11) do
                local under_x, under_y = state[1] + d[1] * (length - 1), state[2] + d[2] * (length - 1)
                local cell = occupied[key(under_x, under_y)]
                if (cell and cell.solid) or tunnels[key(under_x, under_y) .. kind .. axis] then break end
                local end_x, end_y = state[1] + d[1] * length, state[2] + d[2] * length
                if free(end_x, end_y) and free(end_x + d[1], end_y + d[2]) then
                  push({end_x, end_y, dir, true}, entry.cost + length + 4,
                    distance({end_x, end_y}, goal), entry.id)
                end
              end
            end
          end
        end
      end
    end
  end

  function g.lay(path, kind, fluid, finish_dir)
    for i, p in ipairs(path) do
      local before, after = path[i - 1], path[i + 1]
      local input = after and distance(p, after) > 1
      local output = before and distance(before, p) > 1
      local dir = input and after[3] or (output and p[3] or (after and after[3] or p[3]))
      if not after and not output and finish_dir then dir = finish_dir end
      if dir == 0 then dir = 1 end
      local cell = occupied[key(p[1], p[2])]
      if not cell then
        local name = kind == "pipe" and "pipe" or "turbo-transport-belt"
        local extra
        if input or output then
          if kind == "pipe" then
            name = "pipe-to-ground"
            -- The open end faces the surface pipe, away from the tunnel.
            if input then dir = (dir + 1) % 4 + 1 end
          else
            name = "turbo-underground-belt"
            extra = {type = input and "input" or "output"}
          end
        end
        g.make(name, point(p), DIRS[dir][3], extra)
        occupied[key(p[1], p[2])] = {fluid = fluid, route = true}
        if kind == "pipe" then fluid_cells[key(p[1], p[2])] = fluid end
      end
      if input then
        local d = DIRS[after[3]]
        for n = 0, distance(p, after) do
          tunnels[key(p[1] + d[1] * n, p[2] + d[2] * n) .. kind .. (d[1] == 0 and "v" or "h")] = true
        end
      end
    end
  end

  -- A hand-placed pipe, known to the router so other fluids keep clear of it.
  function g.pipe(x, y, fluid)
    g.make("pipe", point{x, y})
    occupied[key(x, y)] = {fluid = fluid, route = true}
    fluid_cells[key(x, y)] = fluid
  end

  local function fluid_ports(entity, fluid, output)
    local result = {}
    for index = 1, entity.fluids_count do
      local filter = entity.get_fluid_filter(index)
      if filter and filter.name == fluid then
        for _, connection in pairs(entity.get_fluid_box_pipe_connections(index) or {}) do
          if connection.flow_direction == "input-output" or connection.flow_direction == (output and "output" or "input") then
            result[#result + 1] = {math.floor(connection.target_position.x), math.floor(connection.target_position.y)}
          end
        end
      end
    end
    return result
  end

  -- Pipes a fluid from one node to another, joining the fluid's existing pipes where shorter.
  function g.fluid_link(from, to, fluid)
    local starts = fluid_ports(g.nodes[from], fluid, true)
    for cell, name in pairs(fluid_cells) do
      if name == fluid then
        local x, y = cell:match("(-?%d+),(-?%d+)")
        starts[#starts + 1] = {tonumber(x), tonumber(y)}
      end
    end
    for _, b in ipairs(fluid_ports(g.nodes[to], fluid, false)) do
      table.sort(starts, function(a, c) return distance(a, b) < distance(c, b) end)
      for _, a in ipairs(starts) do
        local path = g.route(a, b, "pipe", fluid)
        if path then g.lay(path, "pipe", fluid); return end
      end
    end
    error("no pipe route: " .. from .. " -> " .. to .. " " .. fluid)
  end

  -- Keeps the cell in front of every node's fluid port for that port's fluid. Call once all
  -- nodes exist and before the first fluid_link.
  function g.reserve_fluid_ports()
    for _, entity in pairs(g.nodes) do
      for index = 1, entity.fluids_count do
        local filter = entity.get_fluid_filter(index)
        if filter then
          for _, connection in pairs(entity.get_fluid_box_pipe_connections(index) or {}) do
            fluid_reservations[key(math.floor(connection.target_position.x), math.floor(connection.target_position.y))] = filter.name
          end
        end
      end
    end
  end

  -- A short spanning tree carries the same power without a mesh of long wires
  -- crossing the views. Circuit wires retain their separate networks.
  function g.connect_poles()
    local poles = surface.find_entities_filtered{type = "electric-pole", force = force}
    table.sort(poles, function(a, b)
      return a.position.x < b.position.x or (a.position.x == b.position.x and a.position.y < b.position.y)
    end)
    local connected, degree = {[1] = true}, {}
    for i, pole in ipairs(poles) do
      local connector = pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
      connector.disconnect_all(defines.wire_origin.player)
      connector.disconnect_all(defines.wire_origin.script)
      degree[i] = 0
    end
    for _ = 2, #poles do
      local best, from, to
      for i, a in ipairs(poles) do
        if connected[i] and degree[i] < 5 then
          for j, b in ipairs(poles) do
            if not connected[j] then
              local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y
              local length = dx * dx + dy * dy
              local reach = math.min(a.prototype.get_max_wire_distance(a.quality), b.prototype.get_max_wire_distance(b.quality))
              if length <= reach * reach and (not best or length < best) then best, from, to = length, i, j end
            end
          end
        end
      end
      assert(from and to, "power grid is disconnected")
      assert(poles[from].get_wire_connector(defines.wire_connector_id.pole_copper, true)
        .connect_to(poles[to].get_wire_connector(defines.wire_connector_id.pole_copper, true)))
      connected[to], degree[from], degree[to] = true, degree[from] + 1, degree[to] + 1
    end
  end

  return g
end

return M
