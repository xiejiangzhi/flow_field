local M = {}

local PI = math.pi
-- local HPI = PI * 0.5
local PI2 = PI * 2

local AlignmentWeight = 0.6
local CohesionWeight = 0.5
local SeparationWeight = 1.5
local OverlapSeparationWeight = 20.0
local BlockWeight = 20

local NeighborDist = 50

function M.get_weights()
  return AlignmentWeight, CohesionWeight, SeparationWeight
end

function M.set_weights(aw, cw, sw)
  AlignmentWeight, CohesionWeight, SeparationWeight = aw, cw, sw
end

-- obs: { l = 1, r = 0, t = 1, b = 1 }, valid is 1, invalid is 0
function M.calc_velcoity(e, vx, vy, neighbors, obs)
  if #neighbors <= 0 then
    return Vec2(vx, vy)
  end

  local av = M._calc_alignment_velocity(e, neighbors)
  local cv = M._calc_cohesion_velocity(e, neighbors)
  local sv = M._calc_separation_velocity(e, neighbors)
  local bv = M._calc_block_velocity(e, obs)

  local aw = AlignmentWeight
  local cw = CohesionWeight
  local sw = SeparationWeight
  local bw = BlockWeight

  local ds = e.speed
  local fv = Vec2(M.follow_force(e, vx * ds, vy * ds))

  local rv = fv + av * aw + cv * cw + sv * sw
  if bv and not bv:is_zero() then
    bv = (Vec2(vx, vy) * ds + bv) * bw
  end

  if e.debug then
    e.flocking = {
      avx = av.x, avy = av.y,
      cvx = cv.x, cvy = cv.y,
      svx = sv.x, svy = sv.y,
      bvx = bv.x, bvy = bv.y,

      ovx = vx, ovy = vy,
      rvx = rv.x, rvy = rv.y,
    }
  end

  return rv, bv
end

function M.limit_force(vx, vy, max_force)
  local len = Lume.length(vx, vy)
  if len > max_force then
    return vx * max_force / len, vy * max_force / len
  else
    return vx, vy
  end
end

function M.follow_force(e, vx, vy)
  local dx, dy = vx - e.vx, vy - e.vy
  return M.limit_force(dx, dy, e.max_force)
end

function M.seek_pos(e, x, y, speed)
  local vx, vy = Lume.normalize(x - e.x, y - e.y, speed or e.speed)
  return M.follow_force(e, vx, vy)
end

function M.scale_force_to(vx, vy, new_len)
  local len = Lume.length(vx, vy)
  if len > 0 then
    local s = new_len / len
    vx = vx * s
    vy = vy * s
  end
  return vx, vy
end

---------------


-- TODO try to calc entities that are in sight
function M._calc_alignment_velocity(e, neighbors)
  local v = Vec2(0)
  local n = 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= NeighborDist then
      n = n + 1
      v.x = v.x + ne.vx
      v.y = v.y + ne.vy
    end
  end
  if n == 0 then
    return v
  else
    v = v / n
  end

  v = Vec2(M.scale_force_to(v.x, v.y, e.speed))
  return Vec2(M.follow_force(e, v.x, v.y))
end

function M._calc_cohesion_velocity(e, neighbors)
  local cx, cy = 0, 0
  local n = 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= NeighborDist then
      n = n + 1
      cx, cy = cx + ne.x, cy + ne.y
    end
  end
  if n == 0 then
    return 0, 0
  end
  cx, cy = cx / n, cy / n

  local dv = Vec2(cx - e.x, cy - e.y)
  -- local dist = dv:len()
  dv = dv:normalize() * e.speed
  return Vec2(M.follow_force(e, dv.x, dv.y))
end

function M._calc_separation_velocity(e, neighbors)
  local v = Vec2(0)
  local total = 0
  local max_dist = math.min(e.r * 2)
  -- local fov = 0, 0

  for i, ne in ipairs(neighbors) do
    if ne ~= e then
      local dist = neighbors[ne]
      if dist <= max_dist then
        total = total + 1
        local dv = Vec2(e.x - ne.x, e.y - ne.y):normalize()
        if dist > 0 then
          dv = dv / dist
        end
        v = v + dv
      end
    end
  end

  if total == 0 then
    return v
  end

  v = v:normalize() * e.speed
  return Vec2(M.follow_force(e, v.x, v.y))
end

function M._calc_block_velocity(e, obs)
  local vx, vy = 0, 0
  if obs.l then vx = vx + 1 end
  if obs.r then vx = vx - 1 end
  if obs.t then vy = vy + 1 end
  if obs.b then vy = vy - 1 end

  if obs.lt then vx, vy = vx + 1, vy + 1 end
  if obs.rt then vx, vy = vx - 1, vy + 1 end
  if obs.lb then vx, vy = vx + 1, vy - 1 end
  if obs.rb then vx, vy = vx - 1, vy - 1 end

  return Vec2(vx, vy):normalize() * e.speed
end


return M
