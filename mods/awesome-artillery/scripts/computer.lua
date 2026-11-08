-- Targeting computers: each working computer is one rule (sizes, asteroid types, sector). An
-- asteroid gets a decoy only if its aim point matches some rule on its platform. Like the
-- roboport, each circuit input is switched on with a checkbox and reads a signal of the
-- player's choice. Asteroid types are asteroid chunks (what an asteroid finally breaks into),
-- sizes are 1 small ... 4 huge; both come from the data-stage catalogue, so modded asteroids work.

local util = require("util")
local deepcopy = util.table.deepcopy

local M = {}

M.NAME = "awe-art-targeting-computer"
M.BASE_MAX_DISTANCE = 500 -- grows with artillery range research
local SIZES = {"small", "medium", "big", "huge"}
local SIZE_LABELS = {small = "Small", medium = "Medium", big = "Big", huge = "Huge"}
local CHUNK_SLOTS = 6
local SLIDERS = {
  {key = "dir", caption = "Direction", min = 0, exact_min = 0, max = 345, exact_max = 359, step = 15, unit = "°", signal = "signal-D",
    tooltip = "Aim sector center bearing (0° = North, 90° = East, 180° = South, 270° = West)"},
  {key = "arc", caption = "Arc width", min = 15, exact_min = 1, max = 360, exact_max = 360, step = 15, unit = "°", signal = "signal-A",
    tooltip = "Total angular width of the sector around Direction (360° = full circle)"},
  {key = "near", caption = "Near range", min = 0, exact_min = 0, step = 5, unit = "tiles", signal = "signal-N",
    tooltip = "Minimum distance from this targeting computer (artillery minimum range is 32 tiles)"},
  {key = "far", caption = "Far range", min = 5, exact_min = 1, step = 5, unit = "tiles", signal = "signal-F",
    tooltip = "Maximum distance from this targeting computer (scales with artillery range research)"},
}
local INPUTS = {
  {key = "size", caption = "Min size", signal = "signal-S",
    tooltip = "Signal value = smallest size to shoot: 1 Small, 2 Medium, 3 Big, 4 Huge"},
  {key = "off", caption = "Switch off when signal > 0", signal = "signal-deny",
    tooltip = "Disables this targeting computer while the chosen signal is greater than 0"},
}

-- LuaModData.data copies the whole table on every access, so read it once per session
-- (it's prototype data: identical everywhere, safe to keep outside storage).
local CATALOGUE
local function catalogue()
  CATALOGUE = CATALOGUE or prototypes.mod_data["awe-art-asteroids"].data
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

function M.is_computer(e)
  return e and e.valid and (e.name == M.NAME or (e.name == "entity-ghost" and e.ghost_name == M.NAME))
end

local function save_tags(c)
  if c and c.entity and c.entity.valid and c.entity.name == "entity-ghost" then
    local t = c.entity.tags or {}
    t.awe_art_cfg = deepcopy(c.cfg)
    c.entity.tags = t
  end
end

function M.init()
  storage.computers = storage.computers or {} -- unit_number -> {entity, cfg}
  storage.open_computer = storage.open_computer or {} -- player index -> unit_number
  storage.zones = storage.zones or {}
end

function M.add(entity, tags)
  M.init()
  local raw = (tags and tags.awe_art_cfg) or (entity.name == "entity-ghost" and entity.tags and entity.tags.awe_art_cfg)
  local c = {entity = entity, cfg = complete(raw and deepcopy(raw) or default_cfg())}
  storage.computers[entity.unit_number] = c
  save_tags(c)
  if entity.name == M.NAME then
    for p_idx, open_id in pairs(storage.open_computer or {}) do
      local old = storage.computers[open_id]
      if not (old and old.entity.valid) then
        storage.open_computer[p_idx] = entity.unit_number
      end
    end
  end
end

function M.set_cfg(unit_number, cfg)
  M.init()
  local c = storage.computers[unit_number]
  if c then
    c.cfg = complete(cfg)
    save_tags(c)
  end
end

function M.rescan()
  storage.computers = {}
  for _, s in pairs(game.surfaces) do
    for _, e in pairs(s.find_entities_filtered{name = M.NAME}) do M.add(e) end
    for _, e in pairs(s.find_entities_filtered{ghost_name = M.NAME}) do M.add(e) end
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
-- When preview is true (GUI / zone preview for an open ghost), ghosts return their planned rule.
local function effective(c, preview)
  local e, cfg = c.entity, c.cfg
  local ghost = e.name == "entity-ghost"
  if ghost and not preview then return nil end
  if not ghost and (e.status == defines.entity_status.no_power or e.energy <= 0) then return nil end
  local sig = read_signals(e)
  local function get(key)
    local id = cfg.use[key] and cfg.signals[key]
    return id and sig[sig_key(id)]
  end
  if (get("off") or 0) > 0 then return nil end
  local limit = max_distance(e.force)
  local r = {x = e.position.x, y = e.position.y, dir = cfg.dir, arc = cfg.arc, near = cfg.near,
    far = math.min(cfg.far, limit), sizes = cfg.sizes, chunks = chunk_set(cfg.chunks), inputs = {}, ghost = ghost}
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
    r.inputs[#r.inputs + 1] = "min size"
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
M.effective = effective

-- Working rules on a surface, and whether any built computer (working or not) is there.
function M.rules(surface_index)
  local rules, present = {}, false
  for k, c in pairs(storage.computers) do
    if not c.entity.valid then
      storage.computers[k] = nil
    elseif c.entity.surface.index == surface_index and c.entity.name == M.NAME then
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

local function describe(r, wired_count)
  if not r then
    return "[img=utility/status_not_working] [color=1,0.45,0.45]Off (no power or switched off by signal)[/color]"
  end
  local sizes, types = {}, {}
  for _, s in pairs(SIZES) do if r.sizes[s] then sizes[#sizes + 1] = SIZE_LABELS[s] end end
  if r.chunks then
    for name in pairs(r.chunks) do types[#types + 1] = "[asteroid-chunk=" .. name .. "]" end
  else
    types[1] = "all types"
  end
  local badge = r.ghost
    and "[img=utility/status_blue] [color=0.7,0.85,1]Ghost (applies once built):[/color] "
    or "[img=utility/status_working] [font=default-semibold]Active:[/font] "
  local cannons_info = (wired_count and wired_count > 0)
    and string.format(" · [font=default-bold]Wired cannons:[/font] %d", wired_count)
    or " · [color=0.9,0.7,0.4]All unwired platform cannons[/color]"
  local text = string.format("%s%s · %s · %d° ±%d° · %d–%d tiles%s", badge,
    #sizes > 0 and table.concat(sizes, ", ") or "none",
    table.concat(types, " "), r.dir, math.floor(r.arc / 2), r.near, r.far, cannons_info)
  if #r.inputs > 0 then
    text = text .. "  [color=0.6,0.9,0.6](circuit: " .. table.concat(r.inputs, ", ") .. ")[/color]"
  end
  return text
end

local function signal_toggle(parent, key, cfg, caption, tooltip)
  local flow = parent.add{type = "flow", name = "awe_art_tc_sigflow_" .. key, direction = "horizontal"}
  flow.style.vertical_align = "center"
  flow.style.horizontal_spacing = 6
  flow.add{type = "checkbox", name = "awe_art_tc_use_" .. key, state = cfg.use[key] or false, caption = caption,
    tooltip = tooltip or "Override this setting from a circuit network signal"}
  if cfg.signals[key] then
    local b = flow.add{type = "choose-elem-button", name = "awe_art_tc_sig_" .. key, elem_type = "signal",
      signal = cfg.signals[key], tooltip = "Circuit signal to read"}
    b.style.size = 28
  end
  return flow
end

local function get_wired_count(c)
  if not (c and c.entity and c.entity.valid) then return 0 end
  local surface_index = c.entity.surface.index
  local topo = storage.surface_topo and storage.surface_topo[surface_index]
  if topo and topo.comp_to_turrets then
    local list = topo.comp_to_turrets[c.entity.unit_number]
    return list and #list or 0
  end
  return 0
end

local function sync_control_states(f, c)
  if not (f and f.valid and c and c.entity.valid) then return end
  local body = f.inside and f.inside.body
  if not body then return end
  local cfg = c.cfg
  local r = effective(c, true)
  local wired_count = get_wired_count(c)

  if f.inside.subheader and f.inside.subheader.awe_art_tc_now then
    f.inside.subheader.awe_art_tc_now.caption = describe(r, wired_count)
  end

  -- Enable/disable manual size checkboxes when circuit min-size override is active
  local sizes_row = body.sizes_row
  if sizes_row and sizes_row.sizes_left then
    local manual_sizes = not cfg.use.size
    for _, s in pairs(SIZES) do
      local cb = sizes_row.sizes_left["awe_art_tc_size_" .. s]
      if cb then
        cb.enabled = manual_sizes
        cb.state = (not manual_sizes and r) and (r.sizes[s] or false) or (cfg.sizes[s] or false)
      end
    end
  end

  -- Enable/disable manual chunk slots when wire chunk override is active
  local types_row = body.types_row
  if types_row and types_row.types_left then
    local manual_types = not cfg.use.types
    for i = 1, CHUNK_SLOTS do
      local slot = types_row.types_left["awe_art_tc_chunk_" .. i]
      if slot then slot.enabled = manual_types end
    end
  end

  -- Enable/disable sliders & textfields when circuit signal override is active
  local limit = max_distance(c.entity.force)
  local tbl = body.sliders
  if tbl then
    for _, s in pairs(SLIDERS) do
      local max = s.max or limit
      local manual = not cfg.use[s.key]
      local val = (not manual and r) and r[s.key] or cfg[s.key]
      local sl = tbl["awe_art_tc_" .. s.key]
      if sl then
        sl.enabled = manual
        sl.slider_value = clamp(val, s.min, max)
      end
      local tf = tbl["awe_art_tc_txt_" .. s.key]
      if tf then
        tf.enabled = manual
        -- Don't clobber text while the player is actively typing in this field
        if not manual or tf.text == "" or tonumber(tf.text) ~= val then
          tf.text = tostring(val)
        end
      end
    end
  end
end

function M.open(p, entity)
  local c = storage.computers[entity.unit_number]
  if not c then M.add(entity); c = storage.computers[entity.unit_number] end
  if p.gui.screen.awe_art_tc then p.gui.screen.awe_art_tc.destroy() end
  local limit = max_distance(entity.force)

  local f = p.gui.screen.add{type = "frame", name = "awe_art_tc", direction = "vertical"}
  f.auto_center = true

  -- Standard Factorio 2.0 titlebar with draggable space and close [X] button
  local titlebar = f.add{type = "flow", name = "titlebar", direction = "horizontal"}
  titlebar.drag_target = f
  titlebar.style.vertical_align = "center"
  titlebar.add{
    type = "label",
    caption = {"entity-name.awe-art-targeting-computer"},
    style = "frame_title",
    ignored_by_interaction = true,
  }
  local drag = titlebar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.style.minimal_width = 40
  titlebar.add{
    type = "sprite-button",
    name = "awe_art_tc_close",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    tooltip = {"gui.close-instruction"},
  }

  local inside = f.add{type = "frame", name = "inside", style = "inside_shallow_frame", direction = "vertical"}

  -- Status subheader bar at top of frame
  local subheader = inside.add{type = "frame", name = "subheader", style = "subheader_frame", direction = "horizontal"}
  subheader.style.horizontally_stretchable = true
  subheader.style.vertical_align = "center"
  subheader.style.padding = {6, 12, 6, 12}
  local now = subheader.add{type = "label", name = "awe_art_tc_now", caption = describe(effective(c, true), get_wired_count(c))}
  now.style.single_line = false
  now.style.maximal_width = 500

  local body = inside.add{type = "flow", name = "body", direction = "vertical"}
  body.style.padding = 12
  body.style.vertical_spacing = 10

  -- Row 1: Sizes + circuit min-size override
  local sizes_row = body.add{type = "flow", name = "sizes_row", direction = "horizontal"}
  sizes_row.style.vertical_align = "center"
  sizes_row.style.horizontally_stretchable = true
  local sizes_left = sizes_row.add{type = "flow", name = "sizes_left", direction = "horizontal"}
  sizes_left.style.vertical_align = "center"
  sizes_left.style.horizontal_spacing = 10
  local sz_lbl = sizes_left.add{type = "label", caption = "Sizes", style = "bold_label",
    tooltip = "Which asteroid sizes this computer allows artillery to engage"}
  sz_lbl.style.width = 76
  for _, s in pairs(SIZES) do
    sizes_left.add{type = "checkbox", name = "awe_art_tc_size_" .. s, caption = SIZE_LABELS[s], state = c.cfg.sizes[s] or false}
  end
  local sp1 = sizes_row.add{type = "empty-widget"}
  sp1.style.horizontally_stretchable = true
  sp1.style.minimal_width = 16
  signal_toggle(sizes_row, INPUTS[1].key, c.cfg, INPUTS[1].caption, INPUTS[1].tooltip)

  -- Row 2: Types + circuit chunk-signals override
  local types_row = body.add{type = "flow", name = "types_row", direction = "horizontal"}
  types_row.style.vertical_align = "center"
  types_row.style.horizontally_stretchable = true
  local types_left = types_row.add{type = "flow", name = "types_left", direction = "horizontal"}
  types_left.style.vertical_align = "center"
  types_left.style.horizontal_spacing = 4
  local ty_lbl = types_left.add{type = "label", caption = "Types", style = "bold_label",
    tooltip = "Filter by asteroid chunk type. Leave all slots empty to target every asteroid type."}
  ty_lbl.style.width = 82
  for i = 1, CHUNK_SLOTS do
    local b = types_left.add{type = "choose-elem-button", name = "awe_art_tc_chunk_" .. i, elem_type = "asteroid-chunk",
      ["asteroid-chunk"] = c.cfg.chunks[i], tooltip = "Asteroid chunk filter (empty = any type)"}
    b.style.size = 32
  end
  local sp2 = types_row.add{type = "empty-widget"}
  sp2.style.horizontally_stretchable = true
  sp2.style.minimal_width = 16
  signal_toggle(types_row, "types", c.cfg, "From wire chunks",
    "When checked, any asteroid-chunk signal > 0 on the circuit wire replaces the filter slots")

  body.add{type = "line"}

  -- Sector zone table: Label | Slider | Editable Textfield | Unit | Circuit Override
  local tbl = body.add{type = "table", name = "sliders", column_count = 5, vertical_centering = true}
  tbl.style.horizontal_spacing = 8
  tbl.style.vertical_spacing = 6
  for _, s in pairs(SLIDERS) do
    local max = s.max or limit
    local exact_max = s.exact_max or limit
    local val = clamp(c.cfg[s.key], s.exact_min, exact_max)

    local lbl = tbl.add{type = "label", caption = s.caption, style = "bold_label", tooltip = s.tooltip}
    lbl.style.width = 82

    local sl = tbl.add{
      type = "slider",
      name = "awe_art_tc_" .. s.key,
      minimum_value = s.min,
      maximum_value = max,
      value_step = s.step,
      discrete_slider = true,
      value = clamp(val, s.min, max),
      tooltip = s.tooltip,
    }
    sl.style.width = 185

    local tf = tbl.add{
      type = "textfield",
      name = "awe_art_tc_txt_" .. s.key,
      text = tostring(val),
      numeric = true,
      allow_decimal = false,
      allow_negative = false,
      style = "slider_value_textfield",
      tooltip = string.format("Type an exact value (%d–%d %s)", s.exact_min, exact_max, s.unit),
    }
    tf.style.width = 56

    local u = tbl.add{type = "label", caption = s.unit}
    u.style.minimal_width = 32

    signal_toggle(tbl, s.key, c.cfg, "Signal", "Override " .. s.caption:lower() .. " from a circuit network signal")
  end

  body.add{type = "line"}

  -- Bottom row: Circuit switch-off condition
  local off_row = body.add{type = "flow", name = "off_row", direction = "horizontal"}
  off_row.style.vertical_align = "center"
  local off_lbl = off_row.add{type = "label", caption = "Control", style = "bold_label"}
  off_lbl.style.width = 86
  signal_toggle(off_row, INPUTS[2].key, c.cfg, INPUTS[2].caption, INPUTS[2].tooltip)

  sync_control_states(f, c)
  p.opened = f
  storage.open_computer[p.index] = entity.unit_number
  M.sync_zones()
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
    local r = effective(c, player ~= nil)
    if not r then return end
    local key = c.entity.unit_number .. "|" .. (player and player.index or "all")
    want[key] = {c = c, r = r, player = player, sig = zone_sig(r)}
  end
  if storage.debug then
    for _, c in pairs(storage.computers) do if c.entity.valid then wish(c) end end
  end
  for _, p in pairs(game.connected_players) do
    local c = open_entry(p)
    if c and p.gui.screen.awe_art_tc and not storage.debug then wish(c, p) end
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
    local f = p.gui.screen.awe_art_tc
    if c and f then sync_control_states(f, c) end
  end
  M.sync_zones()
end

script.on_event(defines.events.on_gui_opened, function(e)
  if M.is_computer(e.entity) then M.open(game.get_player(e.player_index), e.entity) end
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if e.element and e.element.valid and e.element.name == "awe_art_tc" then
    e.element.destroy()
    if storage.open_computer then storage.open_computer[e.player_index] = nil end
    M.sync_zones()
  end
end)

script.on_event(defines.events.on_gui_click, function(e)
  if e.element and e.element.valid and e.element.name == "awe_art_tc_close" then
    local p = game.get_player(e.player_index)
    if p.gui.screen.awe_art_tc then p.gui.screen.awe_art_tc.destroy() end
    if storage.open_computer then storage.open_computer[e.player_index] = nil end
    M.sync_zones()
  end
end)

local function handle_checked_state_changed(e)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  local name = e.element.name
  if not c or not name:find("^awe_art_tc_") then return end
  local size = name:match("^awe_art_tc_size_(%a+)$")
  local use = name:match("^awe_art_tc_use_(%a+)$")
  if size then c.cfg.sizes[size] = e.element.state end
  if use then c.cfg.use[use] = e.element.state end
  save_tags(c)
  M.refresh_open()
end
M.handle_checked_state_changed = handle_checked_state_changed
script.on_event(defines.events.on_gui_checked_state_changed, handle_checked_state_changed)

script.on_event(defines.events.on_gui_value_changed, function(e)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  if not c then return end
  for _, s in pairs(SLIDERS) do
    if e.element.name == "awe_art_tc_" .. s.key then
      c.cfg[s.key] = math.floor(e.element.slider_value + 0.5)
      local tf = e.element.parent["awe_art_tc_txt_" .. s.key]
      if tf then tf.text = tostring(c.cfg[s.key]) end
    end
  end
  save_tags(c)
  M.refresh_open()
end)

local function on_textfield_edit(e, confirm)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  if not c or not (e.element and e.element.valid) then return end
  local key = e.element.name:match("^awe_art_tc_txt_(%a+)$")
  if not key then return end
  local limit = max_distance(c.entity.force)
  for _, s in pairs(SLIDERS) do
    if s.key == key then
      local num = tonumber(e.element.text)
      local exact_max = s.exact_max or limit
      local slider_max = s.max or limit
      if num then
        local v = clamp(math.floor(num), s.exact_min, exact_max)
        c.cfg[key] = v
        local sl = e.element.parent["awe_art_tc_" .. key]
        if sl then sl.slider_value = clamp(v, s.min, slider_max) end
        if confirm then e.element.text = tostring(v) end
        save_tags(c)
        M.sync_zones()
        local f = p.gui.screen.awe_art_tc
        if f and f.inside and f.inside.subheader and f.inside.subheader.awe_art_tc_now then
          f.inside.subheader.awe_art_tc_now.caption = describe(effective(c, true), get_wired_count(c))
        end
      elseif confirm then
        e.element.text = tostring(c.cfg[key])
      end
      return
    end
  end
end

script.on_event(defines.events.on_gui_text_changed, function(e) on_textfield_edit(e, false) end)
script.on_event(defines.events.on_gui_confirmed, function(e) on_textfield_edit(e, true) end)

script.on_event(defines.events.on_gui_elem_changed, function(e)
  local p = game.get_player(e.player_index)
  local c = open_entry(p)
  if not c then return end
  local key = e.element.name:match("^awe_art_tc_sig_(%a+)$")
  local slot = tonumber(e.element.name:match("^awe_art_tc_chunk_(%d+)$"))
  if key then
    -- keep a signal selected: an input without one can't be switched on
    if e.element.elem_value then c.cfg.signals[key] = e.element.elem_value else e.element.elem_value = c.cfg.signals[key] end
  elseif slot then
    c.cfg.chunks[slot] = e.element.elem_value
  else
    return
  end
  save_tags(c)
  M.refresh_open()
end)

script.on_event(defines.events.on_entity_settings_pasted, function(e)
  if M.is_computer(e.source) and M.is_computer(e.destination) then
    local src = storage.computers[e.source.unit_number]
    if src then M.add(e.destination, {awe_art_cfg = src.cfg}) end
  end
end)

script.on_event(defines.events.on_player_setup_blueprint, function(e)
  -- a library blueprint being reassigned comes as a record, otherwise it's an item stack
  local bp = e.record
  if not (bp and bp.valid_for_write) then
    bp = e.stack
    if not (bp and bp.valid_for_read and bp.is_blueprint) then bp = game.get_player(e.player_index).blueprint_to_setup end
    if not (bp and bp.valid_for_read) then return end
  end
  for index, ent in pairs(e.mapping.get()) do
    local c = M.is_computer(ent) and storage.computers[ent.unit_number]
    if c then bp.set_blueprint_entity_tag(index, "awe_art_cfg", c.cfg) end
  end
end)

return M
