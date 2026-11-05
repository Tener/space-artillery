-- Mod thumbnail candidates: the playtest ship, with square screenshots of the artillery at
-- work every 5 s. Run with tools/factorio-test.sh --client (screenshots need rendering).
require("__awesome-artillery__/scenarios/playtest/control")

script.on_nth_tick(300, function(e)
  local pf = storage.platform
  if not (pf and pf.valid and e.tick >= 900) then return end
  for i, zoom in pairs{0.35, 0.6} do
    game.take_screenshot{surface = pf.surface, position = {0, -45}, resolution = {1024, 1024}, zoom = zoom,
      show_entity_info = false, path = string.format("thumb-%05d-%d.png", e.tick, i)}
  end
end)
