local M = {}

local Lume = require 'lume'

local PI = math.pi
-- local HPI = PI * 0.5
local PI2 = PI * 2

local AlignmentWeight = 0.5
local CohesionWeight = 0.2
local SeparationWeight = 2.0
local BlockWeight = 0

local NeighborDist = 100

function M.get_weights()
  return AlignmentWeight, CohesionWeight, SeparationWeight
end

function M.set_weights(aw, cw, sw)
  AlignmentWeight, CohesionWeight, SeparationWeight = aw, cw, sw
end

-- obs: { l = 1, r = 0, t = 1, b = 1 }, valid is 1, invalid is 0
function M.calc_velcoity(e, vx, vy, neighbors, obs)
  if #neighbors <= 0 then
    return vx, vy
  end

  local avx, avy = M._calc_alignment_velocity(e, neighbors)
  local cvx, cvy = M._calc_cohesion_velocity(e, neighbors)
  local svx, svy = M._calc_separation_velocity(e, neighbors)
  local bvx, bvy = M._calc_block_velocity(e, obs)

  local aw = AlignmentWeight
  local cw = CohesionWeight
  local sw = SeparationWeight
  local bw = BlockWeight

  local rvx = vx + avx * aw + cvx * cw + svx * sw + bvx * bw
  local rvy = vy + avy * aw + cvy * cw + svy * sw + bvy * bw

  -- local rvx, rvy = M._normalize(
  --   vx + avx * AlignmentWeight + cvx * CohesionWeight + svx * SeparationWeight,
  --   vy + avy * AlignmentWeight + cvy * CohesionWeight + svy * SeparationWeight
  -- )

  -- local angle_diff, should_reverse
  -- local pivot_speed = e.pivot_speed or PI * 0.1
  -- rvx, rvy, angle_diff, should_reverse = M._smooth_move_dir(e.angle, pivot_speed, rvx, rvy)
  -- local angular = angle_diff

  if e.debug then
    e.flocking = {
      avx = avx, avy = avy,
      cvx = cvx, cvy = cvy,
      svx = svx, svy = svy,
      bvx = bvx, bvy = bvy,

      ovx = vx, ovy = vy,
      rvx = rvx, rvy = rvy,
    }
  end


  return Lume.normalize(rvx, rvy)
end

function M._calc_alignment_velocity(e, neighbors)
  local vx, vy = 0, 0
  local n = 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= NeighborDist then
      n = n + 1
      vx = vx + ne.vx
      vy = vy + ne.vy
    end
  end
  if n == 0 then
    return 0, 0
  end

  return Lume.normalize(vx / n, vy / n)
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

  return Lume.normalize(cx - e.x, cy - e.y)
end

function M._calc_separation_velocity(e, neighbors)
  local vx, vy = 0, 0
  local total = 0
  -- local max_dist = NeighborDist
  local max_dist = math.min(e.r * 3)

  for i, ne in ipairs(neighbors) do
    if ne ~= e then
      local dist = neighbors[ne]
      if dist <= max_dist then
        total = total + 1
        local pv = ((1 - dist / max_dist) * 3)^2
        vx = vx + (e.x - ne.x) * pv
        vy = vy + (e.y - ne.y) * pv
      end
    end
  end

  if total == 0 then
    return 0, 0
  end
  -- if e.debug then
  --   print('---')
  -- end

  local s = e.r
  return vx / total / s, vy / total / s
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

  return Lume.normalize(vx, vy)
end


return M
