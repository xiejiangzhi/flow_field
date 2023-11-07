Flow-Field
==========

An Flow-Field pathfinding library for Lua.

![img](./example.png)

## Use

A example for grid map

```lua
local PathFinder = require 'flow_field'

local map = { w = 40, h = 32 }
local cached_nodes = {}

local function get_node(x, y)
  local row = cached_nodes[y]
  if not row then row = {}; cached_nodes[y] = row end
  local node = row[x]
  if not node then node = { x = x, y = y, cost = 0 }; row[x] = node end
  return node
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
  return node.cost >= 0 and node.x >= 0 and node.x < map.w and node.y >= 0 and node.y < map.h
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

local st = os.clock()
local goal = get_node(5, 5)
local field = finder:build(goal)

-- print path
local start = get_node(1, 1)
while start ~= goal do
  if not start then break end

  local info = field[start]
  if info then
    print(start.x, start.y, info.score)
    start = get_node(start.x + info.ox, start.y + info.oy)
  else
    start = nil
  end
end

-- print field
local direction_char = {
  '↖', '↑', '↗',
  '←', 'o', '→',
  '↙', '↓', '↘'
}
local str = ''
for y = 0, map.h do
  for x = 0, map.w do
    local cnode = get_node(x, y)
    local tinfo = field[cnode]

    if not tinfo then
      str = str..'  '
    else
      local ox, oy = tinfo.ox + 1, tinfo.oy + 1
      local idx = oy * 3 + ox + 1
      str = str..' '..direction_char[idx]
    end

  end
  str = str..'\n'
end
print(str)
```

And you can try to run the `main.lua` by Love2d


## About RVO2

librvo2.dll from [RVO2](https://github.com/xiejiangzhi/RVO2_SharedExport/tree/c_export) SharedExport

