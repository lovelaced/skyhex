-- Random and greedy bots play many moves; invariants are checked after every move.
-- SKYHEX_FUZZ=<runs per start level> raises the count (default 6 runs x 400 moves).

local ns, T, H = ...
local Game, Codec, Search, Rng, Grid = ns.Game, ns.Codec, ns.Search, ns.Rng, ns.Grid
local describe, it, eq, ok = T.describe, T.it, T.eq, T.ok

local RUNS = tonumber(os.getenv("SKYHEX_FUZZ") or "") or 6
local MOVES = 400

local function bombCount(g)
  local n, low = 0, 99
  for id = 1, Grid.N do
    local b = g.board[id].bomb
    if b then
      n = n + 1
      if b < low then low = b end
    end
  end
  return n, low
end

-- With a bomb low on time, try matching moves on a copy and take one that defuses.
local function defuser(g, found)
  local nb, low = bombCount(g)
  if nb == 0 or low > 4 then return nil end
  local saved = Codec.encode(g)
  for i = 1, math.min(#found, 60) do
    local copy = Codec.decode(saved)
    Game.move(copy, found[i])
    if not copy.over and bombCount(copy) < nb then return found[i] end
  end
  return nil
end

-- Prefers moves that make a match, otherwise a random triad, ring or pearl turn.
local function pickMove(g, bot)
  local r = Rng.float(bot)
  if r < 0.75 then
    local found = Search.findMoves(g.board)
    if #found > 0 then return defuser(g, found) or found[Rng.int(bot, #found)] end
  end
  if r > 0.9 then
    for id = 1, Grid.N do
      local p = g.board[id]
      if Grid.interior[id] and (p.kind == "star" or p.kind == "pearl") then
        return { kind = p.kind == "star" and "ring" or "pearl", cell = id, dir = Rng.int(bot, 2) == 1 and 1 or -1 }
      end
    end
  end
  return { kind = "triad", index = Rng.int(bot, #Grid.triads), dir = Rng.int(bot, 2) == 1 and 1 or -1 }
end

local function checkInvariants(g, beats, where)
  local good, why = H.settled(g)
  ok(good, where .. ": " .. tostring(why))
  local ids = {}
  for id = 1, Grid.N do
    local p = g.board[id]
    ok(not ids[p.id], where .. ": piece id used twice")
    ids[p.id] = true
    if p.bomb then
      local low = g.over == "loss" and 0 or 1
      ok(p.bomb >= low and p.bomb <= 9, where .. ": bomb count " .. p.bomb)
    end
    if p.kind == "gem" then ok(p.color >= 1 and p.color <= 7, where .. ": color " .. tostring(p.color)) end
  end
  if not g.over then
    local shuffled
    for _, b in ipairs(beats) do
      if b.t == "shuffle" then shuffled = b end
    end
    ok(Search.hasMove(g.board) or (shuffled and not shuffled.ok), where .. ": no move left")
  end
  local t = Codec.encode(g)
  local g2 = assert(Codec.decode(t))
  eq(Codec.encode(g2).cells, t.cells, where .. ": codec")
end

describe("fuzz", function()
  local totals = { moves = 0, levels = {}, stars = 0, pearls = 0, chains = 0, bombs = 0, wins = 0, losses = 0, shuffles = 0 }

  it("plays thousands of moves without breaking an invariant", function()
    for _, start in ipairs({ 1, 3, 5 }) do
      for run = 1, RUNS do
        local seed = run * 7919 + start
        local g = Game.new({ seed = seed, startLevel = start })
        local bot = Rng.new(seed * 31)
        local log = {}
        for m = 1, MOVES do
          if g.over then break end
          local mv = pickMove(g, bot)
          log[#log + 1] = mv
          local beats = assert(Game.move(g, mv))
          totals.moves = totals.moves + 1
          for _, b in ipairs(beats) do
            if b.t == "fall" then
              for _, s in ipairs(b.spawns) do
                if s.piece.bomb then totals.bombs = totals.bombs + 1 end
              end
            elseif b.t == "shuffle" then
              totals.shuffles = totals.shuffles + 1
            end
          end
          checkInvariants(g, beats, string.format("start %d run %d move %d", start, run, m))
        end
        totals.levels[g.level] = (totals.levels[g.level] or 0) + 1
        totals.stars = totals.stars + g.stats.stars
        totals.pearls = totals.pearls + g.stats.pearls
        if g.stats.bestChain > 1 then totals.chains = totals.chains + 1 end
        if g.over == "win" then totals.wins = totals.wins + 1 elseif g.over == "loss" then totals.losses = totals.losses + 1 end

        -- the same seed and the same moves give the same run
        local again = Game.new({ seed = seed, startLevel = start })
        for _, mv in ipairs(log) do
          if again.over then break end
          Game.move(again, mv)
        end
        eq(Codec.encode(again).cells, Codec.encode(g).cells, "replay of seed " .. seed)
        eq(again.score, g.score, "replay score")
      end
    end
  end)

  it("exercises cascades, starflowers and bombs", function()
    local lv = {}
    for l = 1, 7 do if totals.levels[l] then lv[#lv + 1] = "L" .. l .. "x" .. totals.levels[l] end end
    print(string.format("  fuzz: %d moves, ended at %s, %d starflowers, %d pearls, %d runs with chains, %d bombs, %d wins, %d losses, %d shuffles",
      totals.moves, table.concat(lv, " "), totals.stars, totals.pearls, totals.chains, totals.bombs, totals.wins, totals.losses, totals.shuffles))
    ok(totals.chains > 0, "some run had a cascade")
    ok(totals.stars > 0, "bots made a starflower")
    ok(totals.bombs > 0, "bombs arrived")
  end)
end)
