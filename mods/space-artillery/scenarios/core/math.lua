local ballistics = require("__space-artillery__/scripts/ballistics")

local function close(actual, expected, label)
  assert(actual and math.abs(actual - expected) < 1e-7,
    string.format("%s: expected %.8f, got %s", label, expected, tostring(actual)))
end

return function()
  local ctx = {cx = 0, cy = 0, shell_speed = 1, half_interval = 0, reach_min = 0, reach_max = 300}
  local cases = {
    {"stationary", 0, -100, 0, 0, 0, -100},
    {"approaching", 0, -100, 0, 0.2, 0, -100 / 1.2},
    {"crossing", 0, -80, 0.6, 0, 60, -80},
    {"receding", 0, -80, 0, -0.6, 0, -200},
    {"unreachable", 0, -80, 0, -2},
    {"equal speed approaching", 0, -100, 0, 1, 0, -50},
    {"equal speed receding", 0, -100, 0, -1},
    {"faster approaching", 0, -100, 0, 2, 0, -100 / 3},
    {"faster crossing", 0, -80, 2, 0},
    {"maximum range", 0, -300, 0, 0, 0, -300},
    {"beyond range", 0, -301, 0, 0},
  }
  for _, c in ipairs(cases) do
    local x, y = ballistics.intercept(c[2], c[3], c[4], c[5], ctx)
    if c[6] then close(x, c[6], c[1] .. " x"); close(y, c[7], c[1] .. " y")
    else assert(x == nil and y == nil, c[1] .. ": expected no intercept") end
  end
  ctx.reach_min = 32
  assert(ballistics.intercept(0, -31, 0, 0, ctx) == nil, "inside minimum range")
  close(select(2, ballistics.intercept(0, -32, 0, 0, ctx)), -32, "minimum range")
  ctx.half_interval = 10
  close(select(2, ballistics.intercept(0, -100, 0, 0.2, ctx)), -98 / 1.2, "scan delay")
  ctx.half_interval, ctx.shell_speed = 0, 2
  close(select(2, ballistics.intercept(0, -100, 0, 0.2, ctx)), -100 / 1.1, "faster shell")
  ctx.cx, ctx.cy = 20, 30
  close(select(2, ballistics.intercept(20, -70, 0, 0.2, ctx)), 30 - 100 / 1.1, "translated origin")

  close(ballistics.damage({physical = 1000, explosion = 800}, {}, 1), 1800, "unarmored damage")
  local resist = {physical = {decrease = 300, percent = 0.5}, explosion = {decrease = 0, percent = 0.9}}
  close(ballistics.damage({physical = 1000, explosion = 800}, resist, 1), 430, "resisted damage")
  close(ballistics.damage({physical = 1000, explosion = 800}, resist, 2), 1010, "research before armor")
  close(ballistics.damage({physical = 200}, {physical = {decrease = 3000, percent = 0}}, 1), 0, "armor gate")
  print("[CORE] interception and damage math: passed")
end
