-- Flow Field
--
-- map:
--  get_neighbors(node) -- all moveable neighbors
--  get_cost(from_node, to_node)
-- node:
--  x:
--  y:

local M = {}
M.__index = M

local has_ffi, ffi = pcall(require, 'ffi')
local new_info

if has_ffi then
  ffi.cdef([[
    typedef struct {
      float vx, vy; // velocity
      float score;
      short ox, oy; // offset of next node
    } flow_field_node_info;
  ]])
  new_info = ffi.typeof("flow_field_node_info")
else
  new_info = function(vx, vy, score, ox, oy)
    return { vx = vx, vy = vy, score = score, ox = ox, oy = oy }
  end
end


local private = {}
local inf = 1 / 0

function M.new(...)
  local obj = setmetatable({}, M)
  obj:init(...)
  return obj
end

function M:init(map)
  self.map = map
  assert(
    map.get_neighbors and map.get_cost,
    "Invalid map, must include get_neighbors, get_cost and estimate_cost functions"
  )
end

-- Params:
--  goal: goal node
-- Return:
--  field: { [node] = { next_node = next_node, vx = 1, vy = 1 }, score = 123 } -- vx, vy: velocity
--
function M:build(goal)
  local map = self.map

	local openset = { [goal] = true }
  local current = goal
	local closedset = {}
  local came_from = {}

	local g_score = { [goal] = 0 }

	while current do
		closedset[current] = true

    local next_node = came_from[current]
		local neighbors = map:get_neighbors(current, next_node)

		for _, neighbor in ipairs (neighbors) do
			if not closedset[neighbor] then
				local tentative_g_score = g_score[current] + map:get_cost(current, neighbor, next_node)

				if not openset[neighbor] or tentative_g_score < g_score[neighbor] then
					came_from[neighbor] = current
					g_score[neighbor] = tentative_g_score
          openset[neighbor] = true
				end
			end
		end

		current = private.pop_best_node(openset, g_score)
	end

  local field_data = {}
  local atan = math.atan2
  for node, next_node in pairs(came_from) do
    local col = field_data[node.x]
    if not col then
      col = {}
      field_data[node.x] = col
    end

    local ox, oy = next_node.x - node.x, next_node.y - node.y
    local angle = atan(oy, ox)
    col[node.y] = new_info(
      math.cos(angle), math.sin(angle), g_score[node]
    )
  end
  local col = field_data[goal.x]
  if not col then
    col = {}
    field_data[goal.x] = col
  end
  col[goal.y] = new_info(0, 0, 0)

  field_data.goal_x, field_data.goal_y = goal.x, goal.y

	return field_data
end

----------------------------

-- Return: best node
function private.pop_best_node(set, score)
  local best, node = inf, nil

  for k, v in pairs(set) do
    local s = score[k]
    if s < best then
      best, node = s, k
    end
  end
  if not node then return end
  set[node] = nil
  return node
end

return M
