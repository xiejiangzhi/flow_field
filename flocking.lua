local M = {}

local PI = math.pi
-- local HPI = PI * 0.5
local PI2 = PI * 2

local AlignmentWeight = 0.5
local AlignmentOtherWeight = 0.2
local CohesionWeight = 0.2
local SeparationWeight = 2.0
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

  local av, av2 = M._calc_alignment_velocity(e, neighbors)
  local cv = M._calc_cohesion_velocity(e, neighbors)
  local sv = M._calc_separation_velocity(e, neighbors)
  local bv = M._calc_block_velocity(e, obs)

  local mv = Vec2(vx, vy) * e.speed
  local fv = Vec2(M.follow_force(e, mv.x, mv.y))

  local rv = fv
    + av * AlignmentWeight
    + av2 * AlignmentOtherWeight
    + cv * CohesionWeight
    + sv * SeparationWeight
  if bv and not bv:is_zero() then
    bv = (mv + bv) * BlockWeight
  end

  if e.debug then
    e.flocking = {
      avx = av.x, avy = av.y,
      cvx = cv.x, cvy = cv.y,
      svx = sv.x, svy = sv.y,
      bvx = bv.x, bvy = bv.y,

      ovx = mv.x, ovy = mv.y,
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

function M.follow_force(e, vx, vy, max_force)
  local dx, dy = vx - e.vx, vy - e.vy
  return M.limit_force(dx, dy, max_force or e.max_force)
end

function M.seek_pos(e, x, y, speed)
  local vx, vy = Lume.normalize(x - e.x, y - e.y, speed or e.speed)
  return M.follow_force(e, vx, vy)
end

function M.scale_force_to(v, new_len)
  local len = v:len()
  if len > 0 then
    v = v * new_len / len
  end
  return v
end

---------------


-- TODO try to calc entities that are in sight
function M._calc_alignment_velocity(e, neighbors)
  local v = Vec2(0)
  local v2 = Vec2(0)
  local n, n2 = 0, 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= NeighborDist then
      local dnrm = Vec2(ne.x - e.x, ne.y - e.y):normalize()
      local fnrm = Vec2(Lume.vector(e.angle, 1))
      local dr = fnrm:dot(dnrm)
      if dr >= 0.3 then
        if ne.group_id == e.group_id then
          n = n + 1
          v.x = v.x + ne.vx
          v.y = v.y + ne.vy
        else
          n2 = n2 + 1
          v2.x = v2.x + ne.vx
          v2.y = v2.y + ne.vy
        end
      end
    end
  end

  local vx1, vy1, vx2, vy2 = 0, 0, 0, 0
  if n > 0 then
    v = v / n
    v = M.scale_force_to(v, e.speed)
    vx1, vy1 = M.follow_force(e, v.x, v.y)
  end
  if n2 > 0 then
    v2 = v2 / n2
    v2 = M.scale_force_to(v2, e.speed)
    vx2, vy2 = M.follow_force(e, v2.x, v2.y, e.max_force * 0.5)
  end

  return Vec2(vx1, vy1), Vec2(vx2, vy2)
end

function M._calc_cohesion_velocity(e, neighbors)
  local cx, cy = 0, 0
  local n = 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= NeighborDist and ne.group_id == e.group_id then
      n = n + 1
      cx, cy = cx + ne.x, cy + ne.y
    end
  end
  if n == 0 then
    return 0, 0
  end
  cx, cy = cx / n, cy / n

  local dv = Vec2(cx - e.x, cy - e.y)
  local dist = dv:len2()
  local min_dist = 10^2
  dv = dv:normalize() * (e.speed * dist / NeighborDist)
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
        local s = (ne.group_id == e.group_id) and 1 or 1.2
        v = v + dv * s
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
