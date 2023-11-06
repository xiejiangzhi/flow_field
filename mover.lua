local M = {}
M.__index = M

local Util = require 'util'
local Floor = math.floor
local Abs = math.abs

local Sqrt = math.sqrt

local CmpEntity = function(a, b)
  return a.id < b.id -- or (a.vx * b.x + a.vy * b.y) < 0
end

function M.new(map)
  return setmetatable({
    map = map,
    mdata = {},
    total_grids = 0,
  }, M)
end

--[[
基于 grid 的移动，每个格子两个标志：占用状态： 空/占用，移动状态： 无/锁定/尝试
空：可以移到到这个格子上，移动前进行锁定
占用：单位已经占用的位置，无法被锁定，但可以设定为尝试

锁定：将要移动的目标，无法被其它单位占用。
尝试：对于已经占用的格子，可以设定尝试标志，在这个格子上的单位，会尝试移动到其它空格子，已经没有可移动的格子，将会尝试找一个周边为占用状态的无移动标志的转为尝试。

当前移动路线被挡时，可以尝试向周边其它相对当前格子更近或是相等的格子前进
]]

function M:pre_move(e, fvx, fvy, dt, obs)
  if e.move_done then
    fvx, fvy = 0, 0
    e.vx, e.vy = e.vx * 0.5, e.vy * 0.5
  end

  local speed_force = e.desired_speed
  local svx, svy = e.vx + fvx * speed_force, e.vy + fvy * speed_force

  local minfo, ginfo = self:update_move_info(e)

  if e.move_done and ginfo.total_used <= 1 and (e.vx * e.vx + e.vy * e.vy) < 9 then
    e.vx, e.vy = 0, 0
    return
  end

  local nx, ny = e.x + svx * dt, e.y + svy * dt
  local mcx, mcy = self.map:screen_to_cell_coord(nx, ny)
  local vx, vy, force_move, tginfo
  if ginfo.total_used <= 1 and mcx == minfo.mcx and mcy == minfo.mcy then
    vx, vy = svx, svy
  else
    local gvx, gvy
    gvx, gvy, force_move, tginfo = self:_try_lock_space(e, svx, svy)
    local s = e.speed -- e.move_done and (e.speed * 0.5) or e.speed
    vx = svx + gvx * s
    vy = svy + gvy * s
  end

  local bvx, bvy = M._calc_block_velocity(e, obs)
  if bvx ~= 0 or bvy ~= 0 then
    local s = e.speed * 100
    vx = vx + bvx * s
    vy = vy + bvy * s
    e.force_move = true
  else
    e.force_move = force_move
  end

  -- fix speed
  local vspeed2 = Lume.length(vx, vy, true)
  if vspeed2 > e.speed2 then
    local s = e.speed / Sqrt(vspeed2)
    vx, vy = vx * s, vy * s
  end
  e.vx, e.vy = vx, vy
end

function M:try_move(e, dt)
  if e.vx == 0 and e.vy == 0 then
    e.current_speed = 0
    return
  end

  local x = e.x + e.vx * dt
  local y = e.y + e.vy * dt
  local mcx, mcy = self.map:screen_to_cell_coord(x, y)

  local minfo = e.move_info
  if mcx == minfo.mcx and mcy == minfo.mcy then
    e.x, e.y = x, y
  else
    if minfo.tginfo then
      if minfo.tginfo.move_e ~= e then
        minfo.tginfo = nil
        minfo.tmcx, minfo.tmcy = nil, nil
        if not minfo.force_move then
          e.current_speed = 0
          return
        end
      end
    else
      if not minfo.force_move then
        e.current_speed = 0
        return
      end
    end
    e.x, e.y = x, y
  end

  -- local minfo, ginfo = self:update_move_info(e)
  -- e.x = e.x + e.vx * dt
  -- e.y = e.y + e.vy * dt
  e.current_speed = Lume.length(e.vx, e.vy)
  e.angle = math.atan2(e.vy, e.vx)
end

function M:draw_all_grids()
  local lg = love.graphics
  for x = 1, self.map.w do
    for y = 1, self.map.h do
      local ginfo = self:get_grid_data(x, y)
      if ginfo then
        local color
        if ginfo.move_e then
          color = { 0, 1, 0, 0.5 }
        elseif ginfo.total_used > 0 then
          color = { 0, 0, 1, 0.3 + 0.1 * ginfo.total_used }
        end
        if color then
          lg.setColor(color)
          local sx, sy = self.map:cell_to_screen_coord(x, y)
          lg.rectangle('fill', sx, sy, self.map.cell_w, self.map.cell_h)
        end
      end
    end
  end
  lg.setColor(1, 1, 1, 1)
end

-------------------------

-- return vx, vy, force, tginfo
function M:_try_lock_space(e, vx, vy)
  -- local mcx, mcy = minfo.mcx, minfo.mcy
  local minfo = e.move_info
  local mfcx, mfcy = self.map:screen_to_cell_coord(e.x, e.y, false)
  local tx, ty = M._calc_next_grid(mfcx, mfcy, vx, vy)
  local tginfo = self:fetch_grid_data(tx, ty)
  if tginfo == minfo.tginfo then
    return vx, vy, false, tginfo
  elseif minfo.tginfo then
    minfo.tginfo.move_e = nil
    minfo.tmcx,minfo.tmcy = nil, nil
  end
  if M._try_lock_grid(e, minfo, tginfo, tx, ty) then
    return vx, vy, false, tginfo
  end

  local dx, dy = tx - minfo.mcx, ty - minfo.mcy
  local grids = { { tx, ty, tginfo, vx, vy } }
  tx, ty = minfo.mcx + dy, minfo.mcy - dx
  tginfo = self:fetch_grid_data(tx, ty)
  if M._try_lock_grid(e, minfo, tginfo, tx, ty) then
    return dy, -dx, false, tginfo
  end
  grids[#grids + 1] = { tx, ty, tginfo, dy, -dx }

  tx, ty = minfo.mcx - dy, minfo.mcy + dx
  tginfo = self:fetch_grid_data(tx, ty)
  if M._try_lock_grid(e, minfo, tginfo, tx, ty) then
    return -dy, dx, false, tginfo
  end
  grids[#grids + 1] = { tx, ty, tginfo, -dy, dx }

  local ginfo = minfo.ginfo
  -- local force_lock = ginfo.total_used > 1
  if ginfo.total_used > 1 then
    tx, ty = minfo.mcx - dx, minfo.mcy - dy
    tginfo = self:fetch_grid_data(tx, ty)
    if M._try_lock_grid(e, minfo, tginfo, tx, ty) then
      return -dx, -dy, false, tginfo
    end
    grids[#grids + 1] = { tx, ty, tginfo, -dx, -dy }

    for i, desc in ipairs(grids) do
      tx, ty, tginfo, vx, vy = unpack(desc)
      if M._try_lock_grid(e, minfo, tginfo, tx, ty, ginfo.total_used - 1) then
        return vx, vy, true, tginfo
      end
    end
  end

  return 0, 0, false
end

function M._try_lock_grid(e, minfo, tginfo, tx, ty, max_used)
  max_used = max_used or 0
  if tginfo.total_used <= max_used then
    local tme = tginfo.move_e
    if not tme or CmpEntity(e, tme) then
      tginfo.move_e = e
      minfo.tginfo = tginfo
      minfo.tmcx, minfo.tmcy = tx, ty
      return true
    end
  end
end

function M:update_move_info(e)
  local minfo = e.move_info
  if not minfo then
    minfo = {}
    e.move_info = minfo
  end

  local mcx, mcy = self.map:screen_to_cell_coord(e.x, e.y)
  local ginfo = self:fetch_grid_data(mcx, mcy)
  if minfo.mcx ~= mcx or minfo.mcy ~= mcy then
    if minfo.ginfo then
      local old_ginfo = minfo.ginfo
      old_ginfo.total_used = old_ginfo.total_used - 1
      if ginfo.top_e == e then
        ginfo.top_e = nil
      end
      if old_ginfo.total_used <= 0 then
        self:del_grid_data(minfo.mcx, minfo.mcy, old_ginfo)
      end
    end
    minfo.ginfo = ginfo
    ginfo.total_used = ginfo.total_used + 1
    if minfo.tginfo then
      if minfo.tginfo.move_e == e then
        minfo.tginfo.move_e = nil
      end
      minfo.tginfo = nil
      minfo.tmcx, minfo.tmcy = nil, nil
    end
    minfo.tmcx, minfo.tmcy = nil, nil
    if not ginfo.top_e or CmpEntity(e, ginfo.top_e) then
      ginfo.top_e = e
    end
    minfo.mcx = mcx
    minfo.mcy = mcy
  else
    if not ginfo.top_e or CmpEntity(e, ginfo.top_e) then
      ginfo.top_e = e
    end
    local tginfo = minfo.tginfo
    if e.vx == 0 and e.vy == 0 and tginfo then
      if tginfo.move_e == e then
        tginfo.move_e = nil
      end
      minfo.tginfo = nil
    end
  end
  return minfo, ginfo
end

function M:get_grid_data(x, y)
  local col = self.mdata[x]
  if col then
    return col[y]
  end
end

function M:fetch_grid_data(x, y)
  local col = self.mdata[x]
  if not col then
    col = {}
    self.mdata[x] = col
  end
  local v = col[y]
  if v == nil then
    v = {
      total_used = 0,
      top_e = nil,
      move_e = nil,
      try_e = nil,
    }
    col[y] = v
    self.total_grids = self.total_grids + 1
  end
  return v
end

function M:del_grid_data(x, y, check_val)
  local col = self.mdata[x]
  if col then
    if col[y] then
      self.total_grids = self.total_grids - 1
    end
    if not check_val or col[y] == check_val then
      col[y] = nil
    end
  end
end

function M._calc_block_velocity(e, obs)
  local vx, vy = 0, 0
  if obs.l then vx = vx + 1 end
  if obs.r then vx = vx - 1 end
  if obs.t then vy = vy + 1 end
  if obs.b then vy = vy - 1 end

  if obs.lt then vx, vy = vx + 1, vy + 1 end
  if obs.rt then vx, vy = vx - 1, vy + 1 end
  if obs.lb then vx, vy = vx + 1, vy - 1 end
  if obs.rb then vx, vy = vx - 1, vy - 1 end

  local len = Lume.length(vx, vy)
  if len > 0 then
    return vx / len, vy / len
  else
    return 0, 0
  end
end

function M._calc_next_grid(x, y, vx, vy)
  local ox = vx > 0 and 1 or -1
  local oy = vy > 0 and 1 or -1
  local sx, sy = Floor(x), Floor(y)
  local nx = sx + ox
  local ny = sy + oy

  local dx = Abs(nx - x)
  local dy = Abs(ny - y)
  if dx > 1 then dx = dx - 1 end
  if dy > 1 then dy = dy - 1 end
  local dx_y = Abs((dx) * vy / vx)

  local tx, ty
  if dx_y < dy then
    tx, ty = nx, sy
  else
    tx, ty = sx, ny
  end
  return tx, ty
end

return M