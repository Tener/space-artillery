-- Bearings in degrees: 0 = north, clockwise (90 = east).

local M = {}

-- Bearing of the offset (dx, dy).
function M.bearing(dx, dy)
  return math.deg(math.atan2(dx, -dy)) % 360
end

-- Smallest angle between two bearings, 0..180.
function M.angle_diff(deg1, deg2)
  return math.abs((deg1 - deg2 + 540) % 360 - 180)
end

return M
