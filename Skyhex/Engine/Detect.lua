-- Engine/Detect.lua
-- Finds flowers and clusters on a settled board.
--
-- Flower: six pieces of one kind ring an interior center.
--   color: six gems of one color around a center that is not a gem of that color
--   star:  six starflowers around any center (makes a black pearl)
--   pearl: six pearls around any center (wins the run)
-- Cluster: triangles (Grid.triads) whose three pieces all match, merged into one
-- cluster when triangles share a piece.
--   color: three gems of one color      bonus: three bonus gems of any colors
--   star:  three starflowers            pearl: three pearls (wins the run)
-- Flowers claim their ring pieces first, so a triangle touching a ring is ignored.

local _, ns = ...
local Grid = ns.Grid
local Detect = {}
ns.Detect = Detect

local N, rings, triads, cellTriads, neighbors = Grid.N, Grid.rings, Grid.triads, Grid.cellTriads, Grid.neighbors

function Detect.flowerAt(board, id)
  local ring = rings[id]
  if not ring then return nil end
  local first = board[ring[1]]
  if not first or not board[id] then return nil end
  if first.kind == "gem" then
    local color = first.color
    for i = 2, 6 do
      local p = board[ring[i]]
      if not p or p.kind ~= "gem" or p.color ~= color then return nil end
    end
    local center = board[id]
    -- PROPOSAL: a same-color center makes this a 7-piece color cluster, not a flower
    if center.kind == "gem" and center.color == color then return nil end
    return { center = id, ring = ring, cat = "color", color = color }
  end
  local kind = first.kind
  for i = 2, 6 do
    local p = board[ring[i]]
    if not p or p.kind ~= kind then return nil end
  end
  return { center = id, ring = ring, cat = kind }
end

-- What a triangle matches as: color (number or nil), bonus, star, pearl (booleans)
local function triangleMatch(board, t)
  local a, b, c = board[t[1]], board[t[2]], board[t[3]]
  if not (a and b and c) then return nil end
  local k = a.kind
  if k ~= b.kind or k ~= c.kind then return nil end
  if k == "gem" then
    local color = (a.color == b.color and b.color == c.color) and a.color or nil
    local bonus = (a.bonus and b.bonus and c.bonus) and true or nil
    return color, bonus
  elseif k == "star" then
    return nil, nil, true
  else
    return nil, nil, nil, true
  end
end
Detect.triangleMatch = triangleMatch

-- Fast check after a rotation: on a settled board any new match has to involve one of
-- the cells that moved, so only their triangles and nearby flower centers are checked.
function Detect.anyNear(board, changed)
  for _, id in ipairs(changed) do
    for _, ti in ipairs(cellTriads[id]) do
      local color, bonus, star, pearl = triangleMatch(board, triads[ti])
      if color or bonus or star or pearl then return true end
    end
    if Detect.flowerAt(board, id) then return true end
    local nb = neighbors[id]
    for d = 1, 6 do
      local m = nb[d]
      if m ~= 0 and Detect.flowerAt(board, m) then return true end
    end
  end
  return false
end

local function root(p, x)
  while p[x] ~= x do
    p[x] = p[p[x]]
    x = p[x]
  end
  return x
end

local function join(p, t)
  for i = 1, 3 do if not p[t[i]] then p[t[i]] = t[i] end end
  local ra = root(p, t[1])
  for i = 2, 3 do
    local rb = root(p, t[i])
    if rb ~= ra then p[rb] = ra end
  end
end

local CATS = { "color", "bonus", "star", "pearl" }

function Detect.find(board)
  local res = { flowers = {}, clusters = {}, any = false }
  local claimed = {}
  for id = 1, N do
    local f = Detect.flowerAt(board, id)
    if f then
      res.flowers[#res.flowers + 1] = f
      for i = 1, 6 do claimed[f.ring[i]] = true end
    end
  end

  local uf = { color = {}, bonus = {}, star = {}, pearl = {} }
  for _, t in ipairs(triads) do
    if not (claimed[t[1]] or claimed[t[2]] or claimed[t[3]]) then
      local color, bonus, star, pearl = triangleMatch(board, t)
      if color then join(uf.color, t) end
      if bonus then join(uf.bonus, t) end
      if star then join(uf.star, t) end
      if pearl then join(uf.pearl, t) end
    end
  end

  for _, cat in ipairs(CATS) do
    local p, groups, order = uf[cat], {}, {}
    for id = 1, N do
      if p[id] then
        local r = root(p, id)
        local g = groups[r]
        if not g then
          g = { cat = cat, cells = {} }
          groups[r] = g
          order[#order + 1] = g
        end
        g.cells[#g.cells + 1] = id
      end
    end
    for _, g in ipairs(order) do
      if cat == "color" then
        g.color = board[g.cells[1]].color
      elseif cat == "bonus" then
        local c0, mono = board[g.cells[1]].color, true
        for _, id in ipairs(g.cells) do
          if board[id].color ~= c0 then mono = false end
        end
        g.mono = mono and c0 or nil
      end
      res.clusters[#res.clusters + 1] = g
    end
  end

  res.any = #res.flowers > 0 or #res.clusters > 0
  return res
end
