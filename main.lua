local PathFinder = require 'flow_field'

local world
local map = {}
local map_w, map_h = 100, 70
local w, h
local cell_w, cell_h
local cached_nodes = {}
local checked_nodes = {}
local check_counter = 0
local mcx, mcy = 0, 0
local neighbor_dist = 1

local lg = love.graphics

-- Node must be able to check if they are the same
-- so the example cannot directly return a different table for same coord
local function get_node(x, y)
  local row = cached_nodes[y]
  if not row then row = {}; cached_nodes[y] = row end
  local node = row[x]
  if not node then node = { x = x, y = y, cost = 0 }; row[x] = node end
  return node
end

local function map_to_cell_coord(x, y, format)
  local cx, cy = x / cell_w, y / cell_h
  if format == false then
    return cx, cy
  else
    return math.floor(cx), math.floor(cy)
  end
end

local function cell_to_map_coord(x, y)
  return x * cell_w, y * cell_h
end

local function los(x0, y0, x1,y1, cb)
  local sx,sy,dx,dy

  if x0 < x1 then
    sx = 1
    dx = x1 - x0
  else
    sx = -1
    dx = x0 - x1
  end

  if y0 < y1 then
    sy = 1
    dy = y1 - y0
  else
    sy = -1
    dy = y0 - y1
  end

  local err, e2 = dx-dy, nil
  if not cb(x0, y0) then return false end

  while not(x0 == x1 and y0 == y1) do
    e2 = err + err
    if e2 > -dy then
      err = err - dy
      x0  = x0 + sx
    end
    if e2 < dx then
      err = err + dx
      y0  = y0 + sy
    end
    if not cb(x0, y0) then return false end
    if e2 > -dy and e2 < dx then
      if not cb(x0 - sx, y0) or not cb(x0, y0 - sy) then return false end
    end
  end

  return true
end

----------------------

-- Return all neighbor nodes. Means a target that can be moved from the current node
function map:get_neighbors(node)
  local nodes = {}
  local x, y = node.x, node.y

  for oy = -neighbor_dist, neighbor_dist do
    for ox = -neighbor_dist, neighbor_dist do
      if not (ox == 0 and oy == 0) then
        local tnode = get_node(x + ox, y + oy)

        if self:is_valid_node(tnode) and self:is_valid_neighbor(node, tnode) then
          nodes[#nodes + 1] = tnode
        end
      end
    end
  end

  return nodes
end

local cached_state = {}
function map:is_valid_node(node)
  local r = cached_state[node]
  if r == nil then
    checked_nodes[#checked_nodes + 1] = node
    r = node.cost >= 0 and node.x >= 0 and node.x < map_w and node.y >= 0 and node.y < map_h
    cached_state[node] = r
  end

  return r
end

function map:is_valid_neighbor(from, node)
  check_counter = check_counter + 1
  return los(from.x, from.y, node.x, node.y, function(x, y)
    local tnode = get_node(x, y)
    return self:is_valid_node(tnode)
  end)
end

-- Cost of two adjacent nodes
function map:get_cost(from_node, to_node)
  local dx, dy = from_node.x - to_node.x, from_node.y - to_node.y
  return math.sqrt(dx * dx + dy * dy) + (from_node.cost + to_node.cost) * 0.5
end

----------------------

local finder = PathFinder.new(map)
local field
local goal_x, goal_y = math.ceil(map_w / 2), math.ceil(map_h / 2)
local find_time = 0

local function update_field(reset_state, reset_nodes)
  checked_nodes = {}
  -- if reset_state then cached_state = {} end
  cached_state = {}
  check_counter = 0

  local st = love.timer.getTime()
  local goal = get_node(goal_x, goal_y)
  if map:is_valid_node(goal) then
    field = finder:build(goal)
  else
    field = {}
  end
  find_time = (love.timer.getTime() - st) * 1000
end

local function new_entity(x, y, r, speed)
  r = r or (cell_h * 0.4 + math.random() * 0.4)
  local shape = love.physics.newCircleShape(r)
  local body = love.physics.newBody(world, x, y, 'dynamic')
  local fixture = love.physics.newFixture(body, shape)

  return {
    x = x, y = y, r = r,
    speed = speed or (30 + math.random(50)),
    shape = shape, body = body, fixture = fixture,
  }
end

local function bilinear_interpolation(x, y, q11, q12, q21, q22)
  local x1, y1, x2, y2 = q11.x, q11.y, q22.x, q22.y

  local r = {}
  local tx1, tx2 = (x2 - x) / (x2 - x1), (x - x1) / (x2 - x1)
  local ty1, ty2 = (y2 - y) / (y2 - y1), (y - y1) / (y2 - y1)

  for i, k in ipairs({ 'vx', 'vy' }) do
    local r1 = tx1 * q11[k] + tx2 * q21[k]
    local r2 = tx1 * q12[k] + tx2 * q22[k]
    r[i] = ty1 * r1 + ty2 * r2
  end

  return unpack(r)
end

local function get_velocity(cx, cy)
  local cnode = get_node(cx, cy)
  local info = field[cnode]
  if not info then return end
  return { x = cx, y = cy, vx = info.vx, vy = info.vy }
end

local function get_smooth_velocity(e)
  local ecx, ecy = map_to_cell_coord(e.x, e.y)
  local fcx, fcy = map_to_cell_coord(e.x, e.y, false)
  local dx, dy = fcx - ecx - 0.5, fcy - ecy - 0.5
  dx = (dx < 0) and -1 or 1
  dy = (dy < 0) and -1 or 1

  local q11, q12, q21, q22 =
    get_velocity(ecx, ecy),
    get_velocity(ecx, ecy + dy),
    get_velocity(ecx + dx, ecy),
    get_velocity(ecx + dx, ecy + dy)

  if not q11 then return 0, 0 end
  if not(q12 and q21 and q22) then return q11.vx, q11.vy end
  return bilinear_interpolation(fcx, fcy, q11, q12, q21, q22)
end

local function update_velocity(e)
  local vx, vy = get_smooth_velocity(e)
  e.body:setLinearVelocity(vx * e.speed, vy * e.speed)
end

local function update_node(node, new_cost)
  node.cost = new_cost

  if node.cost == -1 then
    if not node.fixture then
      node.shape = love.physics.newRectangleShape(cell_w, cell_h)
      local x, y = cell_to_map_coord(node.x + 0.5, node.y + 0.5)
      node.body = love.physics.newBody(world, x, y, 'static')
      node.fixture = love.physics.newFixture(node.body, node.shape)
    end
  elseif node.fixture then
    node.fixture:destroy()
    node.fixture = nil
    node.body:destroy()
    node.body = nil
    node.shape = nil
  end
end

------------------

local entities = {}

function love.load()
  world = love.physics.newWorld()
  update_field()
  w, h = love.graphics.getDimensions()
  cell_w, cell_h = w / map_w, h / map_h

  for i = 1, 3 do
    entities[#entities + 1] = new_entity(math.random(w), math.random(h))
  end
end

function love.update(dt)
  local mx, my = love.mouse.getPosition()
  mcx, mcy = map_to_cell_coord(mx, my)
  local changed = false

  world:update(dt)
  for i, e in ipairs(entities) do
    e.x, e.y = e.body:getPosition()
    update_velocity(e)
  end


  if love.mouse.isDown(1) then
    if love.keyboard.isDown('lctrl') then
      entities[#entities + 1] = new_entity(mx, my)
    elseif goal_x ~= mcx and goal_y ~= mcy then
      goal_x, goal_y = mcx, mcy
      changed = 1
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

  if new_cost then
    local node = get_node(mcx, mcy)
    if node.cost ~= new_cost then
      update_node(node, new_cost)
      changed = 2
    end
  end

  if changed then
    update_field(changed > 1)
  end
end

function love.draw()
  lg.setBackgroundColor(0.5, 0.5, 0.55, 1)

  for i = 0, map_h - 1 do
    for j = 0, map_w - 1 do
      local x, y = cell_to_map_coord(j, i)
      local node = get_node(j, i)
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

      local info = field[node]
      if info then
        local cx, cy = x + cell_w / 2, y + cell_h / 2
        local dist = cell_w / 2
        lg.setColor(0.1, 0.1, 0.3, 0.5)
        lg.line(cx, cy, cx + info.vx * dist, cy + info.vy * dist)
        lg.setColor(1, 1, 1)
        lg.circle('fill', cx, cy, 1)
      end

      -- local info = field[node]
      -- if info then
      --   lg.setColor(1, 1, 1, 0.5)
      --   lg.print(string.format('%.1f', info.score), x + 3, y + 3)
      --   lg.setColor(1, 1, 1)
      -- end
    end
  end

  lg.setColor(1, 1, 1)
  for i, e in ipairs(entities) do
    lg.circle('fill', e.x, e.y, cell_h / 3)
  end
  lg.setColor(0, 0, 1)
  local gx, gy = cell_to_map_coord(goal_x + 0.5, goal_y + 0.5)
  lg.circle('line', gx, gy, cell_h / 1.2)

  lg.setColor(1, 1, 1)
  local str = ''
  str = str..string.format("\n FPS: %i", love.timer.getFPS())

  str = str..'\n'
  local mnode = get_node(mcx, mcy)
  str = str..string.format("\n mouse coord: %i, %i", mcx, mcy)
  str = str..string.format("\n mouse node cost: %i", mnode.cost)

  str = str..'\n'
  str = str..string.format("\n map size: %i x %i = %i", map_w, map_h, map_w * map_h)
  str = str..string.format("\n neighbor dist: %i", neighbor_dist)
  str = str..string.format("\n checked nodes: %i", #checked_nodes)
  str = str..string.format("\n checked neighbors: %i", check_counter)
  str = str..string.format("\n time: %.2fms", find_time)

  str = str..'\n'
  str = str..string.format("\n left click: move goal, ctrl + click: add entity", find_time)
  str = str..string.format("\n set cost: 1: 0; 2: 1; 3 2; 4 blocked", find_time)
  lg.print(str, 10, 10)
end

function love.keypressed(key)
  if key == 'u' then
    neighbor_dist = math.max(1, neighbor_dist - 1)
    update_field()
  elseif key == 'i' then
    neighbor_dist = math.min(5, neighbor_dist + 1)
    update_field()
  end
end

