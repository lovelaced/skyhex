-- Engine/Scenes.lua
-- Practice boards for `/skyhex try <name>`: each is one move away from a special event,
-- so the rules can be checked without playing for hours. The background is a proper
-- 3-coloring in colors 3 to 5, which can't match anything; the scene itself uses
-- colors 1 and 2 and special pieces. Each builder returns the game and the move.

local _, ns = ...
local Grid, Game, Pieces = ns.Grid, ns.Game, ns.Pieces
local Scenes = {}
ns.Scenes = Scenes

local function base(level, seed)
  local g = Game.new({ empty = true, startLevel = level, seed = seed })
  for id = 1, Grid.N do Game.place(g, id, Pieces.gem(Grid.tricolor(id) + 2)) end
  return g
end

local function put(g, c, r, p)
  Game.place(g, Grid.id(c, r), p)
end

local function triad(a, b, c)
  local want = { [a] = true, [b] = true, [c] = true }
  for i, t in ipairs(Grid.triads) do
    if want[t[1]] and want[t[2]] and want[t[3]] then return i end
  end
end

-- the triad that swaps a piece from (4,6) into the S slot of (4,4)'s ring
local function intoRing()
  return { kind = "triad", index = triad(Grid.id(4, 5), Grid.id(4, 6), Grid.id(5, 5)), dir = 1 }
end

-- the triad that brings (5,6) up into (5,5), next to (4,5) and (4,6)
local function intoTriangle()
  return { kind = "triad", index = triad(Grid.id(5, 5), Grid.id(5, 6), Grid.id(6, 6)), dir = 1 }
end

local function almostRing(g, make, center)
  put(g, 4, 4, center)
  for _, cell in ipairs(Grid.rings[Grid.id(4, 4)]) do
    if cell ~= Grid.id(4, 5) then Game.place(g, cell, make()) end
  end
  put(g, 4, 6, make())
end

Scenes.order = { "flower", "pearl", "bomb", "wipe", "win" }

Scenes.info = {
  flower = "Turn the marked tiles to ring a gem with six of one color. It becomes a starflower.",
  pearl = "Ring a gem with six starflowers to make a black pearl.",
  bomb = "Match the bomb's color before its counter runs out. Watch for a new one dropping in.",
  wipe = "Defuse a bomb with a bonus gem of its color to clear that color everywhere.",
  win = "Three touching black pearls win the run.",
}

Scenes.build = {
  flower = function(seed)
    local g = base(1, seed)
    almostRing(g, function() return Pieces.gem(1) end, Pieces.gem(2))
    return g, intoRing()
  end,
  pearl = function(seed)
    local g = base(1, seed)
    almostRing(g, Pieces.star, Pieces.gem(2))
    return g, intoRing()
  end,
  bomb = function(seed)
    local g = base(3, seed)
    put(g, 4, 5, Pieces.bomb(1, 3)); put(g, 4, 6, Pieces.gem(1)); put(g, 5, 6, Pieces.gem(1))
    g.bombPending = 1 -- a fresh bomb drops in as this one is defused
    return g, intoTriangle()
  end,
  wipe = function(seed)
    local g = base(3, seed)
    put(g, 4, 5, Pieces.bomb(1, 4)); put(g, 4, 6, Pieces.gem(1, true)); put(g, 5, 6, Pieces.gem(1))
    put(g, 1, 2, Pieces.gem(1)); put(g, 8, 2, Pieces.gem(1, true)); put(g, 9, 7, Pieces.gem(1))
    put(g, 7, 5, Pieces.gem(1)); put(g, 2, 8, Pieces.gem(1))
    return g, intoTriangle()
  end,
  win = function(seed)
    local g = base(5, seed)
    put(g, 4, 5, Pieces.pearl(1)); put(g, 4, 6, Pieces.pearl(2)); put(g, 5, 6, Pieces.pearl(1))
    return g, intoTriangle()
  end,
}
