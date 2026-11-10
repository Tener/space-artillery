-- Mod thumbnail candidates: the showcase ship, with square screenshots every 5 s.
-- Run with tools/factorio-test.sh --client (screenshots need rendering).
require("__awesome-artillery__/scenarios/showcase/control")

script.on_nth_tick(300, function(e)
  local pf = storage.platform
  if not (pf and pf.valid and e.tick >= 600) then return end
  for i, shot in pairs{{{0, -20}, 0.25}, {{0, -55}, 0.5}} do
    game.take_screenshot{surface = pf.surface, position = shot[1], resolution = {1024, 1024}, zoom = shot[2],
      show_entity_info = false, path = string.format("thumb-%05d-%d.png", e.tick, i)}
  end
end)
