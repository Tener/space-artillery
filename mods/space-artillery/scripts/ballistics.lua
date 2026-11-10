local M = {}

function M.damage(amounts, resistances, multiplier)
  local total = 0
  for kind, amount in pairs(amounts) do
    local r = resistances[kind] or {decrease = 0, percent = 0}
    local d = amount * multiplier - r.decrease
    if d > 0 then total = total + d * (1 - r.percent) end
  end
  return total
end

function M.intercept(px, py, vx, vy, ctx)
  px, py = px + vx * ctx.half_interval, py + vy * ctx.half_interval
  local rx, ry = px - ctx.cx, py - ctx.cy
  local s = ctx.shell_speed
  local a = vx * vx + vy * vy - s * s
  local b = 2 * (rx * vx + ry * vy)
  local c = rx * rx + ry * ry
  local t
  if a == 0 then
    if b >= 0 then return nil end
    t = -c / b
  else
    local disc = b * b - 4 * a * c
    if disc < 0 then return nil end
    local root = math.sqrt(disc)
    local first, last = (-b - root) / (2 * a), (-b + root) / (2 * a)
    if first >= 0 and (last < 0 or first <= last) then t = first
    elseif last >= 0 then t = last
    else return nil end
  end
  local d = s * t
  if d < ctx.reach_min or d > ctx.reach_max then return nil end
  return px + vx * t, py + vy * t
end

return M
