local Map = require 'map'
local FieldBuilder = require 'flow_field_builder'
local FieldData = require 'flow_field_data'
local Flocking = require 'flocking'
local Lume = require 'lume'

local lg = love.graphics

local Helper = {}

----------------------

local map
local field_data
local field_builder
local mcx, mcy
local goal_x, goal_y
local find_time = 0
local entities = {}
local paused = false
local force_run_frames = 0

local MaxNeighborDist = 200


------------------

function love.load()
  map = Map.new(60, 42)
  field_builder = FieldBuilder.new(map)
  goal_x, goal_y = math.ceil(map.w / 2), math.ceil(map.h / 2)
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


  if love.mouse.isDown(1) then
    if love.keyboard.isDown('lctrl') then
      entities[#entities + 1] = Helper.new_entity(mx, my)
    elseif goal_x ~= mcx and goal_y ~= mcy then
      goal_x, goal_y = mcx, mcy
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
  local gx, gy = map:cell_to_screen_coord(goal_x + 0.5, goal_y + 0.5)
  lg.circle('line', gx, gy, cell_h / 1.2)

  lg.setColor(1, 1, 1)
  local str = ''
  str = str..string.format("\n FPS: %i", love.timer.getFPS())

  str = str..'\n'
  local mnode = map:get_node(mcx, mcy)
  str = str..string.format("\n total entities: %i", #entities)
  str = str..string.format("\n mouse coord: %i, %i", mcx, mcy)
  str = str..string.format("\n mouse node cost: %i", mnode.cost)

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
  end
end

---------------------

function Helper.draw_entity(e)
  lg.circle('fill', e.x, e.y, e.r)
end

function Helper.draw_entity_dir(e)
  local angle = e.angle
  local ox, oy = Lume.vector(angle, 10)
  lg.line(e.x, e.y, e.x + ox, e.y + oy)
end

function Helper.update_field()
  local st = love.timer.getTime()
  local goal = map:get_node(goal_x, goal_y)
  if map:is_valid_node(goal) then
    local raw_data = field_builder:build(goal)
    field_data = FieldData.new(raw_data)
  else
    field_data = nil
  end
  find_time = (love.timer.getTime() - st) * 1000
end

function Helper.new_entity(x, y, radius, speed)
  radius = radius or 6
  return {
    x = x, y = y, r = radius, angle = 0,
    vx = 0, vy = 0,
    speed = speed or (80 + math.random(50)),
    pivot_speed = math.pi * 0.1
  }
end

function Helper.update_entity(e, dt)
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

    local ecx, ecy = math.floor(fcx), math.floor(fcy)
    local obs = {
      l = map:is_valid_pos(ecx - 1, ecy) and 1 or 0,
      r = map:is_valid_pos(ecx + 1, ecy) and 1 or 0,
      t = map:is_valid_pos(ecx, ecy - 1) and 1 or 0,
      b = map:is_valid_pos(ecx, ecy + 1) and 1 or 0,
    }
    local angular
    vx, vy, angular = Flocking.calc_velcoity(e, vx, vy, e.speed, nes, obs)
    -- vx, vy = vx * e.speed, vy * e.speed
    e.x = e.x + vx * dt
    e.y = e.y + vy * dt
    e.vx, e.vy = vx, vy
    e.angle = e.angle + angular
  end
end
