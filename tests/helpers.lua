-- tests/helpers.lua
-- Board-building helpers for engine specs.

return function(ns, T)
  local Grid, Pieces, Game = ns.Grid, ns.Pieces, ns.Game
  local H = {}

  function H.id(c, r)
    local id = Grid.id(c, r)
    assert(id, "no cell " .. c .. "," .. r)
    return id
  end

  -- A game where every piece has its own made-up color (1001, 1002, ...) and new pieces
  -- do too, so nothing matches except what a spec places with colors 1 to 7.
  function H.blank(level)
    local inert = 1000
    local g = Game.new({
      empty = true,
      startLevel = level or 1,
      seed = 7,
      noShuffle = true,
      spawn = function()
        inert = inert + 1
        return Pieces.gem(inert)
      end,
    })
    for id = 1, Grid.N do
      inert = inert + 1
      Game.place(g, id, Pieces.gem(inert))
    end
    return g
  end

  function H.put(g, c, r, piece)
    return Game.place(g, H.id(c, r), piece)
  end

  function H.ring(c, r)
    return Grid.rings[H.id(c, r)]
  end

  -- index of the triad made of exactly these three cells
  function H.triad(a, b, c)
    local want = { [a] = true, [b] = true, [c] = true }
    for i, t in ipairs(Grid.triads) do
      if want[t[1]] and want[t[2]] and want[t[3]] then return i end
    end
    error("no triad with those cells")
  end

  -- cell currently holding the piece with this id, or nil
  function H.where(g, pieceId)
    for id = 1, Grid.N do
      if g.board[id] and g.board[id].id == pieceId then return id end
    end
    return nil
  end

  function H.beats(beats, t)
    local out = {}
    for _, b in ipairs(beats) do
      if b.t == t then out[#out + 1] = b end
    end
    return out
  end

  function H.countKind(g, kind)
    local n = 0
    for id = 1, Grid.N do
      if g.board[id].kind == kind then n = n + 1 end
    end
    return n
  end

  function H.bombs(g)
    local out = {}
    for id = 1, Grid.N do
      if g.board[id].bomb then out[#out + 1] = g.board[id] end
    end
    return out
  end

  function H.snapshot(g)
    local s = {}
    for id = 1, Grid.N do s[id] = g.board[id].id end
    return s
  end

  -- every cell filled, nothing left to match
  function H.settled(g)
    for id = 1, Grid.N do
      if not g.board[id] then return false, "empty cell " .. id end
    end
    if ns.Detect.find(g.board).any then return false, "unresolved match" end
    return true
  end

  return H
end
