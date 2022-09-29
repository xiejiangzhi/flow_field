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
  local nodes_neighbors = {}

	local g_score = { [goal] = 0 }

	while current do
		closedset[current] = true

    local next_node = came_from[current]
		local neighbors = map:get_neighbors(current, next_node)
    local col = nodes_neighbors[current.x]
    if not col then
      col = {}
      nodes_neighbors[current.x] = col
    end
    col[current.y]= neighbors

		for _, neighbor in ipairs(neighbors) do
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

  -- local field_data = private.build_field_data(came_from, g_score)
  local field_data = private.build_field_data2(g_score, nodes_neighbors)

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


function private.build_field_data(came_from, g_score)
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
  return field_data
end

function private.build_field_data2(g_score, nodes_neighbors)
  local field_data = {}
  local cost_map = {}

  for node, score in pairs(g_score) do
    local col = cost_map[node.x]
    if not col then
      col = {}
      cost_map[node.x] = col
    end
    col[node.y] = score
  end

  local calc_dir = private.calc_dir
  for x, col in pairs(cost_map) do
    local fcol = {}
    field_data[x] = fcol
    for y, score in pairs(col) do
      local ncol = nodes_neighbors[x]
      local vx, vy = calc_dir(cost_map, x, y, ncol and ncol[y])
      fcol[y] = new_info(vx, vy, score)
    end
  end
  return field_data
end

local dir_normal_scale = 1 / math.sqrt(2)
function private.calc_dir(scores, x, y, neighbors)
  local vx, vy = 0, 0
  local bscore = scores[x] and scores[x][y]
  if not bscore or not neighbors or #neighbors == 0 then
    return vx, vy
  end

  local min_x, min_y, min_score = 0, 0, bscore
  for i, n in ipairs(neighbors) do
    local ox, oy = n.x - x, n.y - y
    local scol = scores[x + ox]
    local s = scol and scol[y + oy]
    if s and not min_score or s < min_score then
      min_x, min_y, min_score = ox, oy, s
    end
  end

  for i, n in ipairs(neighbors) do
    local ox, oy = n.x - x, n.y - y
    local scol = scores[x + ox]
    local s = scol and scol[y + oy]
    if s then
      if not min_score or s < min_score then
        min_x, min_y, min_score = ox, oy, s
      end

      local ks = s - min_score
      local kv = (ks == 0) and 0.5 or (1 / ks)
      vx = vx + ox * kv
      vy = vy + oy * kv
    end
  end

  if math.abs(min_x) == 1 and math.abs(min_y) == 1 then
    min_x = min_x * dir_normal_scale
    min_y = min_y * dir_normal_scale
  end
  -- min_x, min_y = 0, 0

  -- normalize
  vx = vx + min_x
  vy = vy + min_y
  local len = math.sqrt(vx * vx + vy * vy)
  if len > 0 then
    return vx / len, vy / len
  else
    return 0, 0
  end
end

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
