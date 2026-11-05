-- Targeting computers: each working computer is one rule (sizes, asteroid types, sector). An
-- asteroid gets a decoy only if its aim point matches some rule on its platform. Like the
-- roboport, each circuit input is switched on with a checkbox and reads a signal of the
-- player's choice. Asteroid types are asteroid chunks (what an asteroid finally breaks into),
-- sizes are 1 small ... 4 huge; both come from the data-stage catalogue, so modded asteroids work.

local util = require("util")
local deepcopy = util.table.deepcopy

local M = {}

M.NAME = "aa-targeting-computer"
M.BASE_MAX_DISTANCE = 500 -- grows with artillery range research
local SIZES = {"small", "medium", "big", "huge"}
local CHUNK_SLOTS = 8
local SLIDERS = {
  {key = "dir", caption = "Direction", min = 0, max = 345, step = 15, unit = "°", signal = "signal-D"},
  {key = "arc", caption = "Arc width", min = 15, max = 360, step = 15, unit = "°", signal = "signal-A"},
  {key = "near", caption = "Near distance", min = 0, step = 5, unit = " tiles", signal = "signal-N"},
  {key = "far", caption = "Far distance", min = 5, step = 5, unit = " tiles", signal = "signal-F"},
}
local INPUTS = { -- circuit inputs without a slider
  {key = "size", caption = "Minimum size from signal", signal = "signal-S",
    tooltip = "Signal value = smallest size to shoot: 1 small, 2 medium, 3 big, 4 huge"},
  {key = "off", caption = "Switch off when signal > 0", signal = "signal-deny"},
}

-- LuaModData.data copies the whole table on every access, so read it once per session
-- (it's prototype data: identical everywhere, safe to keep outside storage).
local CATALOGUE
local function catalogue()
  CATALOGUE = CATALOGUE or prototypes.mod_data["aa-asteroids"].data
  return CATALOGUE
end
M.catalogue = catalogue

local function max_distance(force)
  return math.floor(M.BASE_MAX_DISTANCE * (1 + force.artillery_range_modifier) / 5) * 5
end

local function default_cfg()
  local cfg = {sizes = {}, chunks = {}, dir = 0, arc = 360, near = 0, far = M.BASE_MAX_DISTANCE, signals = {}, use = {}}
  for _, s in pairs(SIZES) do cfg.sizes[s] = true end
  return cfg
end

-- Fill in anything missing (older configs, blueprint tags, test configs).
local function complete(cfg)
  local d = default_cfg()
  for k, v in pairs(d) do if cfg[k] == nil then cfg[k] = v end end
  for _, s in pairs(SLIDERS) do cfg.signals[s.key] = cfg.signals[s.key] or {type = "virtual", name = s.signal} end
  for _, s in pairs(INPUTS) do cfg.signals[s.key] = cfg.signals[s.key] or {type = "virtual", name = s.signal} end
  return cfg
end
M.complete = complete

function M.init()
  storage.computers = storage.computers or {} -- unit_number -> {entity, cfg}
  storage.open_computer = storage.open_computer or {} -- player index -> unit_number
  storage.zones = storage.zones or {}
end

function M.add(entity, tags)
  local cfg = tags and tags.aa_cfg and deepcopy(tags.aa_cfg) or default_cfg()
  storage.computers[entity.unit_number] = {entity = entity, cfg = complete(cfg)}
end

function M.rescan()
  storage.computers = {}
  for _, s in pairs(game.surfaces) do
    for _, e in pairs(s.find_entities_filtered{name = M.NAME}) do M.add(e) end
  end
end

local function sig_key(id) return (id.type or "item") .. ":" .. id.name end

local function read_signals(e)
  local out = {}
  for _, id in pairs{defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green} do
    local net = e.get_circuit_network(id)
    for _, s in pairs(net and net.signals or {}) do
      local k = sig_key(s.signal)
      out[k] = (out[k] or 0) + s.count
    end
  end
  return out
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function chunk_set(list)
  local set
  for _, c in pairs(list) do if c then set = set or {}; set[c] = true end end
  return set -- nil = every type
end

-- The rule a computer applies right now, with circuit inputs; nil if off or unpowered.
local function effective(c)
  local e, cfg = c.entity, c.cfg
  if e.status == defines.entity_status.no_power or e.energy <= 0 then return nil end
  local sig = read_signals(e)
  local function get(key)
    local id = cfg.use[key] and cfg.signals[key]
    return id and sig[sig_key(id)]
  end
  if (get("off") or 0) > 0 then return nil end
  local limit = max_distance(e.force)
  local r = {x = e.position.x, y = e.position.y, dir = cfg.dir, arc = cfg.arc, near = cfg.near,
    far = math.min(cfg.far, limit), sizes = cfg.sizes, chunks = chunk_set(cfg.chunks), inputs = {}}
  for _, s in pairs(SLIDERS) do
    local v = get(s.key)
    if v then r.inputs[#r.inputs + 1] = s.caption:lower() end
    if v and s.key == "dir" then r.dir = v % 360 end
    if v and s.key == "arc" then r.arc = clamp(v, 1, 360) end
    if v and s.key == "near" then r.near = clamp(v, 0, limit) end
    if v and s.key == "far" then r.far = clamp(v, 0, limit) end
  end
  local min_size = get("size")
  if min_size then
    r.inputs[#r.inputs + 1] = "minimum size"
    r.sizes = {}
    for i, s in pairs(SIZES) do if i >= min_size then r.sizes[s] = true end end
  end
  if cfg.use.types then
    local set
    for k, v in pairs(sig) do
      local name = k:match("^asteroid%-chunk:(.+)$") or k:match("^item:(.+%-asteroid%-chunk)$")
      if name and v > 0 and prototypes.asteroid_chunk[name] then set = set or {}; set[name] = true end
    end
    if set then r.chunks = set; r.inputs[#r.inputs + 1] = "types" end
  end
  return r
end

-- Working rules on a surface, and whether any computer (working or not) is there.
function M.rules(surface_index)
  local rules, present = {}, false
  for k, c in pairs(storage.computers) do
    if not c.entity.valid then
      storage.computers[k] = nil
    elseif c.entity.surface.index == surface_index then
      present = true
      local r = effective(c)
      if r then rules[#rules + 1] = r end
    end
  end
  return rules, present
end

local function in_sector(r, x, y)
  local dx, dy = x - r.x, y - r.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < r.near or d > r.far then return false end
  if r.arc >= 360 then return true end
  local angle = math.deg(math.atan2(dx, -dy)) % 360 -- 0 = north, clockwise
  local diff = (angle - r.dir + 540) % 360 - 180
  return math.abs(diff) <= r.arc / 2
end

function M.allows(rules, asteroid_name, x, y)
  local info = catalogue()[asteroid_name]
  if not info then return false end
  local size = SIZES[info.size]
  for _, r in pairs(rules) do
    if r.sizes[size] and (not r.chunks or r.chunks[info.chunk]) and in_sector(r, x, y) then return true end
  end
  return false
end

-- Zone drawing: a translucent fill plus a stronger outline, as persistent render objects.
local FILL, EDGE = 0.22, 0.7
local function rgba(a) return {0.25 * a, 0.6 * a, 1 * a, a} end -- render colours are premultiplied

local function draw_zone(surface, r, players)
  local objs = {}
  local full = r.arc >= 360
  -- rendering angles: 0 = east, clockwise; ours: 0 = north, clockwise
  local start = full and 0 or math.rad(r.dir - 90 - r.arc / 2)
  local angle = full and 2 * math.pi or math.rad(r.arc)
  local base = {surface = surface, players = players, target = {r.x, r.y}, draw_on_ground = true,
    start_angle = start, angle = angle}
  local function arc(min_r, max_r, a)
    local args = deepcopy(base)
    args.min_radius, args.max_radius, args.color = min_r, max_r, rgba(a)
    objs[#objs + 1] = rendering.draw_arc(args)
  end
  arc(r.near, r.far, FILL)
  arc(math.max(r.far - 0.5, r.near), r.far, EDGE)
  if r.near > 0 then arc(r.near, r.near + 0.5, EDGE) end
  if not full then
    for _, a in pairs{start, start + angle} do
      local cx, cy = math.cos(a), math.sin(a)
      objs[#objs + 1] = rendering.draw_line{surface = surface, players = players, color = rgba(EDGE), width = 3,
        from = {r.x + cx * r.near, r.y + cy * r.near}, to = {r.x + cx * r.far, r.y + cy * r.far}, draw_on_ground = true}
    end
  end
  return objs
end

-- GUI ---------------------------------------------------------------------------------

local function describe(r)
  if not r then return "[color=1,0.4,0.4]Off (no power or switched off by signal)[/color]" end
  local sizes, types = {}, {}
  for _, s in pairs(SIZES) do if r.sizes[s] then sizes[#sizes + 1] = s end end
  if r.chunks then
    for name in pairs(r.chunks) do types[#types + 1] = "[asteroid-chunk=" .. name .. "]" end
  else
    types[1] = "all types"
  end
  local text = string.format("Now: %s; %s; %d° ±%d°; %d-%d tiles", table.concat(sizes, ", "),
    table.concat(types, ""), r.dir, r.arc / 2, r.near, r.far)
  if #r.inputs > 0 then text = text .. "\n[color=0.6,0.9,0.6]From circuit: " .. table.concat(r.inputs, ", ") .. "[/color]" end
  return text
end

local function input_controls(parent, key, cfg, caption, tooltip)
  local flow = parent.add{type = "flow", direction = "horizontal"}
  flow.style.vertical_align = "center"
  flow.add{type = "checkbox", name = "aa_tc_use_" .. key, state = cfg.use[key] or false, caption = caption,
    tooltip = tooltip or "Read this setting from the circuit network"}
  if cfg.signals[key] then
    local b = flow.add{type = "choose-elem-button", name = "aa_tc_sig_" .. key, elem_type = "signal",
      signal = cfg.signals[key], tooltip = "Signal to read"}
    b.style.size = 32
  end
  return flow
end

function M.open(p, entity)
  local c = storage.computers[entity.unit_number]
  if not c then M.add(entity); c = storage.computers[entity.unit_number] end
  if p.gui.screen.aa_tc then p.gui.screen.aa_tc.destroy() end
  local limit = max_distance(entity.force)
  local f = p.gui.screen.add{type = "frame", name = "aa_tc", caption = "Targeting computer", direction = "vertical"}
  f.auto_center = true
  storage.open_computer[p.index] = entity.unit_number
  local inner = f.add{type = "frame", name = "inner", style = "inside_shallow_frame_with_padding", direction = "vertical"}

  local sizes = inner.add{type = "flow", direction = "horizontal"}
  sizes.add{type = "label", caption = "Sizes", style = "bold_label"}.style.width = 60
  for _, s in pairs(SIZES) do sizes.add{type = "checkbox", name = "aa_tc_size_" .. s, caption = s, state = c.cfg.sizes[s]} end

  local types = inner.add{type = "flow", direction = "horizontal"}
  types.style.vertical_align = "center"
  types.add{type = "label", caption = "Types", style = "bold_label",
    tooltip = "Asteroid chunks the asteroid breaks into. Leave all empty for every type."}.style.width = 60
  for i = 1, CHUNK_SLOTS do
    types.add{type = "choose-elem-button", name = "aa_tc_chunk_" .. i, elem_type = "asteroid-chunk",
      ["asteroid-chunk"] = c.cfg.chunks[i], tooltip = "Asteroid type to shoot (empty slots = no restriction)"}
  end

  inner.add{type = "line"}
  local tbl = inner.add{type = "table", name = "sliders", column_count = 4, vertical_centering = true}
  for _, s in pairs(SLIDERS) do
    local max = s.max or limit
    tbl.add{type = "label", caption = s.caption}.style.minimal_width = 110
    local sl = tbl.add{type = "slider", name = "aa_tc_" .. s.key, minimum_value = s.min, maximum_value = max,
      value_step = s.step, discrete_slider = true, value = clamp(c.cfg[s.key], s.min, max)}
    sl.style.width = 200
    tbl.add{type = "label", name = "aa_tc_" .. s.key .. "_readout", caption = c.cfg[s.key] .. s.unit}.style.minimal_width = 70
    input_controls(tbl, s.key, c.cfg, "from signal")
  end

  inner.add{type = "line"}
  inner.add{type = "label", caption = "Circuit network", style = "bold_label"}
  for _, s in pairs(INPUTS) do input_controls(inner, s.key, c.cfg, s.caption, s.tooltip) end
  input_controls(inner, "types", c.cfg, "Asteroid types from chunk signals",
    "Any asteroid chunk signal > 0 on the wire replaces the type slots above")

  inner.add{type = "line"}
  local now = inner.add{type = "label", name = "aa_tc_now", caption = describe(effective(c))}
  now.style.single_line = false
  now.style.maximal_width = 480
  p.opened = f
end

local function open_entry(p)
  local id = storage.open_computer[p.index]
  local c = id and storage.computers[id]
  if c and c.entity.valid then return c end
end

local function zone_sig(r)
  return string.format("%.1f,%.1f,%d,%d,%d,%d", r.x, r.y, r.dir, r.arc, r.near, r.far)
end

-- Zones are persistent render objects, redrawn only when the rule they show changes
-- (re-drawing short-lived copies every update made them flicker).
-- Shown: the open computer's zone to that player; with debug on, every zone to everyone.
function M.sync_zones()
  storage.zones = storage.zones or {} -- key -> {objs, sig}
  local want = {}
  local function wish(c, player)
    local r = effective(c)
    if not r then return end
    local key = c.entity.unit_number .. "|" .. (player and player.index or "all")
    want[key] = {c = c, r = r, player = player, sig = zone_sig(r)}
  end
  if storage.debug then
    for _, c in pairs(storage.computers) do if c.entity.valid then wish(c) end end
  end
  for _, p in pairs(game.connected_players) do
    local c = open_entry(p)
    if c and p.gui.screen.aa_tc and not storage.debug then wish(c, p) end
  end
  for key, z in pairs(storage.zones) do
    local w = want[key]
    local intact = z.objs and true
    for _, o in pairs(z.objs or {}) do intact = intact and o.valid end
    if not (w and w.sig == z.sig and intact) then
      for _, o in pairs(z.objs or {}) do if o.valid then o.destroy() end end
      storage.zones[key] = nil
    end
  end
  for key, w in pairs(want) do
    if not storage.zones[key] then
      storage.zones[key] = {sig = w.sig, objs = draw_zone(w.c.entity.surface, w.r, w.player and {w.player} or nil)}
    end
  end
end

function M.refresh_open()
  for _, p in pairs(game.connected_players) do
    local c = open_entry(p)
    local f = p.gui.screen.aa_tc
    if c and f then f.inner.aa_tc_now.caption = describe(effective(c)) end
  end
  M.sync_zones()
end

script.on_event(defines.events.on_gui_opened, function(e)
  if e.entity and e.entity.valid and e.entity.name == M.NAME then M.open(game.get_player(e.player_index), e.entity) end
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if e.element and e.element.valid and e.element.name == "aa_tc" then
    e.element.destroy()
    storage.open_computer[e.player_index] = nil
    M.sync_zones()
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  local name = e.element.name
  if not c or name:sub(1, 6) ~= "aa_tc_" then return end
  local size = name:match("^aa_tc_size_(%a+)$")
  local use = name:match("^aa_tc_use_(%a+)$")
  if size then c.cfg.sizes[size] = e.element.state end
  if use then c.cfg.use[use] = e.element.state end
  M.refresh_open()
end)

script.on_event(defines.events.on_gui_value_changed, function(e)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  if not c then return end
  for _, s in pairs(SLIDERS) do
    if e.element.name == "aa_tc_" .. s.key then
      c.cfg[s.key] = e.element.slider_value
      e.element.parent["aa_tc_" .. s.key .. "_readout"].caption = c.cfg[s.key] .. s.unit
    end
  end
  M.refresh_open()
end)

script.on_event(defines.events.on_gui_elem_changed, function(e)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  if not c then return end
  local key = e.element.name:match("^aa_tc_sig_(%a+)$")
  local slot = tonumber(e.element.name:match("^aa_tc_chunk_(%d+)$"))
  if key then
    -- keep a signal selected: an input without one can't be switched on
    if e.element.elem_value then c.cfg.signals[key] = e.element.elem_value else e.element.elem_value = c.cfg.signals[key] end
  elseif slot then
    c.cfg.chunks[slot] = e.element.elem_value
  else
    return
  end
  M.refresh_open()
end)

script.on_event(defines.events.on_entity_settings_pasted, function(e)
  if e.source.name == M.NAME and e.destination.name == M.NAME then
    local src = storage.computers[e.source.unit_number]
    if src then M.add(e.destination, {aa_cfg = src.cfg}) end
  end
end)

script.on_event(defines.events.on_player_setup_blueprint, function(e)
  local p = game.get_player(e.player_index)
  local bp = e.stack
  if not (bp and bp.valid_for_read and bp.is_blueprint) then bp = p.blueprint_to_setup end
  if not (bp and bp.valid_for_read) then return end
  for index, ent in pairs(e.mapping.get()) do
    local c = ent.valid and ent.name == M.NAME and storage.computers[ent.unit_number]
    if c then bp.set_blueprint_entity_tag(index, "aa_cfg", c.cfg) end
  end
end)

return M
