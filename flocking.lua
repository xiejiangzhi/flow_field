local M = {}

local Util = require 'util'

-- local PI = math.pi
-- local HPI = PI * 0.5
-- local PI2 = PI * 2

local AlignmentWeight = 0.3
local AlignmentOtherWeight = 0.2
local CohesionWeight = 0.1
local SeparationWeight = 0.6
local BlockWeight = 100

function M.get_weights()
  return AlignmentWeight, CohesionWeight, SeparationWeight
end

function M.set_weights(aw, cw, sw)
  AlignmentWeight, CohesionWeight, SeparationWeight = aw, cw, sw
end

-- obs: { l = 1, r = 0, t = 1, b = 1 }, valid is 1, invalid is 0
function M.calc_velcoity(e, vx, vy, neighbors, obs)
  if not neighbors or #neighbors <= 0 then
    if e.move_done then
      return 0, 0
    else
      return vx * e.speed, vy * e.speed
    end
  end

  local av, av2 = M._calc_alignment_velocity(e, neighbors)
  local cv = Vec2(M._calc_cohesion_velocity(e, neighbors)) * e.speed
  local sv = M._calc_separation_velocity(e, neighbors) * e.speed
  local bv = Vec2(M._calc_block_velocity(obs)) * e.speed

  local mv = Vec2(vx, vy) * e.speed

  local evx, evy = e.vx, e.vy

  if e.move_done then
    mv = Vec2.zero
    av = Vec2.zero
    av2 = Vec2.zero
    cv = Vec2.zero
    evx, evy = evx * 0.9, evy * 0.9
  end

  av = av * AlignmentWeight
  av2 = av2 * AlignmentOtherWeight
  cv = cv * CohesionWeight
  sv = sv * SeparationWeight
  bv = bv * BlockWeight

  local rv = mv + av + av2 + cv + sv
  -- sv + bv

  local rvx, rvy = Util.limit_force(evx + rv.x, evy + rv.y, e.speed)
  rvx, rvy = Util.limit_force(rvx + bv.x, rvy + bv.y, e.speed)

  if e.debug then
    e.flocking = {
      avx = av.x, avy = av.y,
      cvx = cv.x, cvy = cv.y,
      svx = sv.x, svy = sv.y,
      bvx = bv.x, bvy = bv.y,

      ovx = mv.x, ovy = mv.y,
      rvx = rvx, rvy = rvy,
    }
  end

  return rvx, rvy
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
  local ndist = e.r * 4
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= ndist then
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
    -- v = M.scale_force_to(v, e.speed)
    vx1, vy1 = v.x, v.y
  end
  if n2 > 0 then
    v2 = v2 / n2
    -- v2 = M.scale_force_to(v2, e.speed)
    vx2, vy2 = v2.x, v2.y
  end

  return Vec2(vx1, vy1), Vec2(vx2, vy2)
end

function M._calc_cohesion_velocity(e, neighbors)
  local cx, cy = 0, 0
  local n = 0
  local ndist = e.r * 4
  for i, ne in ipairs(neighbors) do
    if ne.group_id == e.group_id and neighbors[ne] <= ndist then
      n = n + 1
      cx, cy = cx + ne.x, cy + ne.y
    end
  end
  if n == 0 then
    return 0, 0
  end
  n = n + 1
  cx, cy = cx + e.x, cy + e.y
  cx, cy = cx / n, cy / n

  local dx, dy = cx - e.x, cy - e.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 0 then
    return dx / len, dy / len
  else
    return 0, 0
  end
end

function M._calc_separation_velocity(e, neighbors)
  local vx, vy = 0, 0
  local n = 0
  local max_dist = e.r * 4
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist < max_dist then
      local dx, dy = e.x - ne.x, e.y - ne.y
      local s = ((max_dist - dist) / (e.r / 2))^2
      if dx == 0 and dy == 0 then
        dx, dy = Lume.vector(e.angle + math.rad(e.id), max_dist * 8)
      else
        dx, dy = dx * s, dy * s
      end
      vx = vx + dx
      vy = vy + dy
      n = n + 1
    end
  end
  if n > 0 then
    vx, vy = vx / n, vy / n
  end
  -- if zero_vn > 0 then
  --   print(zero_vn)
  --   if vx ~= 0 or vy ~= 0 then
  --     local len = Lume.length(vx, vy)
  --     vx = vx + vx / len * zero_vn
  --     vy = vy + vy / len * zero_vn
  --   else
  --     local dx, dy = Lume.vector(e.angle + math.rad(e.id), 1)
  --     vx, vy = vx + dx * zero_vn, vy + dy * zero_vn
  --   end
  -- end
  return Vec2(vx, vy):normalize()
end

function M._calc_block_velocity(obs)
  local vx, vy = 0, 0
  if obs.l then vx = vx + 1 end
  if obs.r then vx = vx - 1 end
  if obs.t then vy = vy + 1 end
  if obs.b then vy = vy - 1 end

  if obs.lt then vx, vy = vx + 1, vy + 1 end
  if obs.rt then vx, vy = vx - 1, vy + 1 end
  if obs.lb then vx, vy = vx + 1, vy - 1 end
  if obs.rb then vx, vy = vx - 1, vy - 1 end

  local len2 = vx * vx + vy * vy
  if len2 > 0 then
    local l = math.sqrt(len2)
    return vx / l, vy / l
  else
    return 0, 0
  end
end

return M
