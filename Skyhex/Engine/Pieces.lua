-- Engine/Pieces.lua
-- A piece is a small table that moves between cells, so its identity survives
-- rotations and falls (the UI keys tile frames on piece.id).
--   gem:    { kind = "gem", color = 1..7, bonus = true|nil, bomb = count|nil }
--   star:   { kind = "star" }            starflower: colorless, ring-rotates its neighbors
--   pearl:  { kind = "pearl", y = 1|2 }  black pearl: rotates three spokes (Grid.spokes)

local _, ns = ...
local Pieces = {}
ns.Pieces = Pieces

function Pieces.gem(color, bonus)
  return { kind = "gem", color = color, bonus = bonus or nil }
end

function Pieces.bomb(color, count)
  return { kind = "gem", color = color, bomb = count }
end

function Pieces.star()
  return { kind = "star" }
end

function Pieces.pearl(y)
  return { kind = "pearl", y = y }
end

function Pieces.copy(p)
  return { kind = p.kind, color = p.color, bonus = p.bonus, bomb = p.bomb, y = p.y, id = p.id }
end

function Pieces.equal(a, b)
  return a.kind == b.kind and a.color == b.color and a.bonus == b.bonus and a.bomb == b.bomb and a.y == b.y
end

-- 3-character token per piece for saving: g<color><* or .>, b<color><count>, s.., p<y>.
function Pieces.encode(p)
  if p.kind == "gem" then
    if p.bomb then return "b" .. p.color .. p.bomb end
    return "g" .. p.color .. (p.bonus and "*" or ".")
  elseif p.kind == "star" then
    return "s.."
  elseif p.kind == "pearl" then
    return "p" .. p.y .. "."
  end
  error("unknown piece kind " .. tostring(p.kind))
end

function Pieces.decode(tok)
  local k, a, b = tok:sub(1, 1), tok:sub(2, 2), tok:sub(3, 3)
  if k == "g" then
    local color = tonumber(a)
    if not color or color < 1 or color > 7 or (b ~= "*" and b ~= ".") then return nil end
    return Pieces.gem(color, b == "*")
  elseif k == "b" then
    local color, count = tonumber(a), tonumber(b)
    -- 0 is legal: the bomb that ended a lost run stays on its board
    if not color or color < 1 or color > 7 or not count or count < 0 then return nil end
    return Pieces.bomb(color, count)
  elseif k == "s" and a == "." and b == "." then
    return Pieces.star()
  elseif k == "p" and (a == "1" or a == "2") and b == "." then
    return Pieces.pearl(tonumber(a))
  end
  return nil
end
