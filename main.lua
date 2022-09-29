local Map = require 'map'
local FieldBuilder = require 'flow_field_builder'
local FieldData = require 'flow_field_data'
local Flocking = require 'flocking'
local Lume = require 'lume'

local lg = love.graphics

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
  world = love.physics.newWorld()
  map = Map.new(60, 42, world)
  field_builder = FieldBuilder.new(map)
  goal_cx, goal_cy = math.ceil(map.w / 2), math.ceil(map.h / 2)
  Helper.update_field()

  local fe = Helper.new_entity(math.random(map.w), math.random(map.h))
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

  local mx, my = love.mouse.getPosition()
  mcx, mcy = map:screen_to_cell_coord(mx, my)
  local changed = false

  for i, e in ipairs(entities) do
    Helper.update_entity(e, dt)
  end

  world:update(dt)


  if love.mouse.isDown(1) then
    if love.keyboard.isDown('lctrl') then
      entities[#entities + 1] = Helper.new_entity(mx, my)
    elseif goal_cx ~= mcx and goal_cy ~= mcy then
      goal_cx, goal_cy = mcx, mcy
      changed = true
    end
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
  local mx, my = love.mouse.getPosition()

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

  local finfo = field_data:get_info(mcx, mcy)
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
    str = str..string.format("\n entity flocking av: %.2f,%.2f", fdata.avx, fdata.avy)
    str = str..string.format("\n entity flocking cv: %.2f,%.2f", fdata.cvx, fdata.cvy)
    str = str..string.format("\n entity flocking sv: %.2f,%.2f", fdata.svx, fdata.svy)
    str = str..string.format("\n entity flocking bv: %.2f,%.2f", fdata.bvx, fdata.bvy)
    str = str..string.format(
      "\n entity flocking v: %.2f,%.2f -> %.2f,%.2f", fdata.ovx, fdata.ovy, fdata.rvx, fdata.rvy
    )
  end

  str = str..'\n'
  str = str..string.format("\n left click: move goal, ctrl + click: add entity")
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
    local fe = Helper.new_entity(math.random(map.w), math.random(map.h))
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
    local angle = e.body:getAngle()
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
  local h
  if math.random() < 0.5 then
    h = math.floor(w + math.random() * 10)
  else
    h = w
  end

  local id = NextEID
  NextEID = NextEID + 1

  local shape, sensor_shape
  if h == w then
    shape = love.physics.newCircleShape(w * 0.5)
    -- sensor_shape = love.physics.newCircleShape(w + MaxNeighborDist)
  else
    shape = love.physics.newRectangleShape(h, w)
    -- sensor_shape = love.physics.newRectangleShape(h + MaxNeighborDist * 2, w + MaxNeighborDist * 2)
  end

  local body = love.physics.newBody(world, x, y, 'dynamic')
  local f = love.physics.newFixture(body, shape)
  -- f:setGroupIndex(-1)
  -- f:setCategory(1)
  -- f:setMask(1)

  -- local sf = love.physics.newFixture(body, sensor_shape)
  -- sf:setSensor(true)
  -- sf:setCategory(2)
  -- sf:setMask(2)

  local speed = 80 + math.random(80)

  local e = {
    id = id,
    r = h * 0.5, w = w, h = h,
    x = x, y = y, angle = 0,
    vx = 0, vy = 0,
    pivot_speed = math.pi * 2, -- radian per seconds

    speed = speed,
    current_speed = 0,

    body = body, shape = shape, fixture = f, sf = sf
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
  e.angle = e.body:getAngle()

  local fcx, fcy = map:screen_to_cell_coord(e.x, e.y, false)
  if field_data then
    local vx, vy = field_data:get_smooth_velocity(fcx, fcy)

    local nes = {}
    for i, ne in ipairs(entities) do
      local dist = Lume.distance(e.x, e.y, ne.x, ne.y)
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
    -- local dist = Lume.distance(ecx, ecy, goal_cx, goal_cy)
    -- local desired_speed = math.max(50, math.min(dist * 50, e.speed))

    vx, vy = Flocking.calc_velcoity(e, vx, vy, nes, obs)
    local f = e.speed * 0.1
    e.vx = e.vx + vx * f
    e.vy = e.vy + vy * f


    local new_angle = Lume.angle(0, 0, e.vx, e.vy)
    local angle_dv = Helper.radian_diff(e.angle, new_angle)
    local speed = e.speed * 0.1 + (1 - angle_dv / PI) * e.speed

    local vlen = Lume.length(e.vx, e.vy)
    if vlen > speed then
      e.vx = e.vx / vlen * speed
      e.vy = e.vy / vlen * speed
    end

    e.body:setLinearVelocity(e.vx, e.vy)

    local rv = angle_dv / dt
    if math.abs(rv) > e.pivot_speed then
      rv = e.pivot_speed * Lume.sign(rv)
    end
    e.body:setAngularVelocity(rv)

    -- e.body:applyLinearImpulse(e.vx * dt, e.vy * dt)

    -- e.x = e.x + e.vx * dt
    -- e.y = e.y + e.vy * dt
    -- e.current_speed = current_speed
  end
end
