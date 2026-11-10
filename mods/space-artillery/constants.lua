-- Balance numbers shared by the data and control stages.
return {
  -- Damage per shell by ammo name ("artillery-shell" mirrors the base game's values).
  shells = {
    ["artillery-shell"] = {physical = 1000, explosion = 1000},
    ["space-art-steel-artillery-shell"] = {physical = 200, explosion = 800},
    ["space-art-promethium-artillery-shell"] = {physical = 4000, explosion = 1000},
  },
  rotation_levels = 10,
  rotation_percent = 30, -- turret rotation speed per research level
  velocity_percent = 20, -- shell flight speed per research level
  ballistics_kills = 500, -- artillery kills that complete asteroid ballistics
}
