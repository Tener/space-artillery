-- Visual check: does a damaged decoy show a health bar? A damaged solar panel next to it
-- is the reference (it must show one). Run with tools/factorio-test.sh --client.
script.on_init(function()
  local force = game.forces.player
  local platform = force.create_space_platform{name = "bars", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
  platform.apply_starter_pack()
  local s = platform.surface
  s.request_to_generate_chunks({0, -20}, 2)
  s.force_generate_chunk_requests()
  local panel = s.create_entity{name = "solar-panel", position = {-3, -12}, force = force}
  panel.health = panel.max_health / 2
  -- decoys sit off the hull, like in play
  for i, name in pairs{"medium-metallic-asteroid", "big-metallic-asteroid"} do
    local d = s.create_entity{name = "aa-decoy-" .. name, position = {i * 5, -12}, force = "enemy"}
    d.health = d.max_health / 2
  end
  storage.s = s
end)

script.on_event(defines.events.on_tick, function(e)
  if e.tick == 60 then
    game.take_screenshot{surface = storage.s, position = {3, -12}, resolution = {1200, 600}, zoom = 2,
      path = "aa-bars.png", show_entity_info = false, hide_health_bars = false}
  end
end)
