local M = {}

local Lume = require 'lume'

local PI = math.pi
local HPI = PI * 0.5
local PI2 = PI * 2

local AlignmentWeight = 1
local CohesionWeight = 0.7
local SeparationWeight = 3.0

local MaxAlignDist = 50
local MaxCohesionDist = 100
-- local MaxSeparationDist = 100

-- local AlignmentForce = 20
-- local CohesionForce = 20
-- local SeparationForce = 50

function M.get_weights()
  return AlignmentWeight, CohesionWeight, SeparationWeight
end

function M.set_weights(aw, cw, sw)
  AlignmentWeight, CohesionWeight, SeparationWeight = aw, cw, sw
end

-- obs: { l = 1, r = 0, t = 1, b = 1 }, valid is 1, invalid is 0
function M.calc_velcoity(e, vx, vy, speed, neighbors, obs)
  if #neighbors <= 0 then
    return vx * speed, vy * speed
  end

  local avx, avy = M._calc_alignment_velocity(e, neighbors)
  avx, avy = M._update_velocity_by_obs(avx, avy, obs)

  local cvx, cvy = M._calc_cohesion_velocity(e, neighbors)
  cvx, cvy = M._update_velocity_by_obs(cvx, cvy, obs)

  local svx, svy = M._calc_separation_velocity(e, neighbors)
  svx, svy = M._update_velocity_by_obs(svx, svy, obs)

  -- local ef = speed
  -- local awv = speed * 0.5 * AlignmentWeight
  -- local cwv = speed * 0.5 * CohesionWeight
  -- local swv = speed * 1 * SeparationWeight
  -- vx, vy = vx * speed, vy * speed
  -- avx, avy = avx * awv, avy * awv
  -- cvx, cvy = cvx * cwv, cvy * cwv
  -- svx, svy = svx * swv, svy * swv
  -- local rvx, rvy = M._normalize(
  --   vx + avx + cvx + svx,
  --   vy + avy + cvy + svy,
  --   speed
  -- )

  local rvx, rvy = M._normalize(
    vx + avx * AlignmentWeight + cvx * CohesionWeight + svx * SeparationWeight,
    vy + avy * AlignmentWeight + cvy * CohesionWeight + svy * SeparationWeight
  )

  local angle_diff, should_reverse
  local pivot_speed = e.pivot_speed or PI * 0.1
  rvx, rvy, angle_diff, should_reverse = M._smooth_move_dir(e.angle, pivot_speed, rvx, rvy)

  if e.debug then
    e.flocking = {
      avx = avx, avy = avy,
      cvx = cvx, cvy = cvy,
      svx = svx, svy = svy,

      ovx = vx, ovy = vy,
      rvx = rvx, rvy = rvy,
    }
  end

  local angular = angle_diff

  return rvx * speed, rvy * speed, angular, should_reverse
end

function M._calc_alignment_velocity(e, neighbors)
  local vx, vy = 0, 0
  local n = 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= MaxAlignDist then
      n = n + 1
      vx, vy = vx + ne.vx, vy + ne.vy
    end
  end
  if n == 0 then
    return vx, vy
  end

  return M._normalize(vx / n, vy / n)
end

function M._calc_cohesion_velocity(e, neighbors)
  local cx, cy = 0, 0
  local n = 0
  for i, ne in ipairs(neighbors) do
    local dist = neighbors[ne]
    if dist <= MaxCohesionDist then
      n = n + 1
      cx, cy = cx + ne.x, cy + ne.y
    end
  end
  if n == 0 then
    return 0, 0
  end
  cx, cy = cx / n, cy / n
  local dist = Lume.distance(e.x, e.y, cx, cy)
  local pv = dist / MaxCohesionDist

  return M._normalize(cx - e.x, cy - e.y, pv)
end

function M._calc_separation_velocity(e, neighbors)
  local vx, vy = 0, 0
  local fv = 0
  local max_dist = e.r * 3
  for i, ne in ipairs(neighbors) do
    if ne ~= e then
      local dist = neighbors[ne]
      if dist <= max_dist then
        local nfv = 1 - (dist / max_dist)^2
        fv = fv + nfv
        vx = vx + (e.x - ne.x) * nfv
        vy = vy + (e.y - ne.y) * nfv
      end
    end
  end

  return M._normalize(vx, vy, fv)
end

function M._normalize(vx, vy, s)
  if vx == 0 and vy == 0 then
    return 0, 0
  end
  if not s then
    s = 1
  end
  local len = math.sqrt(vx * vx + vy * vy)
  return vx / len * s, vy / len * s
end

function M._radian_diff(sr, tr)
  if sr == tr then return 0 end

  if sr >= PI2 then
    sr = sr % PI2
  elseif sr <= -PI2 then
    sr = sr % -PI2
  end
  if tr >= PI2 then
    tr = tr % PI2
  elseif tr <= -PI2 then
    tr = tr % -PI2
  end

  local v = tr - sr

  if math.abs(v) > PI then
    return (v - PI2 * Lume.sign(v))
  else
    return v
  end
end

-- return vector, target_angle_diff, should_reverse
function M._smooth_move_dir(current_angle, pivot_speed, vx, vy)
  local vangle = Lume.angle(0, 0, vx, vy)
  local angle_diff = M._radian_diff(current_angle, vangle)
  local abs_angle_diff = math.abs(angle_diff)
  if abs_angle_diff <= pivot_speed then
    return vx, vy, angle_diff, false
  end

  local sign = angle_diff >= 0 and 1 or -1
  -- reverse
  local rangle_diff = PI - abs_angle_diff
  if rangle_diff <= pivot_speed then
    local new_angle_diff = rangle_diff * -sign
    return vx, vy, new_angle_diff, true
  end

  -- if abs_angle_diff < HPI then
    vx, vy = Lume.vector(current_angle + pivot_speed * sign, 1)
    return vx, vy, pivot_speed * sign, false
  -- else
  --   vx, vy = Lume.vector(current_angle + PI + pivot_speed * -sign, 1)
  --   return vx, vy, pivot_speed * -sign, true
  -- end
end

function M._update_velocity_by_obs(vx, vy, obs)
  vx = vx * ((vx < 0) and obs.l or obs.r)
  vy = vy * ((vy < 0) and obs.t or obs.b)
  return vx, vy
end

return M
