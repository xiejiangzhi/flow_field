-- AStar
--
-- map:
--  get_neighbors(node) -- all moveable neighbors
--  get_cost(from_node, to_node)
--
-- node:
--  x:
--  y:
--  ==: check two node is same

local M = {}
M.__index = M

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

-- goal: goal node
function M:build(goal)
  local map = self.map

	local openset = { [goal] = true }
  local current = goal
	local closedset = {}
	local field = {}

	local g_score = { [goal] = 0 }

	while current do
		closedset[current] = true

    local pre_node = field[current]
		local neighbors = map:get_neighbors(current, pre_node)
		for _, neighbor in ipairs (neighbors) do
			if not closedset[neighbor] then
				local tentative_g_score = g_score[current] + map:get_cost(current, neighbor, pre_node)

				if not openset[neighbor] or tentative_g_score < g_score[neighbor] then
					field[neighbor] = current
					g_score[neighbor] = tentative_g_score
          openset[neighbor] = true
				end
			end
		end

		current = private.pop_best_node(openset, g_score)
	end

	return field, g_score
end

----------------------------

-- -- return: node
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

-- function private.unwind_path(flat_path, map, current_node)
-- 	if map[current_node] then
-- 		table.insert(flat_path, 1, map [ current_node ])
-- 		return private.unwind_path(flat_path, map, map [ current_node ])
-- 	else
-- 		return flat_path
-- 	end
-- end

return M
