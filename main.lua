local HC = require 'hc'
local Map = require 'map'
local FieldBuilder = require 'flow_field_builder'
local FieldData = require 'flow_field_data'
local RVO2 = require 'librvo2'
_G.Lume = require 'lume'
_G.Cpml = require 'cpml'
_G.Vec2 = Cpml.vec2

local lg = love.graphics
local lm = love.mouse

local Util = require 'util'
local Helper = {}

local PI = math.pi
local PI2 = PI * 2

RVO2.setup('./librvo2.dll')

----------------------

local world
local map
local field_builder
local mcx, mcy
local find_time = 0
local focus_entity = nil
local rvo_sim

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
  rvo_sim = Helper.new_rvo_sim()
  local cw, ch = 80, 60
  map = Map.new(cw, ch, world)
  field_builder = FieldBuilder.new(map)
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

  rvo_sim.ts = rvo_sim.ts + dt
  if rvo_sim.ts >= rvo_sim.time_step then
    rvo_sim.ts = rvo_sim.ts - rvo_sim.time_step
    for gi = 1, 2 do
      Helper.pre_rvo_step(move_data[gi])
    end
    rvo_sim:do_step()
    for gi = 1, 2 do
      Helper.sync_rvo_data(move_data[gi])
    end
  end
  for gi = 1, 2 do
    Helper.move_es(move_data[gi].entities, dt)
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
  str = str..string.format(
    "\n total entities: %i + %i = %i", #move_data[1].entities, #move_data[2].entities,
    #move_data[1].entities + #move_data[2].entities
  )
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

  local e = focus_entity
  if e then
    str = str..string.format("\n entity pos: %.2f/%.2f", e.x, e.y)
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
    world = HC.new()
    rvo_sim = Helper.new_rvo_sim()
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

  local speed = 120 + math.random(240)
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

    shape = shape,

    rvo_agent_id = rvo_sim:add_agent(0, 0)
  }
  shape.e = e
  rvo_sim:set_agent_speed(e.rvo_agent_id, e.speed)
  rvo_sim:set_agent_radius(e.rvo_agent_id, e.r)

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

function Helper.pre_rvo_step(mdata)
  local field_data = mdata.field_data
  if not field_data then return end

  for i, e in ipairs(mdata.entities) do
    local fcx, fcy = map:screen_to_cell_coord(e.x, e.y, false)

    local gx, gy = map:cell_to_screen_coord(mdata.goal_cx + 0.5, mdata.goal_cy + 0.5)
    local goal_dist = Lume.distance(e.x, e.y, gx, gy)
    local slow_down_dist = 80
    if goal_dist < slow_down_dist then
      e.desired_speed = math.max(20, goal_dist / slow_down_dist * e.speed)
    else
      e.desired_speed = e.speed
    end
    if goal_dist <= 10 then
      e.move_done_id = mdata.move_id
    end
    e.move_done = e.move_done_id == mdata.move_id

    local bvx, bvy = Util.calc_block_velocity(map, fcx, fcy, 0.3)

    local vx, vy, pvx, pvy
    if bvx ~= 0 or bvy ~= 0 then
      vx, vy = bvx * e.speed, bvy * e.speed
      pvx, pvy = vx, vy
    elseif e.move_done then
      vx, vy = e.vx, e.vy
      pvx, pvy = 0, 0
    else
      vx, vy = e.vx, e.vy
      pvx, pvy = field_data:get_smooth_velocity(fcx, fcy)
      pvx, pvy = pvx * e.desired_speed, pvy * e.desired_speed
    end
    rvo_sim:set_agent_pos_and_vel(e.rvo_agent_id, e.x, e.y, vx, vy, pvx, pvy)
  end
end

function Helper.sync_rvo_data(mdata)
  local field_data = mdata.field_data
  if not field_data then return end

  for i, e in ipairs(mdata.entities) do
    local vx, vy = rvo_sim:get_agent_vel(e.rvo_agent_id)
    local speed = Lume.length(e.vx, e.vy)
    if speed > e.speed then
      local s = e.speed / speed
      e.vx, e.vy = vx * s, vy * s
      e.current_speed = e.speed
    else
      e.vx, e.vy = vx, vy
      e.current_speed = speed
    end
  end
end

function Helper.move_es(es, dt)
  for i, e in ipairs(es) do
    local fcx, fcy = map:screen_to_cell_coord(e.x, e.y, false)
    local bvx, bvy = Util.calc_block_velocity(map, fcx, fcy, 0.3)
    local vx, vy
    if bvx ~= 0 or bvy ~= 0 then
      local vs = e.speed
      vx, vy = bvx * vs, bvy * vs
    else
      vx, vy = e.vx, e.vy
    end

    if vx ~= 0 or vy ~= 0 then
      e.x, e.y = e.x + vx * dt, e.y + vy * dt
      e.current_speed = Lume.length(vx, vy)
      e.angle = math.atan2(vy, vx)
    else
      e.current_speed = 0
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

function Helper.new_rvo_sim()
  local sim = RVO2.new()
  sim.ts = 0
  sim.time_step = 0.1
  sim:set_time_step(sim.time_step)
  sim:set_agent_default(15, 10, 3, 3, 6.5, 180)
  return sim
end
