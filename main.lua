local Map = require 'map'
local FieldBuilder = require 'flow_field_builder'
local FieldData = require 'flow_field_data'
local Flocking = require 'flocking'
_G.Lume = require 'lume'
_G.Cpml = require 'cpml'
_G.Vec2 = Cpml.vec2

local lg = love.graphics
local lp = love.physics
local lm = love.mouse

local Helper = {}

local PI = math.pi
local PI2 = PI * 2


----------------------

local world
local map
local field_data
local field_builder
local mcx, mcy
local goal_cx, goal_cy
local find_time = 0
local entities = {}
local paused = false
local force_run_frames = 0

local MaxNeighborDist = 80


------------------

function love.load()
  world = lp.newWorld()
  map = Map.new(60, 42, world)
  -- map = Map.new(30, 21, world)
  field_builder = FieldBuilder.new(map)
  goal_cx, goal_cy = math.ceil(map.w / 2), math.ceil(map.h / 2)
  Helper.update_field()

  local fe = Helper.new_entity(map:cell_to_screen_coord(map.w * 0.5, map.h * 0.5))
  fe.debug = true
  entities[#entities + 1] = fe
end

function love.update(dt)
  if paused then
    if force_run_frames > 0 then
      force_run_frames = force_run_frames - 1
    else
      return
    end
  end

  local mx, my = lm.getPosition()
  mcx, mcy = map:screen_to_cell_coord(mx, my)
  local changed = false

  for i, e in ipairs(entities) do
    Helper.update_entity(e, dt)
  end

  world:update(dt)


  if lm.isDown(1) then
    if goal_cx ~= mcx or goal_cy ~= mcy then
      goal_cx, goal_cy = mcx, mcy
      changed = true
    end
  end
  if lm.isDown(2) then
    entities[#entities + 1] = Helper.new_entity(mx, my)
  end

  local kbdown = love.keyboard.isDown
  local new_cost = nil
  if kbdown('1') then
    new_cost = 0
  elseif kbdown('2') then
    new_cost = 1
  elseif kbdown('3') then
    new_cost = 2
  elseif kbdown('4') then
    new_cost = -1
  end

  local aw, cw, sw = Flocking.get_weights()
  local wspeed = 3
  if kbdown('u') then
    aw = aw - wspeed * dt
  elseif kbdown('i') then
    aw = aw + wspeed * dt
  elseif kbdown('j') then
    cw = cw - wspeed * dt
  elseif kbdown('k') then
    cw = cw + wspeed * dt
  elseif kbdown('n') then
    sw = sw - wspeed * dt
  elseif kbdown('m') then
    sw = sw + wspeed * dt
  end
  Flocking.set_weights(aw, cw, sw)

  if new_cost then
    local node = map:get_node(mcx, mcy)
    if node.cost ~= new_cost then
      map:update_cost(node, new_cost)
      changed = true
    end
  end

  if changed then
    Helper.update_field()
  end
end

function love.draw()
  lg.setBackgroundColor(0.5, 0.5, 0.55, 1)
  local mx, my = lm.getPosition()

  local cell_w, cell_h = map.cell_w, map.cell_h

  for cx = 0, map.w - 1 do
    for cy = 0, map.h - 1 do
      local x, y = map:cell_to_screen_coord(cx, cy)
      local node = map:get_node(cx, cy)
      local cost = node.cost

      if cost ~= 0 then
        if cost == -1 then
          lg.setColor(0.1, 0.1, 0.1, 1)
        elseif cost == 1 then
          lg.setColor(1, 1, 0.5, 0.5)
        elseif cost == 2 then
          lg.setColor(0.5, 0.5, 0.1, 1)
        end
        lg.rectangle('fill', x, y, cell_w, cell_h)
        lg.setColor(1, 1, 1)
      end

      local info = field_data and field_data:get_info(node.x, node.y)
      if info then
        local cx, cy = x + cell_w / 2, y + cell_h / 2
        local dist = cell_w / 2
        lg.setColor(0.1, 0.1, 0.3, 0.3)
        lg.line(cx, cy, cx + info.vx * dist, cy + info.vy * dist)
        lg.setColor(1, 1, 1)
        lg.circle('fill', cx, cy, 1)
      end
    end
  end



  lg.setColor(1, 1, 1, 0.7)
  for i, e in ipairs(entities) do
    if i > 1 then
      Helper.draw_entity(e)
    end
  end
  lg.setColor(1, 0, 0)
  for i, e in ipairs(entities) do
    if i > 1 then
      Helper.draw_entity_dir(e)
    end
  end

  lg.setColor(1, 1, 0, 0.7)
  local e = entities[1]
  if e then
    Helper.draw_entity(e)
    lg.setColor(1, 0, 0)
    Helper.draw_entity_dir(e)

    local rdata = e.rdata
    if rdata then
      lg.circle('line', rdata.px, rdata.py, rdata.radius)
      lg.circle('line', rdata.tx, rdata.ty, 2)
      lg.line(rdata.tx, rdata.ty, rdata.px, rdata.py)
    end
  end

  lg.setColor(0, 0, 1)
  local gx, gy = map:cell_to_screen_coord(goal_cx + 0.5, goal_cy + 0.5)
  lg.circle('line', gx, gy, cell_h / 1.2)

  lg.setColor(1, 1, 1)
  local str = ''
  str = str..string.format("\n FPS: %i", love.timer.getFPS())

  str = str..'\n'
  local node = map:get_node(mcx, mcy)
  str = str..string.format("\n total entities: %i", #entities)
  str = str..string.format("\n mouse coord: %i, %i", mcx, mcy)
  str = str..string.format("\n mouse node cost: %i", node.cost)

  local finfo = field_data and field_data:get_info(mcx, mcy)
  local score = finfo and finfo.score
  str = str..string.format("\n mouse node field score: %.2f", score or -1)
  local scores = ''
  if finfo then
    for oy = -1, 1 do
      for ox = -1, 1 do
        local info = field_data:get_info(mcx + ox, mcy + oy)
        local s = info and (info.score - score + 2) or math.huge
        scores = scores..string.format(' %.1f ', s)
      end
      scores = scores..'\n'
    end
    str = str..'\n'..scores
  end

  str = str..'\n'
  str = str..string.format("\n map size: %i x %i = %i", map.w, map.h, map.w * map.h)
  str = str..string.format("\n time: %.2fms", find_time)

  local fcx, fcy = map:screen_to_cell_coord(mx, my, false)
  if field_data then
    local vx, vy = field_data:get_smooth_velocity(fcx, fcy)
    str = str..string.format("\n mouse velocity: %.2f,%.2f", vx, vy)

    local len = 15
    local tx, ty = mx + vx * len, my + vy * len
    lg.line(mx, my, tx, ty)
  end

  local aw, cw, sw = Flocking.get_weights()
  str = str..string.format("\n flocking alignment weight: %.1f", aw)
  str = str..string.format("\n flocking cohersion weight: %.1f", cw)
  str = str..string.format("\n flocking separation weight: %.1f", sw)

  if e then
    local fdata = e.flocking
    str = str..string.format("\n entity speed: %.2f/%.2f", e.current_speed, e.desired_speed)
    if fdata then
      str = str..string.format("\n entity flocking av: %.2f,%.2f", fdata.avx, fdata.avy)
      str = str..string.format("\n entity flocking cv: %.2f,%.2f", fdata.cvx, fdata.cvy)
      str = str..string.format("\n entity flocking sv: %.2f,%.2f", fdata.svx, fdata.svy)
      str = str..string.format("\n entity flocking bv: %.2f,%.2f", fdata.bvx, fdata.bvy)
      str = str..string.format(
        "\n entity flocking v: %.2f,%.2f -> %.2f,%.2f", fdata.ovx, fdata.ovy, fdata.rvx, fdata.rvy
      )
    end
  end

  str = str..'\n'
  str = str..string.format("\n left click: set goal, right click: add entity")
  str = str..string.format("\n set cost: 1: 0; 2: 1; 3 2; 4 blocked")
  str = str..string.format("\n flocking weight: u, i, j, k, n, m")
  str = str..string.format("\n space: pause, enter run one frame")
  lg.print(str, 10, 10)
end

function love.keypressed(key)
  if key == 'space' then
    paused = not paused
  elseif key == 'return' then
    force_run_frames = force_run_frames + 1
  elseif key == 'r' then
    local fe = Helper.new_entity(map:cell_to_screen_coord(map.w * 0.5, map.h * 0.5))
    fe.debug = true
    entities = { fe }
  end
end

---------------------

function Helper.draw_entity(e)
  if e.shape:getType() == 'circle' then
    lg.circle('fill', e.x, e.y, e.r)
  else
    local hw, hh = e.h * 0.5, e.w * 0.5
    local ps = {
      -hw, -hh, hw, -hh,
      hw, hh, -hw, hh
    }
    local angle = e.angle
    local c = math.cos(angle)
    local s = math.sin(angle)

    for i = 1, #ps, 2 do
      local j = i + 1
      local x, y = ps[i], ps[j]
      ps[i] = e.x + c * x - s * y
      ps[j] = e.y + s * x + c * y
    end

    lg.polygon('fill', ps)
  end
end

function Helper.draw_entity_dir(e)
  local angle = e.angle
  local ox, oy = Lume.vector(angle, 10)
  lg.line(e.x, e.y, e.x + ox, e.y + oy)
end

function Helper.update_field()
  local st = love.timer.getTime()
  local goal = map:get_node(goal_cx, goal_cy)
  if map:is_valid_node(goal) then
    local raw_data = field_builder:build(goal)
    field_data = FieldData.new(raw_data)
  else
    field_data = nil
  end
  find_time = (love.timer.getTime() - st) * 1000
end

local NextEID = 1
function Helper.new_entity(x, y)
  local w = math.floor(6 + math.random() * 8)
  local h = math.floor(w + math.random() * 10)

  local id = NextEID
  NextEID = NextEID + 1

  local shape = lp.newRectangleShape(h, w)

  local body = lp.newBody(world, x, y, 'dynamic')
  local f = lp.newFixture(body, shape)
  f:setSensor(true)

  -- local speed = 100 + math.random(100)
  local speed = 150

  local e = {
    id = id,
    r = h * 0.5, w = w, h = h,
    x = x, y = y, angle = 0,
    vx = 0, vy = 0,
    pivot_speed = math.pi * 2, -- radian per seconds

    speed = speed,
    max_force = speed * 2,
    current_speed = 0,

    body = body, shape = shape, fixture = f,
  }

  -- sf:setUserData(e)
  -- f:setUserData(e)

  return e
end

function Helper.has_ob(fcx, fcy)
   return not map:is_valid_pos(math.floor(fcx), math.floor(fcy))
end

function Helper.radian_diff(sr, tr)
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
    local sign = (v >= 0) and 1 or -1
    return (v - PI2 * sign)
  else
    return v
  end
end

function Helper.update_entity(e, dt)
  e.x, e.y = e.body:getPosition()
  e.vx, e.vy = e.body:getLinearVelocity()
  -- e.angle = e.
  e.current_speed = Lume.length(e.vx, e.vy)

  if not field_data then
    return
  end

  local fcx, fcy = map:screen_to_cell_coord(e.x, e.y, false)
  local vx, vy
  vx, vy = field_data:get_smooth_velocity(fcx, fcy)
  -- local cx, cy = map:screen_to_cell_coord(e.x, e.y)
  -- local finfo = field_data:get_info(cx, cy)
  -- if finfo then
  --   vx, vy = finfo.vx, finfo.vy
  -- else
  --   vx, vy = 0, 0
  -- end

  local nes = {}
  for i, ne in ipairs(entities) do
    -- local dist = Lume.distance(e.x, e.y, ne.x, ne.y)
    local dist = lp.getDistance(e.fixture, ne.fixture)
    if dist <= MaxNeighborDist then
      nes[#nes + 1] = ne
      nes[ne] = dist
    end
  end

  -- local ecx, ecy = math.floor(fcx), math.floor(fcy)
  local has_ob = Helper.has_ob
  local ov = 0.3
  local obs = {
    l = has_ob(fcx - ov, fcy),
    r = has_ob(fcx + ov, fcy),
    t = has_ob(fcx, fcy - ov),
    b = has_ob(fcx, fcy + ov),

    lt = has_ob(fcx - ov, fcy - ov),
    rt = has_ob(fcx + ov, fcy - ov),
    lb = has_ob(fcx - ov, fcy + ov),
    rb = has_ob(fcx + ov, fcy + ov),
  }

  local gx, gy = map:cell_to_screen_coord(goal_cx + 0.5, goal_cy + 0.5)
  local goal_dist = Lume.distance(e.x, e.y, gx, gy)
  local slow_down_dist = 100
  if goal_dist < slow_down_dist then
    e.desired_speed = goal_dist / slow_down_dist * e.speed
  else
    e.desired_speed = e.speed
  end

  local desired_velocity, block_velocity = Flocking.calc_velcoity(e, vx, vy, nes, obs)
  e.vx, e.vy = e.vx + desired_velocity.x * dt, e.vy + desired_velocity.y * dt

  -- apply block velocity, and don't change speed
  if block_velocity and not block_velocity:is_zero() then
    local olen2 = Lume.length(e.vx, e.vy, true)
    local nx, ny = e.vx + block_velocity.x * dt, e.vy + block_velocity.y * dt
    local len2 = Lume.length(nx, ny, true)
    if len2 > olen2 then
      local len = math.sqrt(len2)
      local olen = math.sqrt(olen2)
      nx, ny = nx * olen / len, ny * olen / len
    end
    e.vx, e.vy = nx, ny
  end

  local new_angle = Lume.angle(0, 0, e.vx, e.vy)
  e.angle = new_angle
  -- local angle_dv = Helper.radian_diff(e.angle, new_angle)

  Helper.control_move(e, desired_velocity, dt)

  e.body:setLinearVelocity(e.vx, e.vy)
  -- local rv = angle_dv / dt
  -- e.body:setAngularVelocity(rv)
end

function Helper.control_move(e, desired_velocity, dt)
  local desired_speed = e.desired_speed
  local len = Lume.length(e.vx, e.vy)
  local ns

  local dv_angle = desired_velocity:angle_to()
  local angle_dv = Helper.radian_diff(e.angle, dv_angle)
  local abs_angle_dv = math.abs(angle_dv)
  local max_speed = e.speed * 3
  if abs_angle_dv > math.rad(165) then
    ns = Helper.slow_down(len, 0, max_speed)
    -- if abs_angle_dv > math.rad(179) then
    --   Helper.trun(e)
    -- end
  elseif abs_angle_dv > math.rad(90) then
    ns = Helper.slow_down(len, 50, max_speed)
  elseif len > desired_speed then
    ns = Helper.slow_down(len, desired_speed, max_speed)
  end

  -- reduce lateral velocity of desired_velocity to make faster turn
  local max_leteral_angle = math.rad(85)
  if abs_angle_dv < max_leteral_angle then
    local pv = 1 - abs_angle_dv / max_leteral_angle
    local sign = (angle_dv > 0) and -1 or 1
    local nrm_angle = dv_angle + math.pi * 0.5 * sign
    local dv_right_nrm = Vec2(Lume.vector(nrm_angle, 1))
    local right_v = Helper.dir_velocity(e.vx, e.vy, dv_right_nrm)
    -- print(math.deg(nrm_angle), dv_right_nrm, right_v)
    e.vx = e.vx - right_v.x * 0.05 * pv
    e.vy = e.vy - right_v.y * 0.05 * pv
  end

  if ns then
    local s = ns / len
    e.vx = e.vx * s
    e.vy = e.vy * s
  end
end

-- 6 7 8
-- 5   1
-- 4 3 2
local AngleIdOffset = {
  { 1, 0 },
  { 1, 1 },
  { 1, 1 },
}

function Helper.trun(e)
  -- if e.angle
  -- e.vx, e.vy = Lume.rotate(e.vx, e.vy, )

  local fcx, fcy = map:screen_to_cell_coord(e.x, e.y, false)
  local pangle = math.pi * 2 / 8
  local angle = math.floor((e.angle + pangle * 0.5) / pangle) * pangle
  local ox, oy = Lume.vector(angle, 1)
  -- print(math.deg(e.angle), math.deg(angle))
  -- local vx, vy = Lume.vector(e.angle, 1)
  -- if math.abs(vx) < 0.2 then
  -- end

  -- l = has_ob(fcx - ov, fcy),
end

-- dir_nrm: normalized vec2
function Helper.dir_velocity(vx, vy, dir_nrm)
  return dir_nrm * dir_nrm:dot(Vec2(vx, vy))
end

function Helper.slow_down(speed, desired, max)
  if speed > max then
    return math.max(desired, speed * 0.7 - 10)
  else
    return math.max(desired, speed * 0.9 - 10)
  end
end
