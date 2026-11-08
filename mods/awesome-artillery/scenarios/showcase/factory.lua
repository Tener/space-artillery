-- Physical production graph. Every item connection gets its own filtered
-- inserters and belt; underground crossings preserve separate ingredients.
local M = {}
local DIRS = {{0, -1, defines.direction.north}, {1, 0, defines.direction.east},
  {0, 1, defines.direction.south}, {-1, 0, defines.direction.west}}
local function key(x, y) return x .. "," .. y end
local function point(p) return {p[1] + 0.5, p[2] + 0.5} end
local function distance(a, b) return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) end

function M.build()
  local force = game.forces.player
  for _, name in ipairs{"vulcanus", "gleba", "aquilo"} do force.unlock_space_location(name) end
  for _, recipe in pairs(force.recipes) do recipe.enabled = true end
  for level = 1, 6 do force.technologies["awe-art-artillery-rotation-" .. level].researched = true end
  force.technologies["awe-art-artillery-shell-velocity-1"].level = 5
  force.set_ammo_damage_modifier("artillery-shell", 3)
  force.set_gun_speed_modifier("artillery-shell", 3)
  force.inserter_stack_size_bonus = 6
  local platform = force.create_space_platform{
    name = "Artillery Vanguard", planet = "vulcanus", starter_pack = "space-platform-starter-pack",
  }
  platform.apply_starter_pack()
  local surface = platform.surface
  surface.request_to_generate_chunks({0, -30}, 6)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for y = -62, 44 do
    local half = y < -54 and 35 or (y > 34 and 30 or 44)
    for x = -half, half do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end
  end
  for _, sign in ipairs{-1, 1} do
    for x = 45, 64 do
      for y = -52, 33 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {sign * x, y}} end
    end
  end
  surface.set_tiles(tiles)
  for _, y in ipairs{-33, -25, -11, 3, 15, 29} do
    surface.set_tiles{{name = "empty-space", position = {43, y}}}
  end
  local occupied, tunnels, fluid_cells, fluid_reservations = {}, {}, {}, {}
  local port_reservations, active_ports = {}, {}
  local pole_forbidden, dry_access = {}, {}
  local nodes, machines, ports, links = {}, {}, {}, {}
  for x = -43, 43 do
    for y = -61, 44 do
      if surface.get_tile(x, y).name ~= "space-platform-foundation" then occupied[key(x, y)] = {solid = true} end
    end
  end

  local function make(name, p, direction, extra)
    local args = {name = name, position = p, force = force, direction = direction or defines.direction.north,
      raise_built = true}
    for k, v in pairs(extra or {}) do args[k] = v end
    assert(surface.can_place_entity(args), "showcase blocked: " .. name .. " " .. serpent.line(p))
    local entity = assert(surface.create_entity(args))
    entity.destructible = false
    local box = entity.bounding_box
    for x = math.floor(box.left_top.x), math.ceil(box.right_bottom.x) - 1 do
      for y = math.floor(box.left_top.y), math.ceil(box.right_bottom.y) - 1 do
        occupied[key(x, y)] = {entity = entity, solid = true}
      end
    end
    return entity
  end
  local function machine(id, name, p, recipe, direction)
    local entity = make(name, p, direction, {recipe = recipe,
      quality = (name == "crusher" or id == "water" or id == "coal" or id == "explosives") and "legendary" or "normal"})
    nodes[id], machines[#machines + 1] = entity, entity
    local inventory = entity.get_module_inventory()
    if inventory then inventory.insert{name = "speed-module-3", count = #inventory} end
    return entity
  end

  -- Collection and crushing at the prow; metallurgy and component production
  -- occupy the middle; propulsion and its chemical plants sit at the stern.
  for i, spec in ipairs{{"metal", -30.5, "metallic"}, {"carbon", -10.5, "carbonic"},
    {"oxide", 9.5, "oxide"}, {"promethium", 29.5, "promethium"}} do
    local collector = make("asteroid-collector", {spec[2], -61.5})
    collector.set_filter(1, spec[3] .. "-asteroid-chunk")
    nodes[spec[1] .. "_collector"] = collector
  end
  machine("metal", "crusher", {-26, -34.5}, "advanced-metallic-asteroid-crushing")
  machine("carbon", "crusher", {0, -34.5}, "advanced-carbonic-asteroid-crushing")
  machine("carbon_propulsion", "crusher", {-32, 28.5}, "advanced-carbonic-asteroid-crushing")
  machine("oxide", "crusher", {26, -34.5}, "advanced-oxide-asteroid-crushing")
  machine("oxide_propulsion", "crusher", {30, 4.5}, "advanced-oxide-asteroid-crushing")
  machine("melt", "foundry", {-30.5, -18.5}, "iron-ore-melting", defines.direction.east)
  machine("steel", "foundry", {-16.5, -18.5}, "awe-art-flash-hardened-steel", defines.direction.east)
  machine("shells", "foundry", {-16.5, -35.5}, "awe-art-steel-artillery-shell")
  machine("prom_shells", "foundry", {15.5, -35.5}, "awe-art-promethium-artillery-shell")
  machine("water", "chemical-plant", {26.5, -18.5}, "ice-melting")
  machine("coal", "chemical-plant", {10.5, -18.5}, "coal-synthesis")
  machine("explosives", "chemical-plant", {18.5, -4.5}, "explosives")
  machine("copper", "electric-furnace", {-32.5, 0.5})
  machine("iron", "foundry", {-18.5, 0.5}, "casting-iron")
  machine("cable", "electromagnetic-plant", {-32.5, 14.5}, "copper-cable")
  machine("circuits", "electromagnetic-plant", {-16.5, 14.5}, "electronic-circuit")
  machine("gears", "assembling-machine-3", {-3.5, 14.5}, "iron-gear-wheel")
  machine("radar", "assembling-machine-3", {-3.5, 28.5}, "radar")
  machine("fuel", "chemical-plant", {16.5, 20.5}, "advanced-thruster-fuel")
  machine("oxidizer", "chemical-plant", {30.5, 20.5}, "advanced-thruster-oxidizer")
  for _, spec in ipairs{{"copper", -32.5}, {"sulfur", -24.5}, {"calcite", -10.5},
    {"carbon", 3.5}, {"ice", 15.5}, {"iron", 29.5}} do
    nodes["waste_" .. spec[1]] = make("turbo-transport-belt", {41.5, spec[2]}, defines.direction.east)
    make("bulk-inserter", {42.5, spec[2]}, defines.direction.west)
  end
  local thrusters = {}
  for i, x in ipairs{-24, 0, 24} do
    thrusters[i] = make("thruster", {x, 42.5})
    nodes["thruster" .. i] = thrusters[i]
  end
  local turrets, steel_loaders, prom_loaders = {}, {}, {}
  for i, x in ipairs{-12.5, -4.5, 4.5, 12.5} do
    local turret = make("awe-art-artillery-turret-r6", {x, -52.5})
    turrets[i], nodes["gun" .. i] = turret, turret
  end
  local computer = make("awe-art-targeting-computer", {0, -52})
  for _, x in ipairs{-36, -28, 28, 36} do make("laser-turret", {x, -52}, nil, {quality = "legendary"}) end
  force.set_ammo_damage_modifier("laser", 3)
  force.set_gun_speed_modifier("laser", 3)
  local wire = computer.get_wire_connector(defines.wire_connector_id.circuit_red, true)
  for i, turret in ipairs(turrets) do
    local source = (i == 1 and turrets[2]) or (i == 4 and turrets[3])
    local connector = source and source.get_wire_connector(defines.wire_connector_id.circuit_red, true) or wire
    assert(connector.connect_to(turret.get_wire_connector(defines.wire_connector_id.circuit_red, true)))
  end

  -- Reserve the hub as an obstacle even though production never uses its stock.
  local hub = platform.hub
  hub.destructible = false
  nodes.magazine = hub
  local hb = hub.bounding_box
  for x = math.floor(hb.left_top.x), math.ceil(hb.right_bottom.x) - 1 do
    for y = math.floor(hb.left_top.y), math.ceil(hb.right_bottom.y) - 1 do
      occupied[key(x, y)] = {solid = true}
    end
  end
  for _, entity in pairs(nodes) do
    local p, proto = entity.position, entity.prototype
    local left, top = math.floor(p.x - proto.tile_width / 2), math.floor(p.y - proto.tile_height / 2)
    for x = left - 2, left + proto.tile_width + 1 do
      for y = top - 2, top + proto.tile_height + 1 do
        pole_forbidden[key(x, y)] = true
        if entity.fluids_count == 0 then dry_access[key(x, y)] = true end
      end
    end
  end

  -- Deterministic A* with underground crossings. Machine footprints cannot be
  -- tunneled through; perpendicular tunnels may cross, parallel tunnels may not.
  local function route(start, goal, kind, fluid, finish_dir, normal_start)
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
      if x < -43 or x > 43 or y < -61 or y > 44 then return false end
      local cell = occupied[key(x, y)]
      if cell and not (kind == "pipe" and cell.fluid == fluid) then return false end
      if kind == "belt" and port_reservations[key(x, y)] and not active_ports[key(x, y)] then return false end
      if kind == "pipe" then
        if dry_access[key(x, y)] then return false end
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

  local function lay(path, kind, fluid, finish_dir)
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
        make(name, point(p), DIRS[dir][3], extra)
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
  local function fluid_link(from, to, fluid)
    local starts = fluid_ports(nodes[from], fluid, true)
    for cell, name in pairs(fluid_cells) do
      if name == fluid then
        local x, y = cell:match("(-?%d+),(-?%d+)")
        starts[#starts + 1] = {tonumber(x), tonumber(y)}
      end
    end
    for _, b in ipairs(fluid_ports(nodes[to], fluid, false)) do
      table.sort(starts, function(a, c) return distance(a, b) < distance(c, b) end)
      for _, a in ipairs(starts) do
        local path = route(a, b, "pipe", fluid)
        if path then lay(path, "pipe", fluid); return end
      end
    end
    error("no pipe route: " .. from .. " -> " .. to .. " " .. fluid)
  end
  for _, entity in pairs(nodes) do
    for index = 1, entity.fluids_count do
      local filter = entity.get_fluid_filter(index)
      if filter then
        for _, connection in pairs(entity.get_fluid_box_pipe_connections(index) or {}) do
          fluid_reservations[key(math.floor(connection.target_position.x), math.floor(connection.target_position.y))] = filter.name
        end
      end
    end
  end
  for _, spec in ipairs{
    {"melt", "steel", "molten-iron"}, {"melt", "iron", "molten-iron"}, {"water", "coal", "water"},
    {"water", "explosives", "water"}, {"water", "fuel", "water"}, {"water", "oxidizer", "water"},
  } do fluid_link(table.unpack(spec)) end
  for i = 1, 3 do
    fluid_link("fuel", "thruster" .. i, "thruster-fuel")
    fluid_link("oxidizer", "thruster" .. i, "thruster-oxidizer")
  end

  -- Reserve substation footprints before routing the dedicated item belts.
  for x = -36, 36, 12 do
    for y = -55, 29, 12 do
      local placed = false
      for dx = -5, 5 do
        for dy = -5, 5 do
          local clear = true
          for px = x + dx - 1, x + dx do
            for py = y + dy - 1, y + dy do
              if pole_forbidden[key(px, py)] then clear = false end
            end
          end
          if not placed and clear and surface.can_place_entity{name = "substation", position = {x + dx, y + dy}, force = force, quality = "legendary"} then
            make("substation", {x + dx, y + dy}, nil, {quality = "legendary"})
            placed = true
          end
        end
      end
      assert(placed, "no substation space at " .. x .. "," .. y)
    end
  end

  local function item_ports(entity)
    local result = {}
    if ports[entity.unit_number] then
      for _, port in ipairs(ports[entity.unit_number]) do
        if not occupied[key(port.inserter[1], port.inserter[2])] and
          not occupied[key(port.belt[1], port.belt[2])] then result[#result + 1] = port end
      end
      return result
    end
    local p, proto = entity.position, entity.prototype
    local left, top = math.floor(p.x - proto.tile_width / 2), math.floor(p.y - proto.tile_height / 2)
    local right, bottom = left + proto.tile_width - 1, top + proto.tile_height - 1
    for dir, d in ipairs(DIRS) do
      local low, high = d[1] == 0 and left or top, d[1] == 0 and right or bottom
      for n = low, high do
        local x = d[1] == 0 and n or (d[1] < 0 and left or right)
        local y = d[2] == 0 and n or (d[2] < 0 and top or bottom)
        local inserter, belt = {x + d[1], y + d[2]}, {x + d[1] * 2, y + d[2] * 2}
        if not occupied[key(inserter[1], inserter[2])] and not occupied[key(belt[1], belt[2])] then
          result[#result + 1] = {inserter = inserter, belt = belt, dir = dir}
        end
      end
    end
    return result
  end
  local function item_link(from, to, item)
    local pairs_by_distance = {}
    for _, a in ipairs(item_ports(nodes[from])) do
      for _, b in ipairs(item_ports(nodes[to])) do
        if distance(a.inserter, b.inserter) > 2 then
          pairs_by_distance[#pairs_by_distance + 1] = {a, b, distance(a.belt, b.belt)}
        end
      end
    end
    table.sort(pairs_by_distance, function(a, b) return a[3] < b[3] end)
    for _, pair in ipairs(pairs_by_distance) do
      local a, b = pair[1], pair[2]
      occupied[key(a.inserter[1], a.inserter[2])] = {solid = true}
      occupied[key(b.inserter[1], b.inserter[2])] = {solid = true}
      active_ports = {[key(a.belt[1], a.belt[2])] = true, [key(b.belt[1], b.belt[2])] = true}
      local finish_dir = (b.dir + 1) % 4 + 1
      local path = route(a.belt, b.belt, "belt", nil, finish_dir, to:match("^gun"))
      active_ports = {}
      occupied[key(a.inserter[1], a.inserter[2])] = nil
      occupied[key(b.inserter[1], b.inserter[2])] = nil
      if path then
        local source = make("bulk-inserter", point(a.inserter), DIRS[(a.dir + 1) % 4 + 1][3])
        source.set_filter(1, item)
        source.use_filters = true
        local destination = make("bulk-inserter", point(b.inserter), DIRS[b.dir][3])
        destination.set_filter(1, item)
        destination.use_filters = true
        lay(path, "belt", nil, finish_dir)
        links[#links + 1] = {from = from, to = to, item = item, source = source, destination = destination, path = path}
        if to:match("^gun") then
          local belt = assert(surface.find_entity("turbo-transport-belt", point(path[1])))
          local read = belt.get_or_create_control_behavior()
          read.read_contents = true
          read.read_contents_mode = defines.control_behavior.transport_belt.content_read_mode.entire_belt_hold
          assert(source.get_wire_connector(defines.wire_connector_id.circuit_red, true)
            .connect_to(belt.get_wire_connector(defines.wire_connector_id.circuit_red, true)))
          local behavior = source.get_or_create_control_behavior()
          behavior.circuit_enable_disable = true
          behavior.circuit_condition = {first_signal = {type = "item", name = item}, comparator = "<", constant = 12}
          nodes[to].get_or_create_control_behavior().read_ammo = true
          assert(destination.get_wire_connector(defines.wire_connector_id.circuit_green, true)
            .connect_to(nodes[to].get_wire_connector(defines.wire_connector_id.circuit_green, true)))
          destination.inserter_stack_size_override = 1
          local loading = destination.get_or_create_control_behavior()
          loading.circuit_enable_disable = true
          loading.circuit_condition = {first_signal = {type = "item", name = item}, comparator = "<", constant = 5}
        end
        return destination
      end
    end
    error("no belt route: " .. from .. " -> " .. to .. " " .. item ..
      "; available ports " .. #item_ports(nodes[from]) .. "/" .. #item_ports(nodes[to]))
  end

  for _, entity in pairs(nodes) do
    local available = item_ports(entity)
    ports[entity.unit_number] = available
    for _, port in ipairs(available) do
      port_reservations[key(port.inserter[1], port.inserter[2])] = true
      port_reservations[key(port.belt[1], port.belt[2])] = true
    end
  end

  for i = 1, 4 do
    steel_loaders[i] = item_link("magazine", "gun" .. i, "awe-art-steel-artillery-shell")
    prom_loaders[i] = item_link("magazine", "gun" .. i, "awe-art-promethium-artillery-shell")
    prom_loaders[i].disabled_by_script = true
  end

  for _, spec in ipairs{
    {"shells", "magazine", "awe-art-steel-artillery-shell"},
    {"prom_shells", "magazine", "awe-art-promethium-artillery-shell"},
    {"metal_collector", "metal", "metallic-asteroid-chunk"},
    {"carbon_collector", "carbon", "carbonic-asteroid-chunk"},
    {"carbon_collector", "carbon_propulsion", "carbonic-asteroid-chunk"},
    {"oxide_collector", "oxide", "oxide-asteroid-chunk"},
    {"oxide_collector", "oxide_propulsion", "oxide-asteroid-chunk"},
    {"promethium_collector", "prom_shells", "promethium-asteroid-chunk"},
    {"metal", "metal", "metallic-asteroid-chunk"},
    {"carbon", "carbon", "carbonic-asteroid-chunk"},
    {"carbon_propulsion", "carbon_propulsion", "carbonic-asteroid-chunk"},
    {"oxide", "oxide", "oxide-asteroid-chunk"},
    {"oxide_propulsion", "oxide_propulsion", "oxide-asteroid-chunk"},
    {"metal", "melt", "iron-ore"}, {"metal", "copper", "copper-ore"},
    {"oxide", "melt", "calcite"}, {"oxide", "steel", "calcite"}, {"oxide", "steel", "ice"},
    {"oxide", "water", "ice"}, {"carbon", "steel", "carbon"},
    {"carbon", "coal", "carbon"}, {"carbon", "coal", "sulfur"},
    {"carbon_propulsion", "coal", "carbon"},
    {"carbon_propulsion", "coal", "sulfur"}, {"carbon_propulsion", "explosives", "sulfur"},
    {"carbon", "explosives", "sulfur"}, {"coal", "explosives", "coal"},
    {"steel", "shells", "awe-art-flash-hardened-steel"},
    {"steel", "prom_shells", "awe-art-flash-hardened-steel"},
    {"explosives", "shells", "explosives"}, {"explosives", "prom_shells", "explosives"},
    {"copper", "cable", "copper-plate"}, {"cable", "circuits", "copper-cable"},
    {"iron", "circuits", "iron-plate"}, {"iron", "gears", "iron-plate"},
    {"iron", "radar", "iron-plate"}, {"gears", "radar", "iron-gear-wheel"},
    {"circuits", "radar", "electronic-circuit"}, {"radar", "shells", "radar"},
    {"radar", "prom_shells", "radar"},
    {"carbon_propulsion", "fuel", "carbon"}, {"metal", "oxidizer", "iron-ore"},
    {"oxide_propulsion", "fuel", "calcite"}, {"oxide_propulsion", "oxidizer", "calcite"},
    {"oxide_propulsion", "water", "ice"},
  } do item_link(table.unpack(spec)) end

  -- Trim secondary outputs with real circuit conditions. Retained stock feeds
  -- consumers; excess cannot stop a crusher from supplying its primary output.
  for _, spec in ipairs{{"metal", "waste_copper", "copper-ore"},
    {"carbon", "waste_sulfur", "sulfur"}, {"oxide", "waste_calcite", "calcite"},
    {"carbon_propulsion", "waste_sulfur", "sulfur"},
    {"oxide_propulsion", "waste_calcite", "calcite"},
    {"metal", "waste_iron", "iron-ore", 4},
    {"carbon", "waste_carbon", "carbon", 3}, {"carbon_propulsion", "waste_carbon", "carbon", 3},
    {"oxide", "waste_ice", "ice", 2}, {"oxide_propulsion", "waste_ice", "ice", 2}} do
    item_link(spec[1], spec[2], spec[3])
    local source = links[#links].source
    source.inserter_stack_size_override = 1
    local machine_entity = nodes[spec[1]]
    machine_entity.get_or_create_control_behavior().circuit_read_contents = true
    assert(source.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      .connect_to(machine_entity.get_wire_connector(defines.wire_connector_id.circuit_red, true)))
    local behavior = source.get_or_create_control_behavior()
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = {
      first_signal = {type = "item", name = spec[3]}, comparator = ">", constant = spec[4] or 1,
    }
  end

  for _, sign in ipairs{-1, 1} do
    for _, x in ipairs{50, 62} do
      for y = -44, 28, 18 do make("substation", {sign * x, y}, nil, {quality = "legendary"}) end
    end
    for x = 46.5, 61.5, 3 do
      for y = -49.5, 31.5, 3 do
        local position = {sign * x, y}
        if surface.can_place_entity{name = "solar-panel", position = position, force = force, quality = "legendary"} then
          make("solar-panel", position, nil, {quality = "legendary"})
        end
      end
    end
  end
  -- A short spanning tree carries the same power without a mesh of long wires
  -- crossing the production views. Circuit wires retain their separate networks.
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
    assert(from and to, "showcase power grid is disconnected")
    assert(poles[from].get_wire_connector(defines.wire_connector_id.pole_copper, true)
      .connect_to(poles[to].get_wire_connector(defines.wire_connector_id.pole_copper, true)))
    connected[to], degree[from], degree[to] = true, degree[from] + 1, degree[to] + 1
  end

  for id, entity in pairs(nodes) do
    if entity.type == "assembling-machine" then
      local recipe = entity.get_recipe()
      for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type == "item" then
          local supplied = false
          for _, link in ipairs(links) do
            if link.to == id and link.item == ingredient.name then supplied = true; break end
          end
          assert(supplied, "missing production input: " .. id .. " needs " .. ingredient.name)
        end
      end
    end
  end
  for _, link in ipairs(links) do
    for i = 1, #link.path - 1 do
      local a, b = link.path[i], link.path[i + 1]
      local first = surface.find_entities_filtered{position = point(a), type = {"transport-belt", "underground-belt"}}[1]
      local second = surface.find_entities_filtered{position = point(b), type = {"transport-belt", "underground-belt"}}[1]
      assert(first and second, "missing belt on " .. link.from .. " -> " .. link.to)
      local connected = false
      if distance(a, b) > 1 then
        connected = first.underground_belt_neighbour == second
      else
        for _, output in pairs(first.belt_neighbours.outputs) do
          if output == second then connected = true end
        end
      end
      assert(connected, "disconnected belt: " .. link.from .. " -> " .. link.to ..
        " at " .. serpent.line(a) .. " -> " .. serpent.line(b))
    end
  end

  platform.schedule = {current = 1, records = {{station = "nauvis"}, {station = "vulcanus"}}}
  platform.paused = true
  return {platform = platform, nodes = nodes, machines = machines, turrets = turrets,
    steel_loaders = steel_loaders, prom_loaders = prom_loaders, computer = computer, thrusters = thrusters, links = links}
end

return M
