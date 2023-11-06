local HC = require 'hc'
local Map = require 'map'
local FieldBuilder = require 'flow_field_builder'
local FieldData = require 'flow_field_data'
local Flocking = require 'flocking'
local Mover = require 'mover'
_G.Lume = require 'lume'
_G.Cpml = require 'cpml'
_G.Vec2 = Cpml.vec2

local lg = love.graphics
local lm = love.mouse

local Util = require 'util'
local Helper = {}

local PI = math.pi
local PI2 = PI * 2


----------------------

local world
local map
local mover
local field_builder
local mcx, mcy
local find_time = 0
local focus_entity = nil

local move_data = {
  {
    field_data = nil,
    goal_cx = nil, goal_cy = nil,
    entities = {},
    should_update_field = true,
    move_id = 0,
  },

  {
    field_data = nil,
    goal_cx = nil, goal_cy = nil,
    entities = {},
    should_update_field = true,
    move_id = 0,
  },
}
local current_group_id = 1
local current_mdata = move_data[current_group_id]

local all_entities = {}

local paused = false
local force_run_frames = 0

local MaxNeighborDist = 80


------------------

function love.load()
  world = HC.new(50)
  local cw, ch = 80, 60
  map = Map.new(cw, ch, world)
  field_builder = FieldBuilder.new(map)
  mover = Mover.new(map)
  for i = 1, 2 do
    local mdata = move_data[i]
    mdata.goal_cx, mdata.goal_cy = math.ceil(map.w / 2), math.ceil(map.h / 2)
    mdata.goal_x, mdata.goal_y = map:cell_to_screen_coord(map.w / 2, map.h / 2)
    Helper.update_field(i)
  end

  focus_entity = Helper.new_entity(map:cell_to_screen_coord(map.w * 0.5, map.h * 0.5))
  focus_entity.debug = true
end

function love.update(dt)
  if dt > 0.1 then
    dt = 0.1
  end
  local mx, my = lm.getPosition()
  mcx, mcy = map:screen_to_cell_coord(mx, my)

  if lm.isDown(2) then
    for i = 1, dt * 800 do
      Helper.new_entity(mx, my)
    end
  end

  if lm.isDown(1) then
    if current_mdata.goal_cx ~= mcx or current_mdata.goal_cy ~= mcy then
      current_mdata.goal_cx, current_mdata.goal_cy = mcx, mcy
      current_mdata.goal_x, current_mdata.goal_y = mx, my
      current_mdata.should_update_field = true
      current_mdata.move_id = current_mdata.move_id + 1
    end
  end

  if paused then
    if force_run_frames > 0 then
      force_run_frames = force_run_frames - 1
    else
      return
    end
  end

  for gi = 1, 2 do
    local es = move_data[gi].entities
    Helper.update_es(es, dt, gi)
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

  -- local aw, cw, sw = Flocking.get_weights()
  -- local wspeed = 3
  -- if kbdown('u') then
  --   aw = aw - wspeed * dt
  -- elseif kbdown('i') then
  --   aw = aw + wspeed * dt
  -- elseif kbdown('j') then
  --   cw = cw - wspeed * dt
  -- elseif kbdown('k') then
  --   cw = cw + wspeed * dt
  -- elseif kbdown('n') then
  --   sw = sw - wspeed * dt
  -- elseif kbdown('m') then
  --   sw = sw + wspeed * dt
  -- end
  -- Flocking.set_weights(aw, cw, sw)

  if new_cost then
    local node = map:get_node(mcx, mcy)
    if node.cost ~= new_cost then
      map:update_cost(node, new_cost)
      move_data[1].should_update_field = true
      move_data[2].should_update_field = true
    end
  end

  for i = 1, 2 do
    if move_data[i].should_update_field then
      Helper.update_field(i)
    end
  end
end

function love.draw()
  lg.setBackgroundColor(0.5, 0.5, 0.55, 1)
  local mx, my = lm.getPosition()

  local cell_w, cell_h = map.cell_w, map.cell_h
  local field_data = current_mdata.field_data

  -- Helper.draw_debug_move_next_grid()
  -- mover:draw_all_grids()

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

  local e_alpha = 0.5
  for gi = 1, 2 do
    if gi == 1 then
      lg.setColor(1, 1, 1, e_alpha)
    else
      lg.setColor(0, 0, 1, e_alpha)
    end
    for i, e in ipairs(move_data[gi].entities) do
      if e ~= focus_entity then
        Helper.draw_entity(e)
      end
    end
    lg.setColor(1, 0, 0)
    for i, e in ipairs(move_data[gi].entities) do
      if e ~= focus_entity then
        Helper.draw_entity_dir(e)
      end
    end

    local e = focus_entity  -- or move_data[gi].entities[1]
    if e then
      if gi == 1 then
        lg.setColor(1, 1, 0, 1)
      else
        lg.setColor(1, 0, 1, 1)
      end

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
  end

  for gi = 1, 2 do
    local mdata = move_data[gi]
    local gx, gy = map:cell_to_screen_coord(mdata.goal_cx + 0.5, mdata.goal_cy + 0.5)

    if gi == 1 then
      lg.setColor(1, 0, 0)
    else
      lg.setColor(0, 0, 1)
    end
    lg.circle('line', gx, gy, cell_h / 1.2)
  end

  lg.setColor(1, 1, 1)
  local str = ''
  str = str..string.format("\n FPS: %i", love.timer.getFPS())

  str = str..'\n'
  local node = map:get_node(mcx, mcy)
  str = str..string.format("\n total entities: %i,%i", #move_data[1].entities, #move_data[2].entities)
  str = str..string.format("\n mouse coord: %i, %i", mcx, mcy)
  str = str..string.format("\n mouse node cost: %i", node.cost)
  local ginfo = mover:get_grid_data(mcx, mcy)
  if ginfo then
    str = str..string.format("\n total used: %i", ginfo.total_used)
  end

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

  local e = focus_entity -- or current_mdata.entities[1]
  if e then
    str = str..string.format("\n entity speed: %.2f/%.2f", e.current_speed, e.desired_speed)
    str = str..string.format("\n entity vel: %.2f,%.2f", e.vx, e.vy)
    str = str..string.format("\n move done: %s", e.move_done and 'y' or 'n')
  end

  str = str..'\n'
  str = str..string.format("\n left click: set goal, right click: add entity. hold left-ctrl to switch group")
  str = str..string.format("\n set cost: 1: 0; 2: 1; 3 2; 4 blocked")
  -- str = str..string.format("\n flocking weight: u, i, j, k, n, m")
  str = str..string.format("\n space: pause, enter run one frame")
  lg.print(str, 10, 10)
end

function love.mousepressed(x, y, btn)
  if btn == 3 then
    local best_e, min_dist2 = nil, math.huge
    local max_dist2 = (focus_entity and focus_entity.r or 6)^2
    for i, e in ipairs(current_mdata.entities) do
      local len2 = Lume.distance(e.x, e.y, x, y, true)
      if len2 <= max_dist2 and len2 <= min_dist2 then
        best_e, min_dist2 = e, len2
      end
    end
    if best_e then
      if focus_entity then
        focus_entity.debug = nil
      end
      focus_entity = best_e
      focus_entity.debug = true
    end
  end
end

function love.keypressed(key)
  if key == 'space' then
    paused = not paused
  elseif key == 'return' then
    force_run_frames = force_run_frames + 1
  elseif key == 'r' then
    move_data[1].entities = {}
    move_data[2].entities = {}
    mover = Mover.new(map)
    world = HC.new()
    all_entities = {}
    focus_entity = Helper.new_entity(map:cell_to_screen_coord(map.w * 0.5, map.h * 0.5))
    focus_entity.debug = true
  elseif key == 'lctrl' then
    current_group_id = 2
    current_mdata = move_data[current_group_id]
  end
end

function love.keyreleased(key)
  if key == 'lctrl' then
    current_group_id = 1
    current_mdata = move_data[1]
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

function Helper.update_field(group_idx)
  local st = love.timer.getTime()
  local mdata = move_data[group_idx]
  local goal = map:get_node(mdata.goal_cx, mdata.goal_cy)
  if map:is_valid_node(goal) then
    local raw_data = field_builder:build(goal)
    mdata.field_data = FieldData.new(raw_data)
  else
    mdata.field_data = nil
  end
  mdata.should_update_field = false
  find_time = (love.timer.getTime() - st) * 1000
end

local NextEID = 1
function Helper.new_entity(x, y, group_id)
  local r = 6 -- math.floor(6 + math.random() * 8)

  local id = NextEID
  NextEID = NextEID + 1

  local shape = world:circle(x, y, r)

  local speed = 100 + math.random(100)
  -- local speed = 150 *

  local e = {
    id = id,
    r = r,
    x = x, y = y, angle = 0,
    vx = 0, vy = 0,
    pivot_speed = math.pi * 2, -- radian per seconds

    speed = speed,
    speed2 = speed^2,
    current_speed = 0,
    desired_speed = 0,

    group_id = group_id or current_group_id,

    shape = shape
  }
  shape.e = e

  -- sf:setUserData(e)
  -- f:setUserData(e)
  all_entities[#all_entities + 1] = e
  if group_id then
    table.insert(move_data[group_id].entities, e)
  else
    table.insert(current_mdata.entities, e)
  end

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

function Helper.update_es(es, dt, group_id)
  local mdata = move_data[group_id]
  local field_data = mdata.field_data

  if not field_data then
    return
  end

  -- local emap = {}
  -- for i, e in ipairs(es) do
  --   local mx, my = map:screen_to_cell_coord(e.x, e.y)
  --   local node = map:get_node(mx, my)
  --   if e.node ~= node then
  --     if e.node then
  --       e.node.total_es = e.node.total_es - 1
  --     end
  --     e.node = node
  --     node.total_es = node.total_es + 1
  --   end
  -- end

  for i, e in ipairs(es) do
    local fcx, fcy = map:screen_to_cell_coord(e.x, e.y, false)
    -- local cx, cy = map:screen_to_cell_coord(e.x, e.y)
    -- local finfo = field_data:get_info(cx, cy)
    -- e.pos_score = finfo and finfo.score or math.huge

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

    local gx, gy = map:cell_to_screen_coord(mdata.goal_cx + 0.5, mdata.goal_cy + 0.5)
    local goal_dist = Lume.distance(e.x, e.y, gx, gy)
    local slow_down_dist = 100
    if goal_dist < slow_down_dist then
      e.desired_speed = goal_dist / slow_down_dist * e.speed
    else
      e.desired_speed = e.speed
    end
    if goal_dist <= 10 then
      e.move_done_id = current_mdata.move_id
    end
    e.move_done = e.move_done_id == current_mdata.move_id

    -- local nbs = {}
    -- for ox = -1, 1 do
    --   for oy = -1, 1 do
    --     local n = 0
    --     for shape in pairs(world._hash:cellAt(e.x + ox * map.cell_w, e.y + oy * map.cell_h)) do
    --       n = n + 1
    --       local ne = shape.e
    --       if ne ~= e then
    --         nbs[#nbs + 1] = ne
    --         nbs[ne] = Lume.distance(e.x, e.y, ne.x, ne.y)
    --       end
    --       if n >= 5 then
    --         break
    --       end
    --     end
    --   end
    -- end

    local vx, vy = field_data:get_smooth_velocity(fcx, fcy)
    -- local rvx, rvy = Flocking.calc_velcoity(e, vx, vy, nbs, obs)

    -- Helper.move_entity(e, rvx, rvy, dt)
    mover:pre_move(e, vx, vy, dt, obs)
  end

  for i, e in ipairs(es) do
    mover:try_move(e, dt)
  end
end

-- function Helper.move_entity(e, vx, vy, dt)
--   -- local desired_velocity = Vec2(vx * e.speed, vy * e.speed)
--   -- e.vx, e.vy = e.vx + desired_velocity.x * dt, e.vy + desired_velocity.y * dt

--   local vspeed = math.sqrt(vx * vx + vy * vy)
--   local dspeed = e.desired_speed
--   if vspeed > e.speed then
--     vx = vx * e.speed / vspeed
--     vy = vy * e.speed / vspeed
--   elseif vspeed > dspeed then
--     local tspeed = math.max(dspeed, vspeed * 0.95)
--     vx = vx * tspeed / vspeed
--     vy = vy * tspeed / vspeed
--   end

--   e.vx, e.vy = vx, vy

--   -- apply block velocity, and don't change speed
--   -- if block_velocity and not block_velocity:is_zero() then
--   --   Helper.apply_block_velocity(e, block_velocity, dt)
--   -- elseif sep_velocity and not sep_velocity:is_zero() then
--   --   -- e.x, e.y = (Vec2(e.x, e.y) + sep_velocity * (e.current_speed + 10) * 1.5 * dt):unpack()
--   --   -- e.body:setPosition(e.x, e.y)
--   --   -- local sv = sep_velocity * (e.current_speed + 10) * 0.7
--   --   -- e.vx, e.vy = e.vx + sv.x, e.vy + sv.y
--   --   -- e.sv = sv
--   -- end

--   -- local new_angle = Lume.angle(0, 0, e.vx, e.vy)
--   -- e.angle = new_angle
--   -- -- local angle_dv = Helper.radian_diff(e.angle, new_angle)

--   -- Helper.control_move(e, desired_velocity, dt)

--   -- if not sep_velocity:is_zero() and (not block_velocity or block_velocity:is_zero()) then
--   --   local sv = sep_velocity * (e.current_speed + 10) * 0.7
--   --   e.vx, e.vy = e.vx + sv.x, e.vy + sv.y
--   --   e.sv = sv
--   -- end

--   -- local speed = Lume.length(e.vx, e.vy)
--   -- if speed > e.speed * 3 then
--   --   local s = e.speed * 3 / speed
--   --   e.vx, e.vy = e.vx * s, e.vy * s
--   -- end

--   -- new_angle = Lume.angle(0, 0, e.vx, e.vy)
--   -- e.shape:setRotation(e.angle)
--   -- local rv = angle_dv / dt
--   -- e.body:setAngularVelocity(rv)

--   e.x = e.x + e.vx * dt
--   e.y = e.y + e.vy * dt
--   e.current_speed = Lume.length(e.vx, e.vy)
--   e.shape:moveTo(e.x, e.y)
--   if e.speed > 0 then
--     e.angle = math.atan2(e.vy, e.vx)
--   end
-- end

function Helper.draw_debug_move_next_grid()
  local size = 80
  local sx, sy = 500, 240

  local goal_x, goal_y = current_mdata.goal_x, current_mdata.goal_y
  local pcx, pcy = goal_x / lg.getWidth(), goal_y / lg.getHeight()
  local mx, my = lm.getPosition()
  local dv = Vec2(mx - goal_x, my - goal_y):normalize()
  local nx, ny = Mover._calc_next_grid(pcx, pcy, dv.x, dv.y)

  local str = string.format(
    "%.2f,%.2f(%.3f,%.3f) -> %.2f,%.2f",
    pcx, pcy, dv.x, dv.y , nx, ny
  )
  lg.print(str, sx, sy - 20)

  local rx, ry = nx + 1, ny + 1

  for i = 0, 2 do
    local x = sx + i * size
    for j = 0, 2 do
      local y = sy + j * size
      if rx == i and ry == j then
        lg.rectangle('fill', x, y, size, size)
      else
        lg.rectangle('line', x, y, size, size)
      end
    end
  end
end

function Helper.draw_move_grid(e)
  local minfo = e.move_info
  if not minfo then
    return
  end
  if minfo.mcx then
    local x, y = map:cell_to_screen_coord(minfo.mcx, minfo.mcy)
    lg.setColor(0, 0, 1, 0.5)
    lg.rectangle('fill', x, y, map.cell_w, map.cell_h)
    lg.setColor(1, 1, 1, 1)
  end
  if minfo.tmcx then
    local x, y = map:cell_to_screen_coord(minfo.tmcx, minfo.tmcy)
    lg.setColor(0, 1, 0, 0.5)
    lg.rectangle('fill', x, y, map.cell_w, map.cell_h)
    lg.setColor(1, 1, 1, 1)
  end
end
