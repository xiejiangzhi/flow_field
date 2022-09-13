local M = {}

local M = {}
M.__index = M

function M.new(...)
  local obj = setmetatable({}, M)
  obj:init(...)
  return obj
end

-- raw_data: { x = { y = node } }
function M:init(raw_data)
  self.raw_data = raw_data
  self.gcx, self.gcy = raw_data.goal_x, raw_data.goal_y
end

function M:get_info(cx, cy)
  local col = self.raw_data[cx]
  return col and col[cy]
end

function M:get_smooth_velocity(fcx, fcy)
  local ecx, ecy = math.floor(fcx), math.floor(fcy)

  if ecx == self.gcx and ecy == self.gcy then
    local vx, vy = self.gcx + 0.5 - fcx, self.gcy + 0.5 - fcy
    local len = math.sqrt(vx * vx + vy * vy)
    return vx / len, vy / len
  end

  local dx, dy = fcx - ecx - 0.5, fcy - ecy - 0.5
  dx = (dx < 0) and -1 or 1
  dy = (dy < 0) and -1 or 1

  local tx, ty = ecx + dx, ecy + dy

  local q11, q12, q21, q22 =
    self:get_info(ecx, ecy),
    self:get_info(ecx, ty),
    self:get_info(tx, ecy),
    self:get_info(tx, ty)

  if not q11 then return 0, 0 end
  if not q12 then q12 = { vx = 0, vy = -dy } end
  if not q21 then q21 = { vx = -dx, vy = 0 } end
  if not q22 then
    local len = 1.4142135624
    q22 = { vx = -dx / len, vy = -dy / len }
  end
  -- if not(q12 and q21 and q22) then return q11.vx, q11.vy end
  return M._bilinear_interpolation(fcx, fcy, ecx + 0.5, ecy + 0.5, tx + 0.5, ty + 0.5, q11, q12, q21, q22)
end

---------------------

function M._bilinear_interpolation(x, y, x1, y1, x2, y2, q11, q12, q21, q22)
  local r = {} local tx1, tx2 = (x2 - x) / (x2 - x1), (x - x1) / (x2 - x1)
  local ty1, ty2 = (y2 - y) / (y2 - y1), (y - y1) / (y2 - y1)

  for i, k in ipairs({ 'vx', 'vy' }) do
    local r1 = tx1 * q11[k] + tx2 * q21[k]
    local r2 = tx1 * q12[k] + tx2 * q22[k]
    r[i] = ty1 * r1 + ty2 * r2
  end

  return unpack(r)
end

return M