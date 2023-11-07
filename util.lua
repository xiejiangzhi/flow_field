local M = {}

function M.limit_force(vx, vy, max_force)
  local len = Lume.length(vx, vy)
  if len > max_force then
    return vx * max_force / len, vy * max_force / len
  else
    return vx, vy
  end
end

function M.follow_force(e, vx, vy, max_force)
  local dx, dy = vx - e.vx, vy - e.vy
  return M.limit_force(dx, dy, max_force or e.speed)
end

function M.seek_pos(e, x, y, speed)
  local vx, vy = Lume.normalize(x - e.x, y - e.y, speed or e.speed)
  return M.follow_force(e, vx, vy)
end

function M.has_ob(map, fcx, fcy)
  return not map:is_valid_pos(math.floor(fcx), math.floor(fcy))
end

function M.calc_block_velocity(map, fcx, fcy, ov)
  local vx, vy = 0, 0
  local l = M.has_ob(map, fcx - ov, fcy)
  local r = M.has_ob(map, fcx + ov, fcy)
  local t = M.has_ob(map, fcx, fcy - ov)
  local b = M.has_ob(map, fcx, fcy + ov)

  local lt = M.has_ob(map, fcx - ov, fcy - ov)
  local rt = M.has_ob(map, fcx + ov, fcy - ov)
  local lb = M.has_ob(map, fcx - ov, fcy + ov)
  local rb = M.has_ob(map, fcx + ov, fcy + ov)

  if l then vx = vx + 1 end
  if r then vx = vx - 1 end
  if t then vy = vy + 1 end
  if b then vy = vy - 1 end

  if lt then vx, vy = vx + 1, vy + 1 end
  if rt then vx, vy = vx - 1, vy + 1 end
  if lb then vx, vy = vx + 1, vy - 1 end
  if rb then vx, vy = vx - 1, vy - 1 end

  local len = Lume.length(vx, vy)
  if len > 0 then
    return vx / len, vy / len
  else
    return 0, 0
  end
end

return M