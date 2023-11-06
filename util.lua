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

return M