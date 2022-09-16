local M = {}

local M = {}
M.__index = M

function M.new(...)
  local obj = setmetatable({}, M)
  obj:init(...)
  return obj
end

function M:init(w, h, world)
  self.w, self.h = w, h
  self.world = world

  local win_w, win_h = love.graphics.getDimensions()
  self.cell_w, self.cell_h = win_w / w, win_h / h

  self.nodes = {}
end

-- Node must be able to check if they are the same
-- so the example cannot directly return a different table for same coord
function M:get_node(x, y)
  local col = self.nodes[x]
  if not col then
    col = {}
    self.nodes[x] = col
  end
  local node = col[y]
  if not node then
    node = { x = x, y = y, cost = 0, block = false }
    col[y] = node
  end
  return node
end

function M:screen_to_cell_coord(x, y, floor)
  local cx, cy = x / self.cell_w, y / self.cell_h
  if floor == false then
    return cx, cy
  else
    return math.floor(cx), math.floor(cy)
  end
end

function M:cell_to_screen_coord(x, y)
  return x * self.cell_w, y * self.cell_h
end

----------------------

-- Return all neighbor nodes. Means a target that can be moved from the current node
function M:get_neighbors(node)
  local nodes = {}
  local x, y = node.x, node.y

  for oy = -1, 1 do
    for ox = -1, 1 do
      if ox ~= 0 or oy ~= 0 then
        local tnode = self:get_node(x + ox, y + oy)

        if self:is_valid_node(tnode) and self:is_valid_neighbor(node, tnode) then
          nodes[#nodes + 1] = tnode
        end
      end
    end
  end

  return nodes
end

function M:is_valid_pos(cx, cy)
  local node = self:get_node(cx, cy)
  if not node then
    return false
  else
    return self:is_valid_node(node)
  end
end

function M:is_valid_node(node)
  local r = node.is_valid
  if r == nil then
    r = node.cost >= 0
      and node.x >= 0 and node.x < self.w
      and node.y >= 0 and node.y < self.h
    node.is_valid = r
  end
  return r
end

function M:update_cost(node, new_cost)
  node.is_valid = nil
  node.cost = new_cost

  if new_cost == -1  then
    if not node.phy then
      local shape = love.physics.newRectangleShape(self.cell_w, self.cell_h)
      local x, y = (node.x + 0.5) * self.cell_w, (node.y + 0.5) * self.cell_h
      local body = love.physics.newBody(self.world, x, y, 'static')
      local fixture = love.physics.newFixture(body, shape)
      node.phy = {
        body = body,
        shape = shape,
        fixture = fixture
      }
    elseif not node.phy.fixture then
      node.phy.fixture = love.physics.newFixture(node.phy.body, node.phy.shape)
    end
  else
    if node.phy and node.phy.fixture then
      node.phy.fixture:destroy()
      node.phy.fixture = nil
    end
  end
end

function M:is_valid_neighbor(from, node)
  if not self:is_valid_node(node) then
    return false
  end

  -- x move
  if node.x ~= from.x and node.y ~= from.y then
    local edge1 = self:get_node(node.x, from.y)
    if not self:is_valid_node(edge1) then
      return false
    end
    local edge2 = self:get_node(from.x, node.y)
    if not self:is_valid_node(edge2) then
      return false
    end
  end

  return true
end

-- Cost of two adjacent nodes
function M:get_cost(from_node, to_node)
  local dx, dy = from_node.x - to_node.x, from_node.y - to_node.y
  return math.sqrt(dx * dx + dy * dy) + (from_node.cost + to_node.cost) * 0.5
end


return M
