-- Engine/Grid.lua
-- Board geometry. 10 flat-top columns alternating 8 and 9 cells (85 total); column 1
-- is short, column 10 tall. Cells are numbered 1..85 column by column, top to bottom.
--
-- Vertical positions use half-cell units h: a tall (even) column's row r sits at
-- h = 2r - 2, a short (odd) column's at h = 2r - 1, so short columns hang half a cell
-- lower. Directions run clockwise on screen from north: N, NE, SE, S, SW, NW.
-- Pixel helpers use y growing downward with hex size (center to corner) of 1.

local _, ns = ...
local Grid = {}
ns.Grid = Grid

local SQRT3 = math.sqrt(3)
Grid.SQRT3 = SQRT3
Grid.COLS = 10
Grid.WIDTH = 2 + 1.5 * 9         -- board width in hex sizes
Grid.HEIGHT = 9 * SQRT3          -- board height in hex sizes

Grid.N_DIR, Grid.NE, Grid.SE, Grid.S_DIR, Grid.SW, Grid.NW = 1, 2, 3, 4, 5, 6
local DIRS = { { 0, -2 }, { 1, -1 }, { 1, 1 }, { 0, 2 }, { -1, 1 }, { -1, -1 } }

local function rowsIn(c) return (c % 2 == 1) and 8 or 9 end
Grid.rowsIn = rowsIn

local cells, at, byCH = {}, {}, {}
local n = 0
for c = 1, Grid.COLS do
  at[c], byCH[c] = {}, {}
  for r = 1, rowsIn(c) do
    n = n + 1
    local h = (c % 2 == 0) and (2 * r - 2) or (2 * r - 1)
    cells[n] = { c = c, r = r, h = h, x = 1 + (c - 1) * 1.5, y = (h + 1) * SQRT3 / 2 }
    at[c][r] = n
    byCH[c][h] = n
  end
end
Grid.N = n
Grid.cells = cells

function Grid.id(c, r)
  local col = at[c]
  return col and col[r] or nil
end

-- neighbors[id][d] is a cell id, or 0 when that side is off the board
local neighbors = {}
for id = 1, n do
  local cell, nb = cells[id], {}
  for d = 1, 6 do
    local col = byCH[cell.c + DIRS[d][1]]
    nb[d] = col and col[cell.h + DIRS[d][2]] or 0
  end
  neighbors[id] = nb
end
Grid.neighbors = neighbors

-- interior cells have all six neighbors; only they can be flower centers or pivots
local interior, rings = {}, {}
for id = 1, n do
  local nb, ok = neighbors[id], true
  for d = 1, 6 do if nb[d] == 0 then ok = false end end
  if ok then
    interior[id] = true
    rings[id] = { nb[1], nb[2], nb[3], nb[4], nb[5], nb[6] }   -- clockwise from N
  end
end
Grid.interior = interior
Grid.rings = rings

-- Pearl spokes. Type 1 is the upside-down Y (N, SE, SW); type 2 the Y (NE, S, NW).
-- Each list is clockwise, so rotating it is the same operation as rotating a triad.
Grid.PEARL_DIRS = { { 1, 3, 5 }, { 2, 4, 6 } }
function Grid.spokes(id, y)
  local ring = rings[id]
  if not ring then return nil end
  local d = Grid.PEARL_DIRS[y]
  return { ring[d[1]], ring[d[2]], ring[d[3]] }
end

-- Triads: three mutually adjacent cells around one vertex, stored clockwise. The same
-- list is the set of triangles that clusters are built from.
local triads, cellTriads, seen = {}, {}, {}
for id = 1, n do cellTriads[id] = {} end
for id = 1, n do
  local nb = neighbors[id]
  for d = 1, 6 do
    local a, b = nb[d], nb[d % 6 + 1]
    if a ~= 0 and b ~= 0 then
      local s = { id, a, b }
      table.sort(s)
      local key = s[1] * 10000 + s[2] * 100 + s[3]
      if not seen[key] then
        seen[key] = true
        local t = { id, a, b }
        local ca, cb, cc = cells[id], cells[a], cells[b]
        t.x = (ca.x + cb.x + cc.x) / 3
        t.y = (ca.y + cb.y + cc.y) / 3
        triads[#triads + 1] = t
        local ti = #triads
        for _, cid in ipairs(t) do
          local list = cellTriads[cid]
          list[#list + 1] = ti
        end
      end
    end
  end
end
Grid.triads = triads
Grid.cellTriads = cellTriads

function Grid.isAdjacent(a, b)
  local nb = neighbors[a]
  for d = 1, 6 do if nb[d] == b then return true end end
  return false
end

-- Move pieces one step around a clockwise cycle. dir 1 is clockwise (each piece moves
-- to the next position), -1 counterclockwise.
function Grid.rotate(board, cycle, dir)
  local k = #cycle
  if dir == 1 then
    local last = board[cycle[k]]
    for i = k, 2, -1 do board[cycle[i]] = board[cycle[i - 1]] end
    board[cycle[1]] = last
  else
    local first = board[cycle[1]]
    for i = 1, k - 1 do board[cycle[i]] = board[cycle[i + 1]] end
    board[cycle[k]] = first
  end
end

-- Proper 3-coloring of the hex grid (adjacent cells always differ). Used for test and
-- sandbox boards that must not contain matches.
function Grid.tricolor(id)
  local cell = cells[id]
  local q, rr = cell.c, (cell.h - cell.c) / 2
  return (q - rr) % 3 + 1
end
