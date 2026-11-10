-- Engine/Codec.lua
-- Run <-> plain table for SavedVariables. The board packs into a 255-character string
-- (3 per cell, see Pieces.encode). decode() validates everything and returns nil plus a
-- reason rather than a half-built game.

local _, ns = ...
local Grid, Pieces, Game, Rng = ns.Grid, ns.Pieces, ns.Game, ns.Rng
local Codec = {}
ns.Codec = Codec

Codec.VERSION = 1

local STAT_KEYS = { "clusters", "flowers", "stars", "pearls", "defused", "bestChain", "bestMove" }

function Codec.encode(game)
  local toks = {}
  for id = 1, Grid.N do toks[id] = Pieces.encode(game.board[id]) end
  local drops = {}
  for c = 1, Grid.COLS do
    local q = game.drops[c]
    if q and #q > 0 then
      local s = {}
      for i, p in ipairs(q) do s[i] = Pieces.encode(p) end
      drops[c] = table.concat(s)
    end
  end
  local stats = {}
  for _, k in ipairs(STAT_KEYS) do stats[k] = game.stats[k] or 0 end
  return {
    v = Codec.VERSION,
    cells = table.concat(toks),
    rng = game.rng.s,
    level = game.level,
    startLevel = game.startLevel,
    score = game.score,
    -- a run that ends mid-move can leave this below zero; -1 means endless (level 7)
    combosLeft = game.combosLeft and math.max(0, game.combosLeft) or -1,
    bombCombo = game.bombCombo,
    bombPending = game.bombPending,
    moves = game.moves,
    over = game.over,
    drops = drops,
    stats = stats,
  }
end

local function isInt(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and (not hi or v <= hi)
end

function Codec.decode(t)
  if type(t) ~= "table" then return nil, "no saved run" end
  if t.v ~= Codec.VERSION then return nil, "saved run has an unknown version" end
  if type(t.cells) ~= "string" or #t.cells ~= Grid.N * 3 then return nil, "board is the wrong size" end
  if not isInt(t.level, 1, Game.RULES.maxLevel) then return nil, "bad level" end
  if not isInt(t.rng, 1, 2147483646) then return nil, "bad random state" end
  if not isInt(t.score, 0) or not isInt(t.moves, 0) then return nil, "bad score" end
  if not isInt(t.combosLeft, -1) or not isInt(t.bombCombo, 0) or not isInt(t.bombPending, 0) then
    return nil, "bad counters"
  end
  if t.over ~= nil and t.over ~= "win" and t.over ~= "loss" then return nil, "bad result" end

  local game = Game.new({ empty = true, startLevel = t.level })
  game.startLevel = isInt(t.startLevel, 1, 7) and t.startLevel or t.level
  game.rng = Rng.new(t.rng)
  game.score, game.moves = t.score, t.moves
  game.combosLeft = t.combosLeft >= 0 and t.combosLeft or nil
  if t.level < Game.RULES.maxLevel and not game.combosLeft then return nil, "bad counters" end
  game.bombCombo, game.bombPending = t.bombCombo, t.bombPending
  game.over = t.over

  for id = 1, Grid.N do
    local p = Pieces.decode(t.cells:sub(id * 3 - 2, id * 3))
    if not p then return nil, "bad piece at cell " .. id end
    Game.place(game, id, p)
  end
  if type(t.drops) == "table" then
    for c = 1, Grid.COLS do
      local s = t.drops[c]
      if type(s) == "string" and #s % 3 == 0 then
        local q = {}
        for i = 1, #s, 3 do
          local p = Pieces.decode(s:sub(i, i + 2))
          if not p then return nil, "bad queued piece" end
          p.id = game.nextId
          game.nextId = game.nextId + 1
          q[#q + 1] = p
        end
        if #q > 0 then game.drops[c] = q end
      end
    end
  end
  if type(t.stats) == "table" then
    for _, k in ipairs(STAT_KEYS) do
      if isInt(t.stats[k], 0) then game.stats[k] = t.stats[k] end
    end
  end
  return game
end
