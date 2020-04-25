local PathFinder = require 'flow_field'

local map = {}
local map_w, map_h = 50, 35
local w, h
local cell_w, cell_h
local cached_nodes = {}
local checked_nodes = {}
local mcx, mcy = 0, 0

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

local function map_to_cell_coord(x, y)
  return math.floor(x / cell_w), math.floor(y / cell_h)
end

local function cell_to_map_coord(x, y)
  return x * cell_w, y * cell_h
end

local neighbors_offset = {
  { -1, -1 }, { 0, -1 }, { 1, -1 },
  { -1, 0 }, { 1, 0 },
  { -1, 1 }, { 0, 1 }, { 1, 1 },
}
-- Return all neighbor nodes. Means a target that can be moved from the current node
function map:get_neighbors(node)
  local nodes = {}
  local x, y = node.x, node.y
  for i, offset in ipairs(neighbors_offset) do
    local tnode = get_node(x + offset[1], y + offset[2])
    if self:is_valid_node(tnode) and self:is_valid_neighbor(node, tnode) then
      nodes[#nodes + 1] = tnode
    end
  end
  return nodes
end

function map:is_valid_node(node)
  return node.cost >= 0 and node.x >= 0 and node.x < map_w and node.y >= 0 and node.y < map_h
end

function map:is_valid_neighbor(from, node)
  if node.x == from.x or node.y == from.y then return true end
  local dx, dy = node.x - from.x, node.y - from.y

  return self:is_valid_node(get_node(from.x + dx, from.y)) and self:is_valid_node(get_node(from.x, from.y + dy))
end

-- Cost of two adjacent nodes
function map:get_cost(from_node, to_node)
  local dx, dy = from_node.x - to_node.x, from_node.y - to_node.y
  return math.sqrt(dx * dx + dy * dy) + (from_node.cost + to_node.cost) * 0.5
end

----------------------

local finder = PathFinder.new(map)
local field, scores
local goal_x, goal_y = math.ceil(map_w / 2), math.ceil(map_h / 2)
local find_time = 0
local e = { x = 1, y = 1, speed = 300 }

local function update_field()
  checked_nodes = {}

  local st = love.timer.getTime()
  local goal = get_node(goal_x, goal_y)
  if map:is_valid_node(goal) then
    field, scores = finder:build(goal)
  else
    field, scores = {}, {}
  end
  find_time = (love.timer.getTime() - st) * 1000
end

local function move_to_goal(dt)
  local ecx, ecy = map_to_cell_coord(e.x, e.y)

  local next_node = e.next_node
  if not next_node then
    local cnode = get_node(ecx, ecy)
    next_node = field[cnode]
    if next_node and map:is_valid_node(next_node) then
      e.next_node = next_node
    else
      return
    end
  end

  local nx, ny = cell_to_map_coord(next_node.x + 0.5, next_node.y + 0.5)
  local dx, dy = nx - e.x, ny - e.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local mv_dist = e.speed * dt
  if dist <= (mv_dist + 1e-10) then e.next_node = nil end

  local angle = math.atan2(ny - e.y, nx - e.x)
  local ox, oy = math.cos(angle) * mv_dist, math.sin(angle) * mv_dist
  e.x, e.y = e.x + ox, e.y + oy
end

------------------

function love.load()
  update_field()
  w, h = love.graphics.getDimensions()
  cell_w, cell_h = w / map_w, h / map_h
end

function love.update(dt)
  local mx, my = love.mouse.getPosition()
  mcx, mcy = map_to_cell_coord(mx, my)
  local changed = false

  local mdown = love.mouse.isDown
  if mdown(2) then
    e.x, e.y = mx, my
  else
    move_to_goal(dt)
  end

  if mdown(1) and goal_x ~= mcx and goal_y ~= mcy then
    goal_x, goal_y = mcx, mcy
    changed = true
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
      node.cost = new_cost
      changed = true
    end
  end

  if changed then
    update_field()
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
          lg.setColor(1, 1, 0.5, 1)
        elseif cost == 2 then
          lg.setColor(0.5, 0.5, 0.1, 1)
        end
        lg.rectangle('fill', x, y, cell_w, cell_h)
        lg.setColor(1, 1, 1)
      end

      local next_node = field[node]
      if next_node then
        lg.setColor(0.1, 0.1, 0.3, 0.5)
        local angle = math.atan2(next_node.y - node.y, next_node.x - node.x)
        local cx, cy = x + cell_w / 2, y + cell_h / 2
        lg.circle('fill', cx, cy, 3)

        local dist = math.min(cell_w, cell_h) - 5
        local ox, oy = math.cos(angle) * dist, math.sin(angle) * dist
        lg.line(cx, cy, cx + ox, cy + oy)
        lg.setColor(1, 1, 1)
      end

      -- local score = scores[node]
      -- if score then
      --   lg.setColor(1, 1, 1, 0.5)
      --   lg.print(string.format('%.1f', score), x + 3, y + 3)
      --   lg.setColor(1, 1, 1)
      -- end
    end
  end

  lg.setColor(1, 1, 1)
  lg.circle('fill', e.x, e.y, cell_h / 3)
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
  str = str..string.format("\n checked nodes: %i", #checked_nodes)
  str = str..string.format("\n time: %.2fms", find_time)

  str = str..'\n'
  str = str..string.format("\n left/right click: move goal/entity", find_time)
  str = str..string.format("\n keyboard: 1: cost 0; 2: cost 1; 3 cost 2; 4 blocked", find_time)
  lg.print(str, 10, 10)
end

