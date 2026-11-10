-- Physical production graph. Every item connection gets its own filtered
-- inserters and belt; underground crossings preserve separate ingredients.
local router = require("__awesome-artillery__/scenarios/showcase/router")
local M = {}
local DIRS, key, point, distance = router.DIRS, router.key, router.point, router.distance

-- Combat research, defence quality and route of the ship. Modifiers are bonuses (3 = +300%);
-- rotation and velocity are levels of this mod's research. The ship starts at `origin` and
-- shuttles between it and `destination`.
M.SHOWCASE_PROFILE = {damage = 3, fire_rate = 3, rotation = 6, velocity = 4,
  laser_quality = "legendary", laser_damage = 3, laser_fire_rate = 3,
  origin = "vulcanus", destination = "nauvis"}

function M.build(profile)
  profile = profile or M.SHOWCASE_PROFILE
  local force = game.forces.player
  for _, name in ipairs{"vulcanus", "gleba", "fulgora", "aquilo"} do force.unlock_space_location(name) end
  for _, recipe in pairs(force.recipes) do recipe.enabled = true end
  for level = 1, profile.rotation do force.technologies["awe-art-artillery-rotation-" .. level].researched = true end
  force.technologies["awe-art-artillery-shell-velocity-1"].level = profile.velocity + 1
  force.set_ammo_damage_modifier("artillery-shell", profile.damage)
  force.set_gun_speed_modifier("artillery-shell", profile.fire_rate)
  force.inserter_stack_size_bonus = 6
  local platform = force.create_space_platform{
    name = "Artillery Vanguard", planet = profile.origin, starter_pack = "space-platform-starter-pack",
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
  local g = router.new(surface, force, {-43, -61, 43, 44})
  local occupied, port_reservations, dry_access, nodes = g.occupied, g.port_reservations, g.dry_access, g.nodes
  local make, route, lay, fluid_link = g.make, g.route, g.lay, g.fluid_link
  local pole_forbidden = {}
  local machines, ports, links = {}, {}, {}
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
    local turret = make(profile.rotation > 0 and ("awe-art-artillery-turret-r" .. profile.rotation) or "artillery-turret",
      {x, -52.5})
    turrets[i], nodes["gun" .. i] = turret, turret
  end
  local computer = make("awe-art-targeting-computer", {0, -52})
  for _, x in ipairs{-36, -28, 28, 36} do make("laser-turret", {x, -52}, nil, {quality = profile.laser_quality}) end
  force.set_ammo_damage_modifier("laser", profile.laser_damage)
  force.set_gun_speed_modifier("laser", profile.laser_fire_rate)

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

  g.reserve_fluid_ports()
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
      g.active_ports = {[key(a.belt[1], a.belt[2])] = true, [key(b.belt[1], b.belt[2])] = true}
      local finish_dir = (b.dir + 1) % 4 + 1
      local path = route(a.belt, b.belt, "belt", nil, finish_dir, to:match("^gun"))
      g.active_ports = {}
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
  g.connect_poles()

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

  platform.schedule = {current = 1, records = {{station = profile.destination}, {station = profile.origin}}}
  platform.paused = true
  return {platform = platform, nodes = nodes, machines = machines, turrets = turrets,
    steel_loaders = steel_loaders, prom_loaders = prom_loaders, computer = computer, thrusters = thrusters, links = links}
end

return M
